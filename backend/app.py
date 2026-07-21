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


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=config.PORT)
