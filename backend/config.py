"""Configuration centrale du backend JobRadar.

Toutes les valeurs sensibles viennent de variables d'environnement (fichier
`.env` en local, variables Render en prod). Rien de secret n'est committé.
"""
import os
from dotenv import load_dotenv

load_dotenv()


def _get(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


# --- Mistral (agents d'extraction / traduction) ---
MISTRAL_API_KEY = _get("MISTRAL_API_KEY")
MISTRAL_MODEL = _get("MISTRAL_MODEL", "mistral-small-latest")

# --- Firebase / Firestore (source de vérité lue par l'app) ---
# Chemin vers le service account JSON de l'Admin SDK, OU son contenu inline.
FIREBASE_CREDENTIALS_PATH = _get("FIREBASE_CREDENTIALS_PATH", "serviceAccount.json")
FIREBASE_CREDENTIALS_JSON = _get("FIREBASE_CREDENTIALS_JSON")  # alternative inline (Render)
FIRESTORE_OFFERS_COLLECTION = _get("FIRESTORE_OFFERS_COLLECTION", "offers")
FIRESTORE_RUNS_COLLECTION = _get("FIRESTORE_RUNS_COLLECTION", "scrape_runs")
FIRESTORE_TOKENS_COLLECTION = _get("FIRESTORE_TOKENS_COLLECTION", "device_tokens")
FIRESTORE_SEARCHES_COLLECTION = _get("FIRESTORE_SEARCHES_COLLECTION", "searches")

# Recherches surveillées par défaut par le cron quotidien, utilisées pour amorcer
# la collection Firestore `searches` à son premier passage (ensuite gérées côté
# app / console Firebase). Adapte cette liste à tes mots-clés cibles.
DEFAULT_DAILY_SEARCHES = [
    {"keyword": "data engineer", "location": "praha"},
]

# --- Scraping ---
USER_AGENT = _get(
    "USER_AGENT",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0 Safari/537.36",
)
SCRAPE_MIN_DELAY = float(_get("SCRAPE_MIN_DELAY", "3"))
SCRAPE_MAX_DELAY = float(_get("SCRAPE_MAX_DELAY", "6"))
SCRAPE_MAX_PAGES = int(_get("SCRAPE_MAX_PAGES", "10"))

# --- Sécurité API : jeton partagé que l'app doit fournir pour déclencher un scrape ---
API_SHARED_SECRET = _get("API_SHARED_SECRET")

# --- Divers ---
PORT = int(_get("PORT", "8000"))
LOG_LEVEL = _get("LOG_LEVEL", "INFO")


def mistral_ready() -> bool:
    return bool(MISTRAL_API_KEY)


def firestore_ready() -> bool:
    return bool(FIREBASE_CREDENTIALS_JSON) or os.path.exists(FIREBASE_CREDENTIALS_PATH)
