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

MATCH_VERSION = 2  # incrémenté à chaque refonte du matching -> force le re-matching


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
    """Structure un profil via une chaîne multi-agents (comme les offres) :
      ① profile (base) → ② profile_skills (compétences par domaine/niveau)
      → ③ profile_verify (contrôle de fidélité).

    Limite haute (120k) : un profil complet dépasse souvent 20k caractères — il
    doit être lu en ENTIER (sinon les sections de fin, ex. Langues, sont tronquées).
    """
    doc = f"CANDIDATE DOCUMENT:\n{text}"
    base = _ask_agent("profile", doc, max_chars=120000) or {}

    # ② compétences techniques + logiciels du candidat, catégorisés (expert Data).
    skills = _ask_agent("profile_skills", doc, max_chars=120000) or {}
    structured = dict(base)
    if skills.get("hard_skills"):
        structured["hard_skills"] = skills["hard_skills"]
    if skills.get("software"):
        structured["software"] = skills["software"]

    # ③ vérificateur de fidélité (langues verbatim, pas d'invention).
    verified = _ask_agent(
        "profile_verify",
        f"{doc}\n\nDRAFT PROFILE JSON:\n{json.dumps(structured, ensure_ascii=False)}",
        max_chars=120000,
    )
    if isinstance(verified, dict) and verified:
        structured = {**structured, **verified}
    return structured


_TEXT_EXTS = (".md", ".markdown", ".txt")


def build_profile(file_bytes: bytes, filename: str = "profil.pdf") -> dict:
    """Structure un profil à partir d'un fichier.

    - .md / .markdown / .txt -> ingestion directe du texte (pas d'OCR).
    - autre (PDF...) -> Mistral OCR.
    """
    lower = (filename or "").lower()
    if lower.endswith(_TEXT_EXTS):
        text = file_bytes.decode("utf-8", errors="replace")
        source = "text"
    else:
        text = ocr_pdf(file_bytes, filename)
        source = "ocr"
    structured = analyze_profile(text) or {}
    return {
        "filename": filename,
        "source": source,
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

    # Texte de l'offre (tronqué) : indispensable pour distinguer un prérequis dur
    # d'un « familiarity with » / d'un exemple ("e.g. Snowflake").
    desc = offer.get("description_text") or ""
    tr = offer.get("translated") or {}
    if tr.get("description_text"):
        desc = tr["description_text"]
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
        "offer_text": desc[:2500],
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
