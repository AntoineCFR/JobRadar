"""Orchestration d'un run de scraping complet.

  liste (HTML) -> filtre nouveautés -> détail (GraphQL/HTML) -> agents Mistral
  -> écriture Firestore -> notification push des nouveautés.

Utilisable en direct (import) ou via l'API Flask (app.py) et le cron
(scripts/run_daily.py).
"""
from __future__ import annotations

import time
import random
import logging
import datetime as dt
from typing import Callable, Optional

from config import SCRAPE_MIN_DELAY, SCRAPE_MAX_DELAY, SCRAPE_MAX_PAGES
from scraper import jobs_cz
from scraper.graphql_client import _session
from extraction.schema import base_record_from_graphql
from extraction.agents import process_offer, score_relevance

log = logging.getLogger("jobradar.pipeline")


def run_scrape(
    keyword: str,
    location: str,
    max_pages: int = SCRAPE_MAX_PAGES,
    enrich: bool = True,
    persist: bool = True,
    notify: bool = True,
    progress: Optional[Callable[[dict], None]] = None,
) -> dict:
    """Exécute un run. Renvoie un résumé {total, new, processed, new_offers[...]}.

    - `enrich`  : lance les agents Mistral (sinon on garde juste le structuré).
    - `persist` : écrit dans Firestore (sinon dry-run en mémoire).
    - `notify`  : envoie une notif push si de nouvelles offres.
    """
    started = time.time()
    sess = _session()
    cards = jobs_cz.search(keyword, location, max_pages=max_pages, sess=sess)
    total = len(cards)

    # Nouveautés = ids inconnus en base.
    if persist:
        from store import firestore_store

        existing = firestore_store.get_existing_ids([c.id for c in cards])
    else:
        existing = set()
    new_cards = [c for c in cards if c.id not in existing]
    log.info("run: %s offres, %s nouvelles", total, len(new_cards))

    processed, new_offers, errors = 0, [], 0
    for idx, card in enumerate(new_cards, 1):
        try:
            job_ad = jobs_cz.fetch_detail(card, sess=sess)
            rec = base_record_from_graphql(card, job_ad)
            rec["scraped_at"] = dt.datetime.utcnow().isoformat() + "Z"
            if enrich:
                rec = process_offer(rec)
                rel = score_relevance(keyword, rec.get("title", ""), rec.get("summary", ""))
                if rel:
                    rec["relevance"] = rel
            rec["is_new"] = True
            if persist:
                firestore_store.upsert_offer(rec, {"keyword": keyword, "location": location})
            new_offers.append({"id": rec["id"], "title": rec.get("title", "")})
            processed += 1
        except Exception as e:  # noqa: BLE001 - une offre ratée ne casse pas le run
            errors += 1
            log.warning("offre %s en échec: %s", card.id, e)
        if progress:
            progress(idx, len(new_cards), f"Analyse des offres · {keyword}")
        if idx < len(new_cards):
            time.sleep(random.uniform(SCRAPE_MIN_DELAY, SCRAPE_MAX_DELAY))

    summary = {
        "keyword": keyword,
        "location": location,
        "total_found": total,
        "new_count": len(new_cards),
        "processed": processed,
        "errors": errors,
        "duration_s": round(time.time() - started, 1),
        "new_offers": new_offers,
    }

    if persist:
        from store import firestore_store

        firestore_store.record_run(summary)
    if notify and new_offers:
        from notify.fcm import notify_new_offers

        notify_new_offers(len(new_offers), [o["title"] for o in new_offers])

    # Matching automatique des offres en attente (si un profil existe).
    if persist and new_offers:
        try:
            matched = run_matching()
            summary["matched"] = matched
        except Exception as e:  # noqa: BLE001
            log.warning("matching post-scrape échoué: %s", e)

    log.info("run terminé: %s", {k: summary[k] for k in ("total_found", "new_count", "processed", "errors")})
    return summary


