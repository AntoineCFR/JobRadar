"""Test bout-en-bout local : liste -> GraphQL -> Mistral. N'écrit rien dans Firestore."""
import sys, os, json, logging
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

from scraper import jobs_cz
from scraper.graphql_client import _session
from extraction.schema import base_record_from_graphql
from extraction.agents import process_offer

KEYWORD = sys.argv[1] if len(sys.argv) > 1 else "data engineer"
LOCATION = sys.argv[2] if len(sys.argv) > 2 else "praha"
N = int(sys.argv[3]) if len(sys.argv) > 3 else 2

sess = _session()
cards = jobs_cz.search(KEYWORD, LOCATION, max_pages=1, sess=sess, polite=False)
print(f"\n=== {len(cards)} offres trouvées pour '{KEYWORD}' @ {LOCATION} ===")
for c in cards[:5]:
    print(f"  [{c.id}] {c.title} — {c.company} ({c.location})")

results = []
for card in cards[:N]:
    print(f"\n--- Détail + IA pour {card.id} : {card.title} ---")
    job_ad = jobs_cz.fetch_detail(card, sess=sess)
    if not job_ad:
        print("  !! GraphQL détail indisponible")
        continue
    rec = base_record_from_graphql(card, job_ad)
    print(f"  langue source: {rec['source_language']} | pub: {rec['published_at']} | "
          f"salaire: {rec['salary']}")
    rec = process_offer(rec)
    results.append(rec)
    slim = {k: rec[k] for k in (
        "id", "title", "company", "intermediary", "published_at", "source_language",
        "location_city", "location_region", "sector", "contract_type",
        "work_arrangement", "education", "experience_years", "soft_skills",
        "technical_skills", "software", "languages", "salary", "benefits", "summary")}
    print(json.dumps(slim, ensure_ascii=False, indent=2))

out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "test_output.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(results, f, ensure_ascii=False, indent=2)
print(f"\n>>> {len(results)} offres enrichies écrites dans {out}")
