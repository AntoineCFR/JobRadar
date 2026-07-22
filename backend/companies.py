"""Localisation des entreprises (collection `companies`).

Un agent Mistral déduit le lieu de travail probable d'une entreprise à partir de
son nom, de la ville de l'offre et du texte de l'offre. Sert au bouton
« itinéraire » côté app (ouverture de Google Maps).
"""
from __future__ import annotations

import re
import time
import logging
import datetime as dt
from typing import Callable, Optional

import requests

import config
from extraction.agents import _ask_agent
from store import firestore_store

log = logging.getLogger("jobradar.companies")

# Indices d'adresse dans le texte (cz/en) -> on priorise ces offres pour l'agent.
_ADDR_HINT = re.compile(
    r"\b(ulice|nám\.|náměstí|třída|sídlo|budova|adresa|address|street|psč|\d{3}\s?\d{2})\b",
    re.I,
)
_NOMINATIM = "https://nominatim.openstreetmap.org/search"


def company_key(name: str) -> str:
    """Clé de document Firestore stable et identique côté app (nom normalisé)."""
    k = re.sub(r"\s+", " ", (name or "").strip()).lower().replace("/", "-")
    return k or "unknown"


def _geocode_google(query: str) -> Optional[dict]:
    """Google Places Text Search : résout un NOM d'entreprise OU une adresse en
    lieu réel (adresse formatée + coordonnées). Nécessite GOOGLE_MAPS_API_KEY."""
    if not query:
        return None
    try:
        r = requests.get(
            "https://maps.googleapis.com/maps/api/place/textsearch/json",
            params={"query": query, "region": "cz", "language": "cs",
                    "key": config.GOOGLE_MAPS_API_KEY},
            timeout=20,
        )
        r.raise_for_status()
        data = r.json()
        results = data.get("results") or []
        status = data.get("status")
        if status == "OK" and results:
            it = results[0]
            loc = (it.get("geometry") or {}).get("location") or {}
            if loc.get("lat") is not None:
                return {
                    "lat": float(loc["lat"]),
                    "lon": float(loc["lng"]),
                    "display_name": it.get("formatted_address") or it.get("name"),
                    "source": "google",
                }
        elif status not in ("OK", "ZERO_RESULTS"):
            log.warning("google places status=%s: %s", status, data.get("error_message"))
    except Exception as e:  # noqa: BLE001
        log.warning("google geocode échoué (%s): %s", query, e)
    return None


def _geocode_osm(query: str) -> Optional[dict]:
    """Géocode via Nominatim (OpenStreetMap). Gratuit, sans clé, taux plus faible."""
    if not query:
        return None
    try:
        r = requests.get(
            _NOMINATIM,
            params={"q": query, "format": "json", "limit": 1, "addressdetails": 1},
            headers={"User-Agent": "JobRadar/1.0 (company workplace lookup)"},
            timeout=20,
        )
        r.raise_for_status()
        arr = r.json()
        if arr:
            it = arr[0]
            return {
                "lat": float(it["lat"]),
                "lon": float(it["lon"]),
                "display_name": it.get("display_name"),
                "source": "osm",
            }
    except Exception as e:  # noqa: BLE001
        log.warning("geocode osm échoué (%s): %s", query, e)
    return None


def _geocode(query: str) -> Optional[dict]:
    """Google si une clé est configurée (meilleur pour les noms d'entreprise),
    sinon OpenStreetMap/Nominatim."""
    if config.GOOGLE_MAPS_API_KEY:
        return _geocode_google(query)
    return _geocode_osm(query)


def locate_company(name: str, offers: list[dict]) -> Optional[dict]:
    """Déduit puis GÉOCODE la localisation d'une entreprise à partir de TOUTES
    ses offres (villes, secteur, textes pour extraire une adresse), et stocke."""
    cities: list[str] = []
    regions: list[str] = []
    sectors: list[str] = []
    texts: list[str] = []
    for o in offers:
        for k, bucket in (("location_city", cities), ("location_region", regions), ("sector", sectors)):
            v = (o.get(k) or "").strip()
            if v and v not in bucket:
                bucket.append(v)
        tr = o.get("translated") or {}
        t = tr.get("description_text") or o.get("description_text") or ""
        if t:
            texts.append(t)
    # Offres avec un indice d'adresse en premier ; on borne la taille.
    texts.sort(key=lambda t: 0 if _ADDR_HINT.search(t) else 1)
    joined = "\n---\n".join(texts)[:4000]
    city = cities[0] if cities else ""

    out = _ask_agent(
        "company_location",
        f"COMPANY: {name}\n"
        f"SECTOR / DOMAIN: {', '.join(sectors) or 'unknown'}\n"
        f"OFFER CITIES: {', '.join(cities) or 'unknown'}\n"
        f"OFFER REGIONS: {', '.join(regions) or 'unknown'}\n"
        f"OFFER TEXTS (may contain the workplace address):\n{joined}",
        max_chars=6000,
    ) or {}

    country = out.get("country") or "Czechia"
    address = out.get("address")
    maps_query = (out.get("maps_query") or "").strip()

    # Géocodage réel : adresse explicite > requête agent > nom + ville.
    candidates: list[str] = []
    if address:
        candidates.append(", ".join(p for p in [address, city, country] if p))
    if maps_query:
        candidates.append(maps_query)
    candidates.append(", ".join(p for p in [name, city, country] if p))
    geo = None
    seen: set[str] = set()
    for q in candidates:
        if not q or q in seen:
            continue
        seen.add(q)
        geo = _geocode(q)
        if not config.GOOGLE_MAPS_API_KEY:
            time.sleep(1.1)  # Nominatim : max 1 requête/seconde (pas nécessaire avec Google)
        if geo:
            break

    doc = {
        "name": name,
        "location": {
            "city": out.get("city") or (city or None),
            "region": out.get("region") or (regions[0] if regions else None),
            "country": country,
            "address": address,
            "maps_query": maps_query or ", ".join(p for p in [name, city] if p),
            "confidence": out.get("confidence") or "basse",
            "geo": geo,  # {lat, lon, display_name, source} ou None
        },
        "updated_at": dt.datetime.utcnow().isoformat() + "Z",
    }
    firestore_store.set_company(company_key(name), doc)
    return doc


def _offers_by_company() -> dict[str, list[dict]]:
    by: dict[str, list[dict]] = {}
    for _id, o in firestore_store.stream_offers():
        nm = (o.get("company") or "").strip()
        if nm:
            by.setdefault(nm, []).append(o)
    return by


def locate_all(only_missing: bool = True, progress: Optional[Callable] = None) -> dict:
    """Localise toutes les entreprises (ou seulement celles sans fiche)."""
    by_company = _offers_by_company()
    existing = firestore_store.list_company_keys() if only_missing else set()
    todo = [
        (nm, offs)
        for nm, offs in by_company.items()
        if not only_missing or company_key(nm) not in existing
    ]
    located = 0
    for i, (nm, offs) in enumerate(todo, 1):
        try:
            if locate_company(nm, offs):
                located += 1
        except Exception as e:  # noqa: BLE001
            log.warning("localisation %s échouée: %s", nm, e)
        if progress:
            progress(i, len(todo), "Localisation des entreprises")
    summary = {"companies": len(by_company), "todo": len(todo), "located": located}
    log.info("locate_all terminé: %s", summary)
    return summary


def locate_one(name: str) -> Optional[dict]:
    """Localise une seule entreprise (par nom)."""
    offers = _offers_by_company().get(name.strip(), [])
    return locate_company(name.strip(), offers)
