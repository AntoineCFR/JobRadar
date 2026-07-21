"""Agents Mistral — pipeline d'extraction multi-agents.

Chaîne par offre :
  (traduction cz->en) -> extract -> data_expert (ordre+explications) ->
  benefits (catégorisation) -> verify (contrôle de fidélité).

Chaque étape est un agent dédié (voir agents_setup.py), interrogé en mode
conversation, avec repli automatique sur chat.complete si l'API Agents n'est pas
accessible avec la clé courante.
"""
from __future__ import annotations

import re
import json
import logging
from typing import Optional

from config import MISTRAL_API_KEY, MISTRAL_MODEL
from extraction.agents_setup import ensure_agents, _SPECS

log = logging.getLogger("jobradar.agents")

EXTRACTION_VERSION = 4  # incrémenter pour forcer un re-traitement des offres

_client = None
_agents_disabled = False


def _get_client():
    global _client
    if _client is None:
        from mistralai.client import Mistral

        _client = Mistral(api_key=MISTRAL_API_KEY, timeout_ms=180000)
    return _client


def _last_text(conversation) -> str:
    for out in reversed(getattr(conversation, "outputs", []) or []):
        if getattr(out, "type", None) != "message.output":
            continue
        content = getattr(out, "content", None)
        if content is None:
            continue
        if isinstance(content, str):
            return content
        return "".join(getattr(c, "text", "") for c in content)
    return ""


def _loads_json(text: str) -> Optional[dict]:
    if not text:
        return None
    t = text.strip()
    if "```" in t:
        m = re.search(r"```(?:json)?\s*(.*?)```", t, re.S)
        if m:
            t = m.group(1).strip()
    start, end = t.find("{"), t.rfind("}")
    if start == -1 or end == -1 or end < start:
        return None
    frag = t[start : end + 1]
    for candidate in (frag, re.sub(r",(\s*[}\]])", r"\1", frag)):
        try:
            return json.loads(candidate, strict=False)
        except json.JSONDecodeError:
            continue
    return None


def _chat_fallback(agent_key: str, user_text: str, max_chars: int) -> Optional[dict]:
    client = _get_client()
    resp = client.chat.complete(
        model=MISTRAL_MODEL,
        messages=[
            {"role": "system", "content": _SPECS[agent_key]["instructions"]},
            {"role": "user", "content": user_text[:max_chars]},
        ],
        response_format={"type": "json_object"},
        temperature=0.1,
    )
    return _loads_json(resp.choices[0].message.content)


def _ask_agent(agent_key: str, user_text: str, max_chars: int = 14000) -> Optional[dict]:
    """Interroge l'agent dédié ; repli auto sur chat.complete si l'API Agents KO."""
    global _agents_disabled
    if not MISTRAL_API_KEY:
        return None
    if not _agents_disabled:
        try:
            client = _get_client()
            agent_id = ensure_agents(client)[agent_key]
            convo = client.beta.conversations.start(agent_id=agent_id, inputs=user_text[:max_chars])
            out = _loads_json(_last_text(convo))
            if out is not None:
                return out
        except Exception as e:  # noqa: BLE001
            _agents_disabled = True
            log.warning("API Agents indisponible (%s) -> repli chat.complete", e)
    try:
        return _chat_fallback(agent_key, user_text, max_chars)
    except Exception as e:  # noqa: BLE001
        log.warning("repli chat '%s' échoué: %s", agent_key, e)
        return None


# --------------------------------------------------------------------------- #
# Helpers de normalisation
# --------------------------------------------------------------------------- #
def _cap(s: str) -> str:
    """Majuscule initiale. Dé-majuscule un libellé entièrement en CAPITALES
    (« PRIME ANNUELLE » -> « Prime annuelle ») tout en préservant les acronymes
    et casses mixtes (SQL, MS Azure, Power BI)."""
    s = (s or "").strip()
    if not s:
        return s
    if s.isupper() and len(s) > 3:  # libellé tout en majuscules -> phrase
        s = s.capitalize()
    return s[:1].upper() + s[1:]


def _int_0_100(v) -> Optional[int]:
    try:
        return max(0, min(100, int(v)))
    except (TypeError, ValueError):
        return None


