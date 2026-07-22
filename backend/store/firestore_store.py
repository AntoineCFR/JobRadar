"""Écriture des offres dans Firestore (source de vérité lue par l'app).

Collections :
  - `offers`       : 1 doc par offre (id = id jobs.cz).
  - `scrape_runs`  : historique des exécutions (pour l'app / le debug).

Les imports firebase-admin sont tardifs : le module s'importe même sans la
dépendance installée (utile pour les tests locaux du scraper).
"""
from __future__ import annotations

import json
import logging
from typing import Iterable, Optional

import config

log = logging.getLogger("jobradar.firestore")

_db = None


def init():
    """Initialise firebase-admin (idempotent). Lève si les credentials manquent."""
    global _db
    if _db is not None:
        return _db
    import firebase_admin
    from firebase_admin import credentials, firestore

    if not firebase_admin._apps:
        if config.FIREBASE_CREDENTIALS_JSON:
            cred = credentials.Certificate(json.loads(config.FIREBASE_CREDENTIALS_JSON))
        else:
            path = config.resolve_credentials_file()
            if not path:
                raise RuntimeError(
                    "Aucun credential Firebase trouvé : définir FIREBASE_CREDENTIALS_JSON "
                    "ou fournir un fichier serviceAccount.json (Secret File Render)."
                )
            cred = credentials.Certificate(path)
        firebase_admin.initialize_app(cred)
    _db = firestore.client()
    return _db


def get_existing_ids(ids: Iterable[str]) -> set[str]:
    """Retourne le sous-ensemble d'ids déjà présents dans `offers`."""
    db = init()
    existing: set[str] = set()
    col = db.collection(config.FIRESTORE_OFFERS_COLLECTION)
    ids = list(ids)
    for i in range(0, len(ids), 30):  # get_all par lots
        refs = [col.document(str(x)) for x in ids[i : i + 30]]
        for snap in db.get_all(refs):
            if snap.exists:
                existing.add(snap.id)
    return existing


def upsert_offer(rec: dict, search_ctx: Optional[dict] = None) -> bool:
    """Écrit/mets à jour une offre. Retourne True si l'offre est nouvelle."""
    from firebase_admin import firestore

    db = init()
    ref = db.collection(config.FIRESTORE_OFFERS_COLLECTION).document(str(rec["id"]))
    snap = ref.get()
    is_new = not snap.exists

    data = dict(rec)
    data.pop("raw_sections", None)  # volumineux, pas utile à l'app
    data["last_scraped_at"] = firestore.SERVER_TIMESTAMP
    data["status"] = "active"
    if search_ctx:
        # on mémorise la/les recherche(s) qui ont trouvé l'offre
        data["searches"] = firestore.ArrayUnion([f"{search_ctx.get('keyword','')}|{search_ctx.get('location','')}"])

    if is_new:
        data["first_seen_at"] = firestore.SERVER_TIMESTAMP
        data["is_read"] = False
    ref.set(data, merge=True)
    return is_new


def get_config(doc_id: str) -> dict | None:
    """Lit un doc de la collection `config` (ex. IDs d'agents Mistral)."""
    db = init()
    snap = db.collection(config.FIRESTORE_CONFIG_COLLECTION).document(doc_id).get()
    return snap.to_dict() if snap.exists else None


def set_config(doc_id: str, data: dict) -> None:
    db = init()
    db.collection(config.FIRESTORE_CONFIG_COLLECTION).document(doc_id).set(data, merge=True)


def get_daily_searches(seed_if_empty: bool = True) -> list[dict]:
    """Recherches à lancer par le cron, lues depuis la collection `searches`.

    Chaque doc : {keyword, location, enabled}. Si la collection est vide, on
    l'amorce avec `config.DEFAULT_DAILY_SEARCHES` (pour que l'app ait de quoi
    afficher / éditer) et on renvoie ce défaut.
    """
    from firebase_admin import firestore

    db = init()
    col = db.collection(config.FIRESTORE_SEARCHES_COLLECTION)
    out = []
    for d in col.stream():
        data = d.to_dict() or {}
        if data.get("enabled", True) and data.get("keyword"):
            out.append({"keyword": data["keyword"], "location": data.get("location", "")})
    if out:
        return out
    if seed_if_empty:
        for s in config.DEFAULT_DAILY_SEARCHES:
            col.add({
                "keyword": s["keyword"],
                "location": s.get("location", ""),
                "enabled": True,
                "created_at": firestore.SERVER_TIMESTAMP,
            })
    return list(config.DEFAULT_DAILY_SEARCHES)


