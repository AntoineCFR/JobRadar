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


def record_run(summary: dict) -> str:
    """Enregistre un run de scraping ; retourne l'id du doc."""
    from firebase_admin import firestore

    db = init()
    payload = dict(summary)
    payload["created_at"] = firestore.SERVER_TIMESTAMP
    _, ref = db.collection(config.FIRESTORE_RUNS_COLLECTION).add(payload)
    return ref.id