def _named_list(items) -> list[dict]:
    """Coerce en [{name, domain, level, weight, explanation}] (capitalisé)."""
    out = []
    for it in items or []:
        if isinstance(it, str) and it.strip():
            out.append({"name": _cap(it), "domain": "", "level": None, "weight": None, "explanation": ""})
        elif isinstance(it, dict) and it.get("name"):
            out.append({
                "name": _cap(str(it["name"])),
                "domain": str(it.get("domain", "") or "").strip(),
                "level": (str(it["level"]).strip() if it.get("level") else None),
                "weight": _int_0_100(it.get("weight")),
                "explanation": _cap(str(it.get("explanation", "") or "")),
            })
    return out


def _named_pairs(items) -> list[dict]:
    out = []
    for it in items or []:
        if isinstance(it, str) and it.strip():
            out.append({"name": _cap(it), "explanation": ""})
        elif isinstance(it, dict) and it.get("name"):
            out.append({"name": _cap(str(it["name"])), "explanation": _cap(str(it.get("explanation", "") or ""))})
    return out


def _norm_lang(name: str) -> str:
    s = (name or "").strip().lower()
    if any(k in s for k in ("tch", "cze", "czech", "češ", "česk")) or s == "cs":
        return "cs"
    if any(k in s for k in ("angl", "engl")) or s == "en":
        return "en"
    if any(k in s for k in ("allem", "germ", "něm", "deutsch")) or s == "de":
        return "de"
    if any(k in s for k in ("ital",)) or s == "it":
        return "it"
    if any(k in s for k in ("franç", "french")) or s == "fr":
        return "fr"
    if any(k in s for k in ("slov",)) or s == "sk":
        return "sk"
    if any(k in s for k in ("pol",)) or s == "pl":
        return "pl"
    return s[:3]


_CZ_LEVELS = {
    "základní": "Basic (A1-A2)",
    "mírně pokročilá": "Pre-intermediate (A2-B1)",
    "středně pokročilá": "Intermediate (B1-B2)",
    "pokročilá": "Advanced (B2-C1)",
    "výborná": "Excellent (C1-C2)",
    "rodilý mluvčí": "Native",
}


def _norm_level(lvl):
    if not lvl:
        return lvl
    return _CZ_LEVELS.get(str(lvl).strip().lower(), lvl)


def _merge_languages(agent_langs: list, structured_langs: list) -> list:
    """Fusionne : les langues du champ « requises » de l'offre (structuré) sont
    AUTORITAIRES et restent impératives ; l'agent enrichit (niveau/raison) et peut
    ajouter des langues déduites en plus."""
    structured_langs = structured_langs or []
    agent_langs = agent_langs or []
    if not structured_langs:
        return agent_langs
    required = {_norm_lang(l.get("language")) for l in structured_langs if l.get("language")}
    struct_by = {_norm_lang(l.get("language")): l for l in structured_langs if l.get("language")}
    out = []
    seen = set()
    for al in agent_langs:
        key = _norm_lang(al.get("language"))
        seen.add(key)
        if key in required:
            al = dict(al)
            al["mandatory"] = True  # présent dans les langues requises -> impératif
            if not al.get("level") and struct_by[key].get("level"):
                al["level"] = _norm_level(struct_by[key]["level"])
        out.append(al)
    # langues requises non reprises par l'agent -> on les ajoute
    for key in required - seen:
        sl = struct_by[key]
        out.append({
            "language": sl.get("language"),
            "level": _norm_level(sl.get("level")),
            "mandatory": True,
            "reason": "Langue listée comme requise dans l'offre.",
        })
    return out


_BENEFIT_CATS = ("flexibility", "financial", "training", "other")


def _empty_benefits() -> dict:
    return {c: [] for c in _BENEFIT_CATS}


# --------------------------------------------------------------------------- #
# Étapes
# --------------------------------------------------------------------------- #
def translate_to_english(title: str, text: str) -> Optional[dict]:
    out = _ask_agent("translate", f"TITLE: {title}\n\nOFFER (Czech):\n{text}")
    if not out:
        return None
    return {
        "title": out.get("title", title),
        "summary": out.get("summary", ""),
        "description_text": out.get("description_text", ""),
    }


