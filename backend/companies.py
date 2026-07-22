"""Localisation des entreprises (collection `companies`).

Un agent Mistral déduit le lieu de travail probable d'une entreprise à partir de
son nom, de la ville de l'offre et du texte de l'offre. Sert au bouton
« itinéraire » côté app (ouverture de Google Maps).
"""
from __future__ import annotations

import re
import logging
import datetime as dt
from typing import Callable, Optional

from extraction.agents import _ask_agent
from store import firestore_store

log = logging.getLogger("jobradar.companies")


def company_key(name: str) -> str:
    """Clé de document Firestore stable et identique côté app (nom normalisé)."""
    k = re.sub(r"\s+", " ", (name or "").strip()).lower().replace("/", "-")
    return k or "unknown"


def locate_company(name: str, offers: list[dict]) -> Optional[dict]:
    """Déduit et stocke la localisation d'une entreprise à partir de ses offres."""
    city = ""
    text = ""
    for o in offers:
        city = city or (o.get("location_city") or "")
        if not text:
            tr = o.get("translated") or {}
            text = (tr.get("description_text") or o.get("description_text") or "")[:1500]
    out = _ask_agent(
        "company_location",
        f"COMPANY: {name}\nOFFER LOCATION: {city}\nOFFER TEXT:\n{text}",
        max_chars=3000,
    )
    if not out:
        return None
    maps_query = (out.get("maps_query") or "").strip() or f"{name}, {city}".strip(", ")
    doc = {
        "name": name,
        "location": {
            "city": out.get("city"),
            "region": out.get("region"),
            "country": out.get("country") or "Czechia",
            "address": out.get("address"),
            "maps_query": maps_query,
            "confidence": out.get("confidence") or "basse",
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