def reprocess_all(force: bool = True, progress: Optional[Callable] = None) -> dict:
    """Re-passe toutes les offres dans la chaîne d'extraction (nouvelles consignes).

    Pour une offre sans texte (détail jamais récupéré), on RETENTE la récupération
    du détail avant de la ré-analyser. Relance ensuite le matching. Renvoie un
    résumé {total, reprocessed, refetched, errors}.
    """
    from store import firestore_store
    from extraction.agents import process_offer, EXTRACTION_VERSION
    from extraction.schema import base_record_from_graphql
    from scraper import jobs_cz
    from scraper.jobs_cz import ListingCard

    sess = _session()
    offers = firestore_store.stream_offers()
    total = len(offers)
    reprocessed = refetched = errors = 0
    for i, (offer_id, offer) in enumerate(offers, 1):
        if progress:
            progress(i, total, "Ré-analyse des offres")
        if not force and offer.get("extraction_version") == EXTRACTION_VERSION:
            continue
        try:
            rec = dict(offer)
            rec["id"] = offer_id
            # Re-récupération du détail si le texte manque OU si la copie brute des
            # langues requises est absente (offres d'avant ce correctif) : ça rapatrie
            # aussi la date de publication (widget v3) et le contenu à jour.
            needs_refetch = rec.get("link") and (
                not (rec.get("description_text") or "").strip()
                or not rec.get("structured_languages")
            )
            if needs_refetch:
                card = ListingCard(
                    site=rec.get("site", "jobs.cz"), id=offer_id,
                    title=rec.get("title", ""), company=rec.get("company", ""),
                    location=rec.get("location_city", ""), link=rec["link"],
                )
                job_ad = jobs_cz.fetch_detail(card, sess=sess)
                if job_ad:
                    rec = base_record_from_graphql(card, job_ad)
                    rec["id"] = offer_id
                    refetched += 1
            rec = process_offer(rec)
            searches = offer.get("searches") or []
            kw = str(searches[0]).split("|")[0] if searches else ""
            rel = score_relevance(kw, rec.get("title", ""), rec.get("summary", ""))
            if rel:
                rec["relevance"] = rel
            firestore_store.upsert_offer(rec)
            reprocessed += 1
        except Exception as e:  # noqa: BLE001
            errors += 1
            log.warning("reprocess %s échoué: %s", offer_id, e)
    # Le contenu a changé -> re-matcher.
    try:
        run_matching(force=True)
    except Exception as e:  # noqa: BLE001
        log.warning("matching après reprocess échoué: %s", e)
    summary = {"total": total, "reprocessed": reprocessed, "refetched": refetched, "errors": errors}
    log.info("reprocess_all terminé: %s", summary)
    return summary


def run_matching(force: bool = False, progress: Optional[Callable] = None) -> int:
    """Calcule le matching des offres en attente pour le profil courant.

    Ne (re)calcule une offre que si `match` absent, ou si la version du profil
    ou du modèle de matching a changé (sauf `force=True`). Renvoie le nombre
    d'offres (re)matchées.
    """
    from store import firestore_store
    from matching import match_offer, MATCH_VERSION

    prof = firestore_store.first_profile()
    if not prof:
        log.info("run_matching: aucun profil, rien à faire")
        return 0
    _, profile = prof
    pv = profile.get("version", "")
    pstruct = profile.get("structured") or {}

    offers = firestore_store.stream_offers()
    total = len(offers)
    matched = 0
    for i, (offer_id, offer) in enumerate(offers, 1):
        if progress:
            progress(i, total, "Matching des offres")
        m = offer.get("match")
        up_to_date = (
            m
            and m.get("profile_version") == pv
            and m.get("match_version") == MATCH_VERSION
        )
        if up_to_date and not force:
            continue
        result = match_offer(pstruct, offer)
        if result:
            firestore_store.set_offer_match(offer_id, result, pv)
            matched += 1
    log.info("run_matching: %s offres (re)matchées (profil %s)", matched, pv)
    return matched