def score_relevance(keyword: str, title: str, summary: str) -> Optional[dict]:
    """Pertinence de l'offre vs le mot-clé recherché (premier rideau)."""
    if not keyword:
        return None
    out = _ask_agent(
        "relevance",
        f"SEARCH KEYWORD: {keyword}\n\nOFFER TITLE: {title}\nOFFER SUMMARY: {summary}",
        max_chars=3000,
    )
    if not out:
        return None
    return {
        "score": _int_0_100(out.get("score")) or 0,
        "reason": str(out.get("reason", "") or ""),
        "keyword": keyword,
    }


def process_offer(rec: dict) -> dict:
    """Enrichit un enregistrement d'offre via la chaîne d'agents.

    Sans clé Mistral, renvoie `rec` inchangé (le structuré GraphQL reste dispo).
    """
    source_lang = (rec.get("source_language") or "").lower()
    original_text = rec.get("description_text") or ""
    working_title = rec.get("title") or ""
    working_text = original_text
    # Langues requises structurées (jobs.cz) = source autoritaire. On privilégie
    # la copie brute `structured_languages` (survit à une ré-analyse) ; à défaut,
    # rec["languages"] tel que posé par base_record avant l'agent.
    structured_langs = list(rec.get("structured_languages") or rec.get("languages") or [])

    # 0) Traduction cz -> en (on garde les 2 versions).
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

    if not working_text:
        rec["extraction_version"] = EXTRACTION_VERSION
        return rec

    # 1) Extraction de base.
    raw_software, raw_tech = [], []
    base = _ask_agent("extract", f"OFFER TEXT:\n{working_text}")
    if base:
        rec["summary"] = base.get("summary") or rec.get("summary") or ""
        rec["experience_years"] = base.get("experience_years")
        rec["education"] = base.get("education") or rec.get("education") or ""
        rec["work_arrangement"] = base.get("work_arrangement") or ""
        rec["soft_skills"] = [_cap(s) for s in (base.get("soft_skills") or []) if isinstance(s, str) and s.strip()]
        if base.get("languages") or structured_langs:
            rec["languages"] = _merge_languages(base.get("languages"), structured_langs)
        if base.get("company"):
            rec["company"] = base["company"]
        rec["intermediary"] = base.get("intermediary") or ""
        raw_software = base.get("software") or []
        raw_tech = base.get("technical_skills") or []

    # 2) Expert Data : ordre + explications.
    software = _named_list(raw_software)
    technical = _named_list(raw_tech)
    if raw_software or raw_tech:
        de = _ask_agent(
            "data_expert",
            f"INPUT: {json.dumps({'software': raw_software, 'technical_skills': raw_tech}, ensure_ascii=False)}"
            f"\n\nOFFER TEXT:\n{working_text}",
        )
        if de:
            software = _named_list(de.get("software")) or software
            technical = _named_list(de.get("technical_skills")) or technical

    # 3) Avantages : catégorisation (source = benefits GraphQL + texte).
    raw_benefits = rec.get("benefits") or []
    benefits_cat = _empty_benefits()
    benefits_cat["other"] = _named_pairs(raw_benefits)
    if raw_benefits:
        bn = _ask_agent(
            "benefits",
            f"BENEFITS: {json.dumps(raw_benefits, ensure_ascii=False)}\n\nOFFER TEXT:\n{working_text}",
        )
        if bn:
            benefits_cat = {c: _named_pairs(bn.get(c)) for c in _BENEFIT_CATS}

    # 4) Vérificateur de fidélité.
    draft = {"software": software, "technical_skills": technical, "benefits": benefits_cat}
    vr = _ask_agent(
        "verify",
        f"OFFER TEXT:\n{working_text}\n\nDRAFT JSON:\n{json.dumps(draft, ensure_ascii=False)}",
    )
    if vr:
        software = _named_list(vr.get("software")) or software
        technical = _named_list(vr.get("technical_skills")) or technical
        if isinstance(vr.get("benefits"), dict):
            benefits_cat = {c: _named_pairs(vr["benefits"].get(c)) for c in _BENEFIT_CATS}

    rec["software"] = software
    rec["technical_skills"] = technical
    rec["benefits_categorized"] = benefits_cat
    rec["extraction_version"] = EXTRACTION_VERSION

    if rec.get("intermediary") and not rec.get("company"):
        rec["company"] = "inconnu"
    return rec
