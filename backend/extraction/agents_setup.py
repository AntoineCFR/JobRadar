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
    '- "soft_skills": string[] IN FRENCH, sentence case (human/interpersonal skills, '
    'e.g. "Esprit analytique", "Travail en équipe").\n'
    '- "technical_skills": string[] (hard/technical skills, methods, domains — names only).\n'
    '- "software": string[] (named tools/software/technologies/languages — names only).\n'
    '- "languages": array of {"language","level"(string|null),"mandatory"(bool),"reason"}. '
    "ALWAYS include Czech with mandatory=true whenever the ad requires native/fluent "
    "Czech, is written in Czech, or the role clearly needs Czech (Czech clients/team). "
    "Set mandatory=true for any language the ad states as required/essential, even if "
    "other languages (e.g. English) are also required.\n"
    '- "company": string or null (the real hiring/end company).\n'
    '- "intermediary": string or null — ONLY a staffing/recruitment AGENCY posting for a '
    "different end client; null for a company hiring for itself or its own group."
)

DATA_EXPERT_INSTRUCTIONS = (
    "You are a senior expert in Data / IT job markets, advising a FRENCH-speaking "
    "candidate. Given a job ad text and lists of technical skills and software, produce "
    "a refined, categorised view. Return ONLY a JSON object with two keys \"software\" "
    "and \"technical_skills\". Each is an ARRAY of objects:\n"
    '  {"name": proper-cased string (e.g. "Python", "Power BI", "Kubernetes"),\n'
    '   "domain": FRENCH data/IT sub-domain — pick the most accurate. Typical: '
    '"Langages", "ETL/ELT", "Data cleaning", "Bases de données", "Cloud & plateformes", '
    '"Orchestration", "CI/CD", "Big Data", "BI & visualisation", "Machine Learning", '
    '"Méthodologie" (you may use another if clearly better),\n'
    '   "level": one of "Maîtrise", "Pratique", "Connaissance", "Culture générale" — '
    "inferred from how the ad phrases it (proficient/expert -> Maîtrise; have worked "
    "with / experience with -> Pratique; knowledge of -> Connaissance; aware of / "
    "familiar with -> Culture générale; if unspecified, infer from context),\n"
    '   "weight": integer 0-100 for that level (Maîtrise~90, Pratique~65, '
    "Connaissance~40, Culture générale~20; nuance within),\n"
    '   "explanation": ONE FRENCH sentence, starting with a capital letter and ending '
    "with a period, saying what it is and the expected mastery for this role.}\n"
    "ORDER each array so items are GROUPED BY DOMAIN (contiguous), most important domain "
    "first, and within a domain by decreasing weight. Never invent items absent from the "
    "input/text; merge duplicates; normalise names."
)

BENEFITS_INSTRUCTIONS = (
    "You extract and classify the perks/benefits of a job ad for a FRENCH-speaking "
    "candidate. Consider BOTH the provided benefits list AND any benefit mentioned in "
    "the OFFER TEXT — extract those from the text too (job ads often list perks only in "
    "prose). Return ONLY a JSON object with keys, in this order: \"flexibility\" (remote, "
    "home office, flexible hours, extra holidays, sick days...), \"financial\" (bonuses, "
    "pension/insurance, meal vouchers, cafeteria, MultiSport, salary extras...), "
    "\"training\" (courses, conferences, language lessons, certifications...), \"other\" "
    "(everything else). Each value is an ARRAY of {\"name\": short FRENCH label in "
    "normal sentence case (only the first letter capital, NEVER all-caps), "
    "\"explanation\": ONE FRENCH sentence, starting with a capital and ending with a "
    "period, INCLUDING any concrete detail from the ad (amount, duration, condition — "
    "e.g. \"Tickets restaurant de 100 CZK par jour.\")}. Never invent; empty array if a "
    "category has none."
)

VERIFY_INSTRUCTIONS = (
    "You are a faithfulness checker. Given the job ad text and a JSON draft of its "
    "extracted software, technical_skills and categorised benefits, return the SAME JSON "
    "structure, corrected: REMOVE any item not supported by the text, fix wrong "
    "explanations, drop hallucinated levels. KEEP every field of each skill item "
    "(name, domain, level, weight, explanation) and keep benefits' 4 sub-keys and the "
    "given ordering. Ensure explanations are in French, start with a capital and end "
    "with a period. Return ONLY the corrected JSON object with keys \"software\", "
    "\"technical_skills\", \"benefits\"."
)

RELEVANCE_INSTRUCTIONS = (
    "You judge how well a job offer matches the SEARCH KEYWORD a candidate typed. "
    "Return ONLY a JSON object: {\"score\": integer 0-100, \"reason\": one short FRENCH "
    "sentence}. Guidance: same role as searched ~90-100; closely adjacent role (e.g. "
    "searched 'Data Engineer' -> offer 'Data Scientist' / 'Data Analyst' / 'Python "
    "Developer' / 'ETL Developer' / 'BI Developer') ~50-80 depending on overlap; loosely "
    "related ~30-50; unrelated (e.g. 'Process Engineer', 'Sales', 'Accountant') <30. "
    "Judge on the role/skills, not the seniority."
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
    '- "languages": array of {"language","level"}. Use the level(s) EXACTLY as stated '
    "in the document, verbatim (e.g. document says English C1-C2 -> \"C1-C2\"; Czech "
    "\"A2 solide, proche B1\" -> \"A2-B1\"; French natif -> \"C2 (natif)\"). NEVER "
    "downgrade, round, or invent a level.\n"
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
    "relevance": {"name": "JobRadar · Pertinence recherche", "instructions": RELEVANCE_INSTRUCTIONS},
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


def rebuild_agents(client) -> dict:
    """Supprime les agents JobRadar existants et les recrée avec les instructions
    COURANTES (à appeler après avoir modifié un prompt). Déterministe : évite
    l'ambiguïté de versioning de l'API `agents.update`."""
    global _cache
    try:
        names = {spec["name"] for spec in _SPECS.values()}
        page = client.beta.agents.list()
        items = getattr(page, "data", None) or page or []
        for a in items:
            if getattr(a, "name", None) in names:
                try:
                    client.beta.agents.delete(agent_id=a.id)
                    log.info("agent supprimé: %s", a.name)
                except Exception as e:  # noqa: BLE001
                    log.warning("delete %s échoué: %s", a.id, e)
    except Exception as e:  # noqa: BLE001
        log.warning("list/delete agents échoué: %s", e)

    ids = {}
    for key, spec in _SPECS.items():
        agent = client.beta.agents.create(
            model=config.MISTRAL_MODEL,
            name=spec["name"],
            description=spec["name"],
            instructions=spec["instructions"],
        )
        ids[key] = agent.id
        log.info("agent (re)créé: %s -> %s", spec["name"], agent.id)
    _cache = ids
    _save_firestore(ids)
    return ids


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
