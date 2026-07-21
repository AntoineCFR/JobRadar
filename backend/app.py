"""API Flask JobRadar.

Endpoints :
  GET  /health          -> statut + dépendances prêtes
  POST /scrape          -> lance un run (async) ; protégé par un secret partagé
  GET  /status          -> résumé du dernier run en mémoire

Le run tourne dans un thread : l'app déclenche puis observe Firestore en direct.
"""
from __future__ import annotations

import logging
import threading

from flask import Flask, request, jsonify

import config
import pipeline

logging.basicConfig(level=getattr(logging, config.LOG_LEVEL, logging.INFO),
                    format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("jobradar.api")

app = Flask(__name__)

# État minimal du dernier/du run courant (mémoire process).
_state: dict = {"running": False, "last": None}
_lock = threading.Lock()


def _authorized(req) -> bool:
    if not config.API_SHARED_SECRET:
        return True  # pas de secret configuré -> ouvert (dev)
    return req.headers.get("X-JobRadar-Key") == config.API_SHARED_SECRET


def _run_async(keyword: str, location: str, max_pages: int):
    with _lock:
        _state["running"] = True
    try:
        summary = pipeline.run_scrape(keyword, location, max_pages=max_pages)
        with _lock:
            _state["last"] = summary
    except Exception as e:  # noqa: BLE001
        log.exception("run failed")
        with _lock:
            _state["last"] = {"error": str(e)}
    finally:
        with _lock:
            _state["running"] = False


@app.get("/health")
def health():
    return jsonify(
        status="ok",
        mistral=config.mistral_ready(),
        firestore=config.firestore_ready(),
        running=_state["running"],
    )


@app.post("/scrape")
def scrape():
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    body = request.get_json(silent=True) or {}
    keyword = (body.get("keyword") or "").strip()
    location = (body.get("location") or "").strip()
    max_pages = int(body.get("max_pages") or config.SCRAPE_MAX_PAGES)
    if not keyword:
        return jsonify(error="keyword is required"), 400
    with _lock:
        if _state["running"]:
            return jsonify(status="already_running"), 409
    t = threading.Thread(target=_run_async, args=(keyword, location, max_pages), daemon=True)
    t.start()
    return jsonify(status="started", keyword=keyword, location=location), 202


@app.get("/status")
def status():
    return jsonify(running=_state["running"], last=_state["last"])


@app.post("/profile/analyze")
def profile_analyze():
    """Reçoit un PDF de profil (multipart 'file' + 'uid'), l'OCR + le structure,
    le stocke, puis relance le matching de toutes les offres en tâche de fond."""
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    uid = (request.form.get("uid") or "").strip()
    file = request.files.get("file")
    if not uid or not file:
        return jsonify(error="uid et file requis"), 400
    try:
        from matching import build_profile
        from store import firestore_store

        doc = build_profile(file.read(), file.filename or "profil.pdf")
        firestore_store.set_profile(uid, doc)
    except Exception as e:  # noqa: BLE001
        log.exception("profile analyze failed")
        return jsonify(error=str(e)), 500

    # Re-match de fond (le profil a changé).
    def _rematch():
        try:
            pipeline.run_matching(force=True)
        except Exception:  # noqa: BLE001
            log.exception("re-match after profile failed")

    threading.Thread(target=_rematch, daemon=True).start()
    return jsonify(status="ok", version=doc["version"], structured=doc["structured"]), 200


@app.post("/match")
def match():
    """Relance le matching des offres en attente (missing/stale) en tâche de fond."""
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    force = bool((request.get_json(silent=True) or {}).get("force"))

    def _run():
        try:
            pipeline.run_matching(force=force)
        except Exception:  # noqa: BLE001
            log.exception("match run failed")

    threading.Thread(target=_run, daemon=True).start()
    return jsonify(status="started"), 202


@app.post("/admin/reprocess")
def admin_reprocess():
    """Re-passe une offre existante dans la chaîne d'extraction (validation/debug).

    Body {id}. Renvoie les champs enrichis pour inspection.
    """
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    offer_id = str((request.get_json(silent=True) or {}).get("id") or "")
    if not offer_id:
        return jsonify(error="id requis"), 400
    try:
        from store import firestore_store
        from extraction.agents import process_offer

        offer = firestore_store.get_offer(offer_id)
        if not offer:
            return jsonify(error="offre introuvable"), 404
        offer["id"] = offer_id
        offer = process_offer(offer)
        firestore_store.upsert_offer(offer)
        return jsonify(
            id=offer_id,
            software=offer.get("software"),
            technical_skills=offer.get("technical_skills"),
            soft_skills=offer.get("soft_skills"),
            benefits_categorized=offer.get("benefits_categorized"),
            summary=offer.get("summary"),
        )
    except Exception as e:  # noqa: BLE001
        log.exception("reprocess failed")
        return jsonify(error=str(e)), 500


@app.post("/admin/setup-agents")
def setup_agents():
    """Crée (ou retrouve) les agents Mistral dédiés et renvoie leurs IDs.

    Protégé par le secret partagé. Idempotent : ne crée pas de doublon.
    """
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    try:
        from extraction.agents import _get_client
        from extraction.agents_setup import ensure_agents

        ids = ensure_agents(_get_client())
        return jsonify(status="ok", agents=ids)
    except Exception as e:  # noqa: BLE001
        log.exception("setup-agents failed")
        return jsonify(error=str(e)), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=config.PORT)
