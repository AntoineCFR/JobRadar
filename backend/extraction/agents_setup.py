"""Création / résolution des agents Mistral dédiés à JobRadar.

Deux pipelines :
  Extraction (par offre)     : extract -> data_expert -> benefits -> verify (+ translate)
  Conseil / matching (offre × profil) : profile, match, calibrate

Résolution des IDs par ordre : variables d'env > cache Firestore
(`config/mistral_agents`) > création via l'API (dédup par nom). Les agents
apparaissent dans la console Mistral.
"""
from __future__ import annotations

import logging

import config

log = logging.getLogger("jobradar.agents_setup")

# --------------------------------------------------------------------------- #
# Pipeline 1 — Extraction
# --------------------------------------------------------------------------- #
EXTRACT_INSTRUCTIONS = (
    "You extract structured data from a job advertisement written in English. "
    "Return ONLY a JSON object (no prose, no markdown fences). Be faithful; use "
    "null or empty arrays when absent. Never invent. Keys:\n"
    '- "summary": string, 2-3 sentence neutral English summary.\n'
    '- "experience_years": integer or null (minimum years of experience required).\n'
    '- "education": string or null (required/desired level of study).\n'
    '- "work_arrangement": "on-site" | "hybrid" | "remote" | null.\n'
    '- "soft_skills": string[] (human/interpersonal skills).\n'
    '- "technical_skills": string[] (hard/technical skills, methods, domains — names only).\n'
    '- "software": string[] (named tools/software/technologies/languages — names only).\n'
    '- "languages": array of {"language","level"(string|null),"mandatory"(bool),"reason"}. '
    "Infer mandatory from context (e.g. Czech implied by Czech clients).\n"
    '- "company": string or null (the real hiring/end company).\n'
    '- "intermediary": string or null — ONLY a staffing/recruitment AGENCY posting for a '
    "different end client; null for a company hiring for itself or its own group."
)

DATA_EXPERT_INSTRUCTIONS = (
    "You are a senior expert in Data / IT job markets. Given a job ad text and lists "
    "of technical skills and software/technologies, you rewrite them for a candidate. "
    "Return ONLY a JSON object with two keys: \"software\" and \"technical_skills\". "
    "Each is an ARRAY of objects {\"name\": string, \"explanation\": string (one concise "
    "sentence: what it is / why this role needs it), \"level\": string|null (required "
    "proficiency if the ad implies one, e.g. \"expert\", \"advanced\", \"notions\")}. "
    "ORDER each array: first by decreasing required level/importance, then group items "
    "logically (e.g. languages -> libraries/frameworks -> cloud & data platforms -> "
    "orchestration/CI -> databases -> BI/visualisation -> methodology). Do not add items "
    "absent from the input/text; you may merge duplicates and normalise names."
)

BENEFITS_INSTRUCTIONS = (
    "You classify the perks/benefits of a job ad into four ordered categories. "
    "Return ONLY a JSON object with keys, in this order: \"flexibility\" (work "
    "flexibility: remote, home office, flexible hours, extra holidays, sick days...), "
    "\"financial\" (financial contributions: bonuses, pension/insurance, meal vouchers, "
    "cafeteria, MultiSport...), \"training\" (learning & development: courses, "
    "conferences, language lessons, certifications...), \"other\" (everything else). "
    "Each value is an ARRAY of {\"name\": string, \"explanation\": string (one short "
    "sentence)}. Only use benefits present in the input; never invent. Empty array if none."
)

VERIFY_INSTRUCTIONS = (
    "You are a faithfulness checker. Given the job ad text and a JSON draft of its "
    "extracted software, technical_skills and categorised benefits, you return the SAME "
    "JSON structure, corrected: REMOVE any item not supported by the text, fix wrong "
    "explanations, drop hallucinated levels. Keep the given ordering/grouping otherwise. "
    "Return ONLY the corrected JSON object with keys \"software\", \"technical_skills\", "
    "\"benefits\" (benefits keeps its 4 sub-keys)."
)

TRANSLATE_INSTRUCTIONS = (
    "You are a professional translator for job advertisements. Translate the given "
    "Czech job offer into natural, professional English. Keep meaning and tone. Never "
    "invent. Return ONLY a JSON object (no fences) with keys: \"title\", \"summary\" "
    "(2-3 sentences), \"description_text\" (full offer, keep line breaks/bullets)."
)

# --------------------------------------------------------------------------- #
# Pipeline 2 — Conseil / matching
# --------------------------------------------------------------------------- #
PROFILE_INSTRUCTIONS = (
    "You analyse a candidate's CV / skills document (already OCR'd to text). Return "
    "ONLY a JSON object describing the candidate factually (never flatter, never "
    "invent). Keys:\n"
    '- "headline": string (one line, e.g. \"Data analyst, 2y, FR/EN\").\n'
    '- "seniority": "junior" | "mid" | "senior" | null.\n'
    '- "total_experience_years": number or null.\n'
    '- "domains": array of {"domain": string, "years": number|null} (fields the '
    "candidate has real experience in).\n"
    '- "hard_skills": string[]; "software": string[]; "soft_skills": string[].\n'
    '- "languages": array of {"language","level" (CEFR if possible, e.g. B1)}.\n'
    '- "education": string[]; "certifications": string[].\n'
    '- "strengths": string[]; "gaps": string[] (weaknesses vs typical data roles, e.g. '
    "\"no data engineering experience\").\n"
    '- "summary": string (3-4 sentences, neutral)."'
)

