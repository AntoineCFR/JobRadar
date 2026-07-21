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
from extraction.agents import process_offer

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
            rec["is_new"] = True
            if persist:
                firestore_store.upsert_offer(rec, {"keyword": keyword, "location": location})
            new_offers.append({"id": rec["id"], "title": rec.get("title", "")})
            processed += 1
        except Exception as e:  # noqa: BLE001 - une offre ratée ne casse pas le run
            errors += 1
            log.warning("offre %s en échec: %s", card.id, e)
        if progress:
            progress({"idx": idx, "of": len(new_cards), "id": card.id})
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

    log.info("run terminé: %s", {k: summary[k] for k in ("total_found", "new_count", "processed", "errors")})
    return summary
