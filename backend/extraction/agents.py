"""Agents Mistral : traduction cz->en + extraction des champs non structurés.

Deux agents (comme le pattern EducaQuiz) :
  - `translate_to_english()` : traduit une offre tchèque en anglais.
  - `enrich_offer()` : déduit du texte les champs qu'aucune API ne donne
    (soft/hard skills, logiciels, années d'XP, nécessité d'une langue,
    mode de travail remote/hybride, résumé court).

Tout passe par le mode JSON de Mistral pour une sortie parsable.
"""
from __future__ import annotations

import json
import logging
from typing import Optional

from config import MISTRAL_API_KEY, MISTRAL_MODEL

log = logging.getLogger("jobradar.agents")

_client = None


def _get_client():
    global _client
    if _client is None:
        from mistralai.client import Mistral  # SDK v2.x : le client est dans mistralai.client

        _client = Mistral(api_key=MISTRAL_API_KEY)
    return _client


def _chat_json(system: str, user: str, max_chars: int = 12000) -> Optional[dict]:
    """Appelle Mistral en mode JSON et renvoie le dict, ou None en cas d'échec."""
    if not MISTRAL_API_KEY:
        log.warning("MISTRAL_API_KEY absent : agents désactivés")
        return None
    try:
        resp = _get_client().chat.complete(
            model=MISTRAL_MODEL,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user[:max_chars]},
            ],
            response_format={"type": "json_object"},
            temperature=0.1,
        )
        content = resp.choices[0].message.content
        return json.loads(content)
    except Exception as e:  # noqa: BLE001 - on ne veut jamais casser le pipeline
        log.warning("Mistral call failed: %s", e)
        return None


# --------------------------------------------------------------------------- #
# Agent 1 : traduction
# --------------------------------------------------------------------------- #
_TRANSLATE_SYSTEM = (
    "You are a professional translator for job advertisements. Translate the "
    "given Czech job offer into natural, professional English. Keep the meaning "
    "and tone. Do NOT invent information. Return ONLY a JSON object with keys: "
    '"title" (string), "summary" (string, 2-3 sentences), "description_text" '
    "(string, the full offer translated, keep line breaks/bullets)."
)


def translate_to_english(title: str, text: str) -> Optional[dict]:
    user = f"TITLE: {title}\n\nOFFER (Czech):\n{text}"
    out = _chat_json(_TRANSLATE_SYSTEM, user)
    if not out:
        return None
    return {
        "title": out.get("title", title),
        "summary": out.get("summary", ""),
        "description_text": out.get("description_text", ""),
    }


# --------------------------------------------------------------------------- #
# Agent 2 : extraction / enrichissement
# --------------------------------------------------------------------------- #
_ENRICH_SYSTEM = (
    "You extract structured data from a job advertisement (written in English). "
    "Return ONLY a JSON object. Be faithful to the text; use null / empty arrays "
    "when the information is absent. Do not invent. JSON keys:\n"
    '- "summary": string, 2-3 sentence neutral summary in English.\n'
    '- "experience_years": integer or null (minimum years of experience required).\n'
    '- "education": string or null (required/desired level of study).\n'
    '- "soft_skills": string[] (human/interpersonal skills).\n'
    '- "technical_skills": string[] (hard/technical skills, methods, domains).\n'
    '- "software": string[] (named tools/software/technologies, e.g. Python, Power BI, SAP).\n'
    '- "work_arrangement": one of "on-site","hybrid","remote", or null.\n'
    '- "languages": array of {"language": string, "level": string|null, '
    '"mandatory": boolean, "reason": string}. Infer a language as mandatory even '
    "if not explicit when the context implies it (e.g. Czech required because the "
    'role serves Czech clients or is Czech-speaking). Fill "reason" with a short '
    "justification.\n"
    '- "company": string or null (the actual hiring/end company if identifiable).\n'
    '- "intermediary": string or null. Fill ONLY when a staffing/recruitment '
    "AGENCY is posting on behalf of a different end-client company. Return null "
    "for a company hiring for itself, including its own subsidiaries or entities "
    "of the same corporate group (same brand/name family is NOT an intermediary).\n"
)


def enrich_offer(text: str, hints: Optional[dict] = None) -> Optional[dict]:
    hints = hints or {}
    hint_str = json.dumps(
        {
            k: hints.get(k)
            for k in ("title", "company", "location_city",
                      "location_country", "sector", "languages", "education",
                      "contract_type")
        },
        ensure_ascii=False,
    )
    user = f"KNOWN STRUCTURED HINTS: {hint_str}\n\nOFFER TEXT:\n{text}"
    return _chat_json(_ENRICH_SYSTEM, user)


# --------------------------------------------------------------------------- #
# Orchestration d'une offre
# --------------------------------------------------------------------------- #
def process_offer(rec: dict) -> dict:
    """Complète un enregistrement d'offre (base GraphQL) avec les agents Mistral.

    Modifie et renvoie `rec`. Sans clé Mistral, renvoie `rec` inchangé (les
    champs structurés GraphQL restent disponibles).
    """
    source_lang = (rec.get("source_language") or "").lower()
    original_text = rec.get("description_text") or ""
    working_title = rec.get("title") or ""

    # 1) Traduction si tchèque -> on garde les 2 versions.
    working_text = original_text
    if source_lang.startswith("cs") and original_text:
        tr = translate_to_english(working_title, original_text)
        if tr:
            rec["translated"] = {
                "language": "en",
                "title": tr["title"],
                "summary": tr["summary"],
                "description_text": tr["description_text"],
            }
            working_text = tr["description_text"] or original_text
            working_title = tr["title"] or working_title

    # 2) Extraction sur le texte anglais.
    if working_text:
        data = enrich_offer(working_text, hints=rec)
        if data:
            rec["summary"] = data.get("summary") or rec.get("summary") or ""
            rec["experience_years"] = data.get("experience_years")
            rec["education"] = data.get("education") or rec.get("education") or ""
            rec["soft_skills"] = data.get("soft_skills") or []
            rec["technical_skills"] = data.get("technical_skills") or []
            rec["software"] = data.get("software") or []
            rec["work_arrangement"] = data.get("work_arrangement") or ""
            if data.get("languages"):
                rec["languages"] = data["languages"]
            if data.get("company"):
                rec["company"] = data["company"]
            # Mistral fait autorité sur l'intermédiaire (l'heuristique GraphQL
            # sur contactCompanyName donne des faux positifs intra-groupe).
            rec["intermediary"] = data.get("intermediary") or ""

    # Règle métier : si un intermédiaire est identifié mais pas l'entreprise
    # réelle, on marque l'entreprise comme "inconnu".
    if rec.get("intermediary") and not rec.get("company"):
        rec["company"] = "inconnu"
    return rec