MATCH_INSTRUCTIONS = (
    "You are a career advisor. Given a CANDIDATE profile (JSON) and a JOB offer (JSON), "
    "assess honestly the candidate's chance of landing THIS job. Be realistic, not "
    "encouraging. Return ONLY a JSON object:\n"
    '- "score": integer 0-100 (probability of getting an interview/offer given the gap).\n'
    '- "band": "faible" | "moyen" | "bon" | "excellent".\n'
    '- "verdict": string (one sentence, French).\n'
    '- "synthese": string (French, 3-5 sentences: what fits, what is missing).\n'
    '- "blockers": array of {"issue": string (French), "severity": "haute"|"moyenne"|'
    '"basse"} — hard mismatches (missing mandatory language level, required years of '
    "experience the candidate lacks, mandatory skill absent...).\n"
    '- "matches": string[] (French, concrete strengths that fit this offer).\n'
    '- "plan": array of strings (French, actionable: what to highlight, how to '
    "compensate a gap, what to learn/prepare). "
    "Weigh mandatory languages and required experience heavily."
)

CALIBRATE_INSTRUCTIONS = (
    "You audit a career-advisor assessment for over-optimism. Given the candidate "
    "profile, the job offer and a draft assessment JSON, return the SAME JSON structure "
    "corrected: adjust \"score\"/\"band\" so they reflect the blockers (a high-severity "
    "blocker such as a missing mandatory language or required experience should cap the "
    "score low), remove unjustified blockers, keep it honest and consistent. Return ONLY "
    "the corrected JSON object (same keys as the draft)."
)

_SPECS = {
    # extraction
    "extract": {"name": "JobRadar · Extraction offre", "instructions": EXTRACT_INSTRUCTIONS},
    "data_expert": {"name": "JobRadar · Expert Data (technos)", "instructions": DATA_EXPERT_INSTRUCTIONS},
    "benefits": {"name": "JobRadar · Avantages", "instructions": BENEFITS_INSTRUCTIONS},
    "verify": {"name": "JobRadar · Vérificateur extraction", "instructions": VERIFY_INSTRUCTIONS},
    "translate": {"name": "JobRadar · Traduction CZ→EN", "instructions": TRANSLATE_INSTRUCTIONS},
    # matching
    "profile": {"name": "JobRadar · Analyse profil", "instructions": PROFILE_INSTRUCTIONS},
    "match": {"name": "JobRadar · Matching offre/profil", "instructions": MATCH_INSTRUCTIONS},
    "calibrate": {"name": "JobRadar · Calibrage score", "instructions": CALIBRATE_INSTRUCTIONS},
}
_CONFIG_DOC = "mistral_agents"
_cache: dict[str, str] = {}


def _from_env() -> dict:
    ids = {}
    if config.MISTRAL_EXTRACT_AGENT_ID:
        ids["extract"] = config.MISTRAL_EXTRACT_AGENT_ID
    if config.MISTRAL_TRANSLATE_AGENT_ID:
        ids["translate"] = config.MISTRAL_TRANSLATE_AGENT_ID
    return ids


def _from_firestore() -> dict:
    try:
        from store import firestore_store

        return firestore_store.get_config(_CONFIG_DOC) or {}
    except Exception as e:  # noqa: BLE001
        log.warning("cache Firestore agents indisponible: %s", e)
        return {}


def _save_firestore(ids: dict) -> None:
    try:
        from store import firestore_store

        firestore_store.set_config(_CONFIG_DOC, ids)
    except Exception as e:  # noqa: BLE001
        log.warning("sauvegarde IDs agents (Firestore) échouée: %s", e)


def _existing_by_name(client) -> dict:
    """Retrouve des agents déjà créés d'après leur nom (déduplication)."""
    found = {}
    try:
        names = {spec["name"]: key for key, spec in _SPECS.items()}
        page = client.beta.agents.list()
        items = getattr(page, "data", None) or page or []
        for a in items:
            nm = getattr(a, "name", None)
            if nm in names:
                found[names[nm]] = a.id
    except Exception as e:  # noqa: BLE001
        log.warning("list agents échoué: %s", e)
    return found


def ensure_agents(client) -> dict:
    """Retourne {key: agent_id} pour tous les agents, en créant ce qui manque."""
    global _cache
    ids = dict(_cache)
    ids.update(_from_env())
    if any(k not in ids for k in _SPECS):
        for k, v in _from_firestore().items():
            ids.setdefault(k, v)

    missing = [k for k in _SPECS if k not in ids]
    if missing:
        by_name = _existing_by_name(client)
        for k in list(missing):
            if k in by_name:
                ids[k] = by_name[k]
                missing.remove(k)

    if missing:
        for k in missing:
            spec = _SPECS[k]
            agent = client.beta.agents.create(
                model=config.MISTRAL_MODEL,
                name=spec["name"],
                description=spec["name"],
                instructions=spec["instructions"],
            )
            ids[k] = agent.id
            log.info("agent créé: %s -> %s", spec["name"], agent.id)
        _save_firestore(ids)

    _cache = ids
    return ids
