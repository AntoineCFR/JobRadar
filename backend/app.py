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
_state: dict = {"running": False, "last": None, "progress": None}
_lock = threading.Lock()


def _progress_cb(done: int, total: int, phase: str = "") -> None:
    with _lock:
        _state["progress"] = {"done": done, "total": total, "phase": phase}


def _clear_progress() -> None:
    with _lock:
        _state["progress"] = None


def _authorized(req) -> bool:
    if not config.API_SHARED_SECRET:
        return True  # pas de secret configuré -> ouvert (dev)
    return req.headers.get("X-JobRadar-Key") == config.API_SHARED_SECRET


def _run_async(keyword: str, location: str, max_pages: int):
    with _lock:
        _state["running"] = True
    try:
        summary = pipeline.run_scrape(keyword, location, max_pages=max_pages, progress=_progress_cb)
        with _lock:
            _state["last"] = summary
    except Exception as e:  # noqa: BLE001
        log.exception("run failed")
        with _lock:
            _state["last"] = {"error": str(e)}
    finally:
        _clear_progress()
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
    return jsonify(running=_state["running"], last=_state["last"], progress=_state["progress"])


@app.get("/count")
def count():
    """Nombre d'offres en base (léger : liste les refs, ne lit pas les docs)."""
    try:
        from store import firestore_store

        db = firestore_store.init()
        n = sum(1 for _ in db.collection(config.FIRESTORE_OFFERS_COLLECTION).list_documents())
        return jsonify(offers=n)
    except Exception as e:  # noqa: BLE001
        return jsonify(error=str(e)), 500


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
        from matching import build_profile, merge_structured
        from store import firestore_store

        doc = build_profile(file.read(), file.filename or "profil.pdf")
        # Fusion intelligente : le document ne met à jour QUE les sections qu'il
        # mentionne ; le reste du profil (édité à la main ou issu d'autres docs)
        # est conservé.
        existing = firestore_store.get_profile(uid) or {}
        doc["structured"] = merge_structured(
            existing.get("structured") or {}, doc.get("structured") or {}
        )
        firestore_store.set_profile(uid, doc)
    except Exception as e:  # noqa: BLE001
        log.exception("profile analyze failed")
        return jsonify(error=str(e)), 500

    # Re-match de fond (le profil a changé).
    def _rematch():
        with _lock:
            _state["running"] = True
        try:
            pipeline.run_matching(force=True, progress=_progress_cb)
        except Exception:  # noqa: BLE001
            log.exception("re-match after profile failed")
        finally:
            _clear_progress()
            with _lock:
                _state["running"] = False

    threading.Thread(target=_rematch, daemon=True).start()
    return jsonify(status="ok", version=doc["version"], structured=doc["structured"]), 200


@app.post("/run-searches")
def run_searches():
    """Boucle complète : re-scrape toutes les recherches surveillées (collection
    `searches`) -> extraction -> matching. En tâche de fond."""
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    with _lock:
        if _state["running"]:
            return jsonify(status="already_running"), 409
        _state["running"] = True

    def _run():
        try:
            from store import firestore_store

            searches = firestore_store.get_daily_searches()
            runs = []
            for s in searches:
                if s.get("keyword"):
                    runs.append(pipeline.run_scrape(s["keyword"], s.get("location", ""), progress=_progress_cb))
            with _lock:
                _state["last"] = {"searches": len(searches), "runs": runs}
        except Exception as e:  # noqa: BLE001
            log.exception("run-searches failed")
            with _lock:
                _state["last"] = {"error": str(e)}
        finally:
            _clear_progress()
            with _lock:
                _state["running"] = False

    threading.Thread(target=_run, daemon=True).start()
    return jsonify(status="started"), 202


@app.post("/match")
def match():
    """Relance le matching des offres en attente (missing/stale) en tâche de fond."""
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    force = bool((request.get_json(silent=True) or {}).get("force"))

    def _run():
        with _lock:
            _state["running"] = True
        try:
            pipeline.run_matching(force=force, progress=_progress_cb)
        except Exception:  # noqa: BLE001
            log.exception("match run failed")
        finally:
            _clear_progress()
            with _lock:
                _state["running"] = False

    threading.Thread(target=_run, daemon=True).start()
    return jsonify(status="started"), 202


@app.post("/match-one")
def match_one():
    """(Re)matche UNE seule offre avec le profil courant, de façon SYNCHRONE.

    Body {id}. Utilisé par l'app après une édition de compétences (bouton
    « actualiser le matching de cette offre »). Renvoie le résultat ; l'app le
    verra aussi arriver en direct via Firestore.
    """
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    offer_id = str((request.get_json(silent=True) or {}).get("id") or "")
    if not offer_id:
        return jsonify(error="id requis"), 400
    try:
        from store import firestore_store
        from matching import match_offer

        prof = firestore_store.first_profile()
        if not prof:
            return jsonify(error="aucun profil"), 400
        _, profile = prof
        offer = firestore_store.get_offer(offer_id)
        if not offer:
            return jsonify(error="offre introuvable"), 404
        offer["id"] = offer_id
        result = match_offer(profile.get("structured") or {}, offer)
        if result:
            firestore_store.set_offer_match(offer_id, result, profile.get("version", ""))
        return jsonify(status="ok", match=result), 200
    except Exception as e:  # noqa: BLE001
        log.exception("match-one failed")
        return jsonify(error=str(e)), 500


