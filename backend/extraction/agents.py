"""Agents Mistral : traduction cz->en + extraction des champs non structurés.

On utilise deux **agents dédiés** (créés via l'API, visibles dans la console —
voir agents_setup.py), interrogés en mode conversation. Chaque agent renvoie du
JSON, parsé de façon tolérante.
"""
from __future__ import annotations

import re
import json
import logging
from typing import Optional

from config import MISTRAL_API_KEY, MISTRAL_MODEL
from extraction.agents_setup import ensure_agents, _SPECS

log = logging.getLogger("jobradar.agents")

_client = None
# Passe à True si l'API Agents est inaccessible (clé sans permission) : on cesse
# alors de retenter la création à chaque offre et on va droit au repli chat.
_agents_disabled = False


def _get_client():
    global _client
    if _client is None:
        from mistralai.client import Mistral  # SDK v2.x : le client est dans mistralai.client

        _client = Mistral(api_key=MISTRAL_API_KEY, timeout_ms=180000)
    return _client


def _last_text(conversation) -> str:
    """Texte du dernier message assistant (outputs mélange plusieurs types)."""
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
    """Parse tolérant : retire les fences markdown, isole { … }, vire les virgules
    finales. Renvoie None si vraiment impossible."""
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
    """Repli : appel direct chat.complete avec les MÊMES instructions que l'agent.

    Utilisé si la clé Mistral n'a pas accès à l'API Agents (beta). Fonctionnement
    identique du point de vue métier.
    """
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


def _ask_agent(agent_key: str, user_text: str, max_chars: int = 12000) -> Optional[dict]:
    """Interroge l'agent dédié ; repli automatique sur chat.complete si l'API
    Agents n'est pas accessible avec la clé courante."""
    global _agents_disabled
    if not MISTRAL_API_KEY:
        log.warning("MISTRAL_API_KEY absent : agents désactivés")
        return None
    # 1) voie agent dédié (sautée si déjà constatée indisponible)
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
            log.warning("API Agents indisponible (%s) -> repli chat.complete pour ce process", e)
    # 2) repli chat.complete
    try:
        return _chat_fallback(agent_key, user_text, max_chars)
    except Exception as e:  # noqa: BLE001 - ne jamais casser le pipeline
        log.warning("repli chat '%s' échoué: %s", agent_key, e)
        return None


# --------------------------------------------------------------------------- #
# Agent 1 : traduction
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


# --------------------------------------------------------------------------- #
# Agent 2 : extraction / enrichissement
# --------------------------------------------------------------------------- #
def enrich_offer(text: str, hints: Optional[dict] = None) -> Optional[dict]:
    hints = hints or {}
    hint_str = json.dumps(
        {
            k: hints.get(k)
            for k in ("title", "company", "location_city", "location_country",
                      "sector", "languages", "education", "contract_type")
        },
        ensure_ascii=False,
    )
    return _ask_agent("extract", f"KNOWN STRUCTURED HINTS: {hint_str}\n\nOFFER TEXT:\n{text}")


# --------------------------------------------------------------------------- #
# Orchestration d'une offre
# --------------------------------------------------------------------------- #
def process_offer(rec: dict) -> dict:
    """Complète un enregistrement d'offre (base GraphQL) avec les agents Mistral.

    Sans clé Mistral, renvoie `rec` inchangé (le structuré GraphQL reste dispo).
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
            # Mistral fait autorité sur l'intermédiaire.
            rec["intermediary"] = data.get("intermediary") or ""

    if rec.get("intermediary") and not rec.get("company"):
        rec["company"] = "inconnu"
    return rec
