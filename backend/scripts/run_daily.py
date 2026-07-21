"""Point d'entrée du cron quotidien (Render Cron Job).

Lit la liste des recherches à surveiller dans la collection Firestore `searches`
(gérable depuis l'app / la console Firebase). Si elle est vide, elle est amorcée
avec `config.DEFAULT_DAILY_SEARCHES`. Chaque recherche fait un run ; les
nouveautés déclenchent une notif push.
"""
import os
import sys
import logging

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("jobradar.cron")

import config  # noqa: E402
import pipeline  # noqa: E402


def _load_searches() -> list[dict]:
    try:
        from store import firestore_store

        return firestore_store.get_daily_searches()
    except Exception as e:  # noqa: BLE001 - pas de Firestore dispo -> défaut
        log.warning("lecture Firestore impossible (%s), fallback défaut", e)
        return list(config.DEFAULT_DAILY_SEARCHES)


def main():
    searches = _load_searches()
    log.info("%s recherche(s) à traiter", len(searches))
    grand_total_new = 0
    for s in searches:
        kw, loc = s.get("keyword", ""), s.get("location", "")
        if not kw:
            continue
        log.info("=== run quotidien : '%s' @ %s ===", kw, loc)
        summary = pipeline.run_scrape(kw, loc)
        grand_total_new += summary.get("new_count", 0)
    log.info("cron terminé : %s nouvelles offres au total", grand_total_new)


if __name__ == "__main__":
    main()