def get_offer(offer_id: str) -> dict | None:
    db = init()
    snap = db.collection(config.FIRESTORE_OFFERS_COLLECTION).document(offer_id).get()
    return snap.to_dict() if snap.exists else None


def get_profile(uid: str) -> dict | None:
    db = init()
    snap = db.collection(config.FIRESTORE_PROFILES_COLLECTION).document(uid).get()
    return snap.to_dict() if snap.exists else None


def set_profile(uid: str, data: dict) -> None:
    # PAS de merge : un nouveau document de profil REMPLACE entièrement l'ancien
    # (sinon Firestore fusionne récursivement les maps et garde de vieux sous-champs).
    db = init()
    db.collection(config.FIRESTORE_PROFILES_COLLECTION).document(uid).set(data)


def first_profile() -> tuple[str, dict] | None:
    """App mono-utilisateur : renvoie (uid, profil) du 1er profil trouvé, ou None."""
    db = init()
    for d in db.collection(config.FIRESTORE_PROFILES_COLLECTION).limit(1).stream():
        return d.id, (d.to_dict() or {})
    return None


def stream_offers() -> list[tuple[str, dict]]:
    db = init()
    return [(d.id, d.to_dict() or {}) for d in db.collection(config.FIRESTORE_OFFERS_COLLECTION).stream()]


# --------------------------------------------------------------------------- #
# Entreprises (collection `companies`) — localisation déduite par agent.
# --------------------------------------------------------------------------- #
_COMPANIES = "companies"


def set_company(key: str, data: dict) -> None:
    db = init()
    db.collection(_COMPANIES).document(key).set(data, merge=True)


def get_company(key: str) -> dict | None:
    db = init()
    snap = db.collection(_COMPANIES).document(key).get()
    return snap.to_dict() if snap.exists else None


def list_company_keys() -> set[str]:
    db = init()
    return {d.id for d in db.collection(_COMPANIES).list_documents()}


def reconcile_search_expiry(search_key: str, current_ids: set[str]) -> dict:
    """Après un scraping du mot-clé `search_key` ("keyword|location") :
      - marque `status="expired"` (+ `expired_at`) les offres ACTIVES de cette
        recherche ABSENTES des résultats courants ;
      - RÉACTIVE (status="active") celles qui réapparaissent.
    N'écrit que sur changement d'état. Détection SIMPLE : une offre retrouvée par
    une AUTRE recherche sera réactivée par le scraping de celle-ci.
    """
    from firebase_admin import firestore

    db = init()
    col = db.collection(config.FIRESTORE_OFFERS_COLLECTION)
    expired = reactivated = 0
    for snap in col.where("searches", "array_contains", search_key).stream():
        d = snap.to_dict() or {}
        status = d.get("status", "active")
        found = snap.id in current_ids
        if found and status == "expired":
            snap.reference.set(
                {"status": "active", "expired_at": firestore.DELETE_FIELD}, merge=True
            )
            reactivated += 1
        elif not found and status != "expired":
            snap.reference.set(
                {"status": "expired", "expired_at": firestore.SERVER_TIMESTAMP}, merge=True
            )
            expired += 1
    if expired or reactivated:
        log.info("expiry[%s]: %s expirées, %s réactivées", search_key, expired, reactivated)
    return {"expired": expired, "reactivated": reactivated}


def purge_expired(days: int = 30) -> int:
    """Supprime définitivement les offres expirées depuis plus de `days` jours."""
    import datetime as _dt

    db = init()
    col = db.collection(config.FIRESTORE_OFFERS_COLLECTION)
    cutoff = _dt.datetime.now(_dt.timezone.utc) - _dt.timedelta(days=days)
    purged = 0
    for snap in col.where("status", "==", "expired").stream():
        exp = (snap.to_dict() or {}).get("expired_at")
        # `expired_at` est un Timestamp Firestore (tz-aware) une fois relu.
        if exp is not None and hasattr(exp, "timestamp") and exp < cutoff:
            snap.reference.delete()
            purged += 1
    if purged:
        log.info("purge_expired: %s offres supprimées (> %s j)", purged, days)
    return purged


def set_offer_match(offer_id: str, match: dict, profile_version: str) -> None:
    db = init()
    payload = dict(match)
    payload["profile_version"] = profile_version
    db.collection(config.FIRESTORE_OFFERS_COLLECTION).document(offer_id).set(
        {"match": payload}, merge=True
    )


def record_run(summary: dict) -> str:
    """Enregistre un run de scraping ; retourne l'id du doc."""
    from firebase_admin import firestore

    db = init()
    payload = dict(summary)
    payload["created_at"] = firestore.SERVER_TIMESTAMP
    _, ref = db.collection(config.FIRESTORE_RUNS_COLLECTION).add(payload)
    return ref.id
