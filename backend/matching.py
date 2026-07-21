"""Pipeline 2 — Conseil / matching offre × profil.

  PDF profil --OCR--> texte --agent profil--> profil structuré (+ version=hash)
  (profil, offre) --agent match--> évaluation --agent calibrate--> score fiable

Le matching d'une offre n'est (re)calculé que si absent ou si la version du
profil a changé (voir pipeline / endpoints).
"""
from __future__ import annotations

import json
import hashlib
import logging
import datetime as dt
from typing import Optional

from extraction.agents import _get_client, _ask_agent

log = logging.getLogger("jobradar.matching")

MATCH_VERSION = 1


# --------------------------------------------------------------------------- #
# Profil
# --------------------------------------------------------------------------- #
def ocr_pdf(pdf_bytes: bytes, filename: str = "profil.pdf") -> str:
    """OCR d'un PDF via Mistral OCR -> texte markdown."""
    client = _get_client()
    uploaded = client.files.upload(
        file={"file_name": filename, "content": pdf_bytes}, purpose="ocr"
    )
    signed = client.files.get_signed_url(file_id=uploaded.id)
    ocr = client.ocr.process(
        model="mistral-ocr-latest",
        document={"type": "document_url", "document_url": signed.url},
        include_image_base64=False,
    )
    return "\n\n".join(getattr(p, "markdown", "") for p in ocr.pages)


def profile_version(text: str) -> str:
    return hashlib.sha256((text or "").encode("utf-8")).hexdigest()[:16]


def analyze_profile(text: str) -> Optional[dict]:
    """Structure le texte du CV/profil via l'agent Profil."""
    return _ask_agent("profile", f"CANDIDATE DOCUMENT:\n{text}", max_chars=20000)


def build_profile(pdf_bytes: bytes, filename: str = "profil.pdf") -> dict:
    """OCR + structuration -> doc profil complet à stocker dans Firestore."""
    text = ocr_pdf(pdf_bytes, filename)
    structured = analyze_profile(text) or {}
    return {
        "filename": filename,
        "text": text,
        "structured": structured,
        "version": profile_version(text),
        "updated_at": dt.datetime.utcnow().isoformat() + "Z",
    }


# --------------------------------------------------------------------------- #
# Matching offre × profil
# --------------------------------------------------------------------------- #
def _offer_view(offer: dict) -> dict:
    """Vue compacte d'une offre pour l'agent (champs pertinents seulement)."""
    def names(items):
        return [i.get("name") if isinstance(i, dict) else i for i in (items or [])]

    return {
        "title": offer.get("title"),
        "company": offer.get("company"),
        "location": offer.get("location_city"),
        "sector": offer.get("sector"),
        "experience_years_required": offer.get("experience_years"),
        "education": offer.get("education"),
        "work_arrangement": offer.get("work_arrangement"),
        "languages": offer.get("languages"),
        "software": names(offer.get("software")),
        "technical_skills": names(offer.get("technical_skills")),
        "summary": offer.get("summary"),
    }


def match_offer(profile_struct: dict, offer: dict) -> Optional[dict]:
    """Évalue l'adéquation profil/offre (agent match) puis calibre (agent calibrate)."""
    payload = {
        "candidate": profile_struct,
        "offer": _offer_view(offer),
    }
    draft = _ask_agent(
        "match",
        f"CANDIDATE: {json.dumps(profile_struct, ensure_ascii=False)}\n\n"
        f"OFFER: {json.dumps(_offer_view(offer), ensure_ascii=False)}",
    )
    if not draft:
        return None
    # Calibrage anti-optimisme.
    calibrated = _ask_agent(
        "calibrate",
        f"CANDIDATE: {json.dumps(profile_struct, ensure_ascii=False)}\n\n"
        f"OFFER: {json.dumps(_offer_view(offer), ensure_ascii=False)}\n\n"
        f"DRAFT ASSESSMENT: {json.dumps(draft, ensure_ascii=False)}",
    )
    result = calibrated or draft
    # Garde-fous de forme.
    try:
        result["score"] = max(0, min(100, int(result.get("score", 0))))
    except (TypeError, ValueError):
        result["score"] = 0
    result.setdefault("band", "moyen")
    result["match_version"] = MATCH_VERSION
    result["computed_at"] = dt.datetime.utcnow().isoformat() + "Z"
    return result