@app.post("/companies/locate")
def companies_locate():
    """Localise (agent Mistral) les entreprises SANS fiche, en tâche de fond."""
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    only_missing = bool((request.get_json(silent=True) or {}).get("only_missing", True))
    with _lock:
        if _state["running"]:
            return jsonify(status="already_running"), 409
        _state["running"] = True

    def _run():
        try:
            import companies

            summary = companies.locate_all(only_missing=only_missing, progress=_progress_cb)
            with _lock:
                _state["last"] = summary
        except Exception as e:  # noqa: BLE001
            log.exception("companies locate failed")
            with _lock:
                _state["last"] = {"error": str(e)}
        finally:
            _clear_progress()
            with _lock:
                _state["running"] = False

    threading.Thread(target=_run, daemon=True).start()
    return jsonify(status="started"), 202


@app.post("/companies/locate-one")
def companies_locate_one():
    """Localise UNE entreprise (par nom), de façon synchrone. Body {company}."""
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    name = str((request.get_json(silent=True) or {}).get("company") or "").strip()
    if not name:
        return jsonify(error="company requis"), 400
    try:
        import companies

        doc = companies.locate_one(name)
        if not doc:
            return jsonify(error="localisation impossible"), 422
        return jsonify(status="ok", company=doc), 200
    except Exception as e:  # noqa: BLE001
        log.exception("companies locate-one failed")
        return jsonify(error=str(e)), 500


@app.post("/admin/reprocess-all")
def admin_reprocess_all():
    """Re-traite toutes les offres (nouvelles consignes d'agents) en tâche de fond."""
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    with _lock:
        if _state["running"]:
            return jsonify(status="already_running"), 409
        _state["running"] = True

    def _run():
        try:
            summary = pipeline.reprocess_all(force=True, progress=_progress_cb)
            with _lock:
                _state["last"] = summary
        except Exception as e:  # noqa: BLE001
            log.exception("reprocess-all failed")
            with _lock:
                _state["last"] = {"error": str(e)}
        finally:
            _clear_progress()
            with _lock:
                _state["running"] = False

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
        from extraction.schema import base_record_from_graphql
        from scraper import jobs_cz
        from scraper.jobs_cz import ListingCard

        offer = firestore_store.get_offer(offer_id)
        if not offer:
            return jsonify(error="offre introuvable"), 404
        offer["id"] = offer_id
        # Re-récupération du détail (données structurées fraîches, dont langues + date).
        if offer.get("link"):
            card = ListingCard(
                site=offer.get("site", "jobs.cz"), id=offer_id,
                title=offer.get("title", ""), company=offer.get("company", ""),
                location=offer.get("location_city", ""), link=offer["link"],
            )
            job_ad = jobs_cz.fetch_detail(card)
            if job_ad:
                offer = base_record_from_graphql(card, job_ad)
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


@app.post("/admin/test-match")
def admin_test_match():
    """Debug matching : {profile_text, offer_id} -> analyse profil + match (sans stockage)."""
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    body = request.get_json(silent=True) or {}
    text = body.get("profile_text", "")
    offer_id = str(body.get("offer_id") or "")
    if not text or not offer_id:
        return jsonify(error="profile_text et offer_id requis"), 400
    try:
        from store import firestore_store
        from matching import analyze_profile, match_offer

        offer = firestore_store.get_offer(offer_id)
        if not offer:
            return jsonify(error="offre introuvable"), 404
        profile = analyze_profile(text)
        result = match_offer(profile or {}, offer)
        return jsonify(
            offer_title=offer.get("title"),
            offer_languages=offer.get("languages"),
            match=result,
        )
    except Exception as e:  # noqa: BLE001
        log.exception("test-match failed")
        return jsonify(error=str(e)), 500


@app.post("/admin/analyze-profile-text")
def admin_analyze_profile_text():
    """Debug : structure un texte de profil et renvoie le résultat (sans stockage)."""
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    text = (request.get_json(silent=True) or {}).get("text", "")
    if not text:
        return jsonify(error="text requis"), 400
    try:
        from matching import analyze_profile

        return jsonify(structured=analyze_profile(text), chars=len(text))
    except Exception as e:  # noqa: BLE001
        log.exception("analyze-profile-text failed")
        return jsonify(error=str(e)), 500


@app.post("/admin/setup-agents")
def setup_agents():
    """Crée (ou retrouve) les agents Mistral dédiés et renvoie leurs IDs.

    Protégé par le secret partagé. Idempotent : ne crée pas de doublon.
    """
    if not _authorized(request):
        return jsonify(error="unauthorized"), 401
    rebuild = bool((request.get_json(silent=True) or {}).get("rebuild"))
    try:
        from extraction.agents import _get_client
        from extraction.agents_setup import ensure_agents, rebuild_agents

        client = _get_client()
        ids = rebuild_agents(client) if rebuild else ensure_agents(client)
        return jsonify(status="ok", rebuilt=rebuild, agents=ids)
    except Exception as e:  # noqa: BLE001
        log.exception("setup-agents failed")
        return jsonify(error=str(e)), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=config.PORT)
