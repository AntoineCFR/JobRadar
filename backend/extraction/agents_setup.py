"""Création / résolution des agents Mistral dédiés à JobRadar.

Deux agents (visibles dans la console Mistral) :
  - `extract`   : extraction structurée d'une offre -> JSON ;
  - `translate` : traduction cz->en d'une offre -> JSON.

Résolution des IDs, par ordre de priorité :
  variables d'env > cache Firestore (`config/mistral_agents`) > création via l'API
  (avec déduplication par nom pour ne jamais créer de doublon).
"""
from __future__ import annotations

import logging

import config

log = logging.getLogger("jobradar.agents_setup")

EXTRACT_INSTRUCTIONS = (
    "You extract structured data from a job advertisement written in English. "
    "Return ONLY a JSON object (no prose, no markdown fences). Be faithful to the "
    "text; use null or empty arrays when the information is absent. Never invent. "
    "JSON keys:\n"
    '- "summary": string, 2-3 sentence neutral summary in English.\n'
    '- "experience_years": integer or null (minimum years of experience required).\n'
    '- "education": string or null (required/desired level of study).\n'
    '- "soft_skills": string[] (human/interpersonal skills).\n'
    '- "technical_skills": string[] (hard/technical skills, methods, domains).\n'
    '- "software": string[] (named tools/software/technologies, e.g. Python, Power BI, SAP).\n'
    '- "work_arrangement": one of "on-site", "hybrid", "remote", or null.\n'
    '- "languages": array of {"language": string, "level": string|null, '
    '"mandatory": boolean, "reason": string}. Infer a language as mandatory even '
    "if not explicit when the context implies it (e.g. Czech required because the "
    'role serves Czech clients or is Czech-speaking). Fill "reason" briefly.\n'
    '- "company": string or null (the actual hiring/end company if identifiable).\n'
    '- "intermediary": string or null. Fill ONLY when a staffing/recruitment AGENCY '
    "is posting on behalf of a different end-client company. Return null for a "
    "company hiring for itself, including its own subsidiaries or entities of the "
    "same corporate group (same brand/name family is NOT an intermediary)."
)

TRANSLATE_INSTRUCTIONS = (
    "You are a professional translator for job advertisements. Translate the given "
    "Czech job offer into natural, professional English. Keep the meaning and tone. "
    "Never invent information. Return ONLY a JSON object (no prose, no markdown "
    'fences) with keys: "title" (string), "summary" (string, 2-3 sentences), '
    '"description_text" (string, the full offer translated, keep line breaks/bullets).'
)

_SPECS = {
    "extract": {"name": "JobRadar · Extraction offre", "instructions": EXTRACT_INSTRUCTIONS},
    "translate": {"name": "JobRadar · Traduction CZ→EN", "instructions": TRANSLATE_INSTRUCTIONS},
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
    """Retourne {'extract': id, 'translate': id}, en créant ce qui manque."""
    global _cache
    ids = dict(_cache)
    ids.update(_from_env())
    if len(ids) < len(_SPECS):
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
