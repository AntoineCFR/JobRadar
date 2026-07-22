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

MATCH_VERSION = 7  # incrémenté à chaque refonte du matching -> force le re-matching


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


def _is_nonempty(v) -> bool:
    """Une section est « mentionnée » par le document si elle est non vide."""
    if v is None:
        return False
    if isinstance(v, str):
        return v.strip() != ""
    if isinstance(v, (list, dict)):
        return len(v) > 0
    return True  # nombres / bool = mentionnés


def _name_key_for(section: str) -> str:
    return {"languages": "language", "experience": "role"}.get(section, "name")


def _merge_list(section: str, old: list, new: list) -> list:
    """Fusion d'une section-liste. Listes d'objets -> fusion par nom (le nouveau
    écrase l'item de même nom, garde les autres). Listes de chaînes -> union."""
    if new and isinstance(new[0], dict):
        nk = _name_key_for(section)
        order: list = []
        by: dict = {}
        for it in list(old or []) + list(new):  # new après old => new écrase
            if isinstance(it, dict):
                nm = str(it.get(nk, "")).strip().lower()
                token = nm or f"__anon_{id(it)}"
            else:
                token = f"__str_{str(it).strip().lower()}"
            if token not in by:
                order.append(token)
            by[token] = it
        return [by[t] for t in order]
    # Listes de chaînes -> union en conservant l'ordre.
    seen: set = set()
    out: list = []
    for s in list(old or []) + list(new):
        t = str(s).strip().lower()
        if t and t not in seen:
            seen.add(t)
            out.append(s)
    return out


def merge_structured(existing: dict, new: dict) -> dict:
    """Fusion par section : une section NON VIDE du nouveau document est fusionnée
    dans l'existant (listes d'objets fusionnées par nom, scalaires écrasés) ; une
    section absente/vide du nouveau est CONSERVÉE telle quelle. Permet à un
    document ciblé (ex. fiche projet) de mettre à jour seulement ce qu'il mentionne.
    """
    merged = dict(existing or {})
    for k, v in (new or {}).items():
        if not _is_nonempty(v):
            continue  # non mentionné -> on garde l'existant
        old = merged.get(k)
        if isinstance(v, list) and isinstance(old, list):
            merged[k] = _merge_list(k, old, v)
        else:
            merged[k] = v  # scalaire ou nouvelle section -> écrase
    return merged


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


# --------------------------------------------------------------------------- #
# Barrière de langue — PLAFOND DÉTERMINISTE (autoritaire, hors LLM)
# --------------------------------------------------------------------------- #
# Le LLM ne respecte pas de façon fiable un plafond de score sur une langue
# rédhibitoire (ex. tchèque C2 exigé pour un candidat ~B1 -> il notait 35 %).
# On calcule donc le plafond en Python, APRÈS les agents, à partir des niveaux
# requis (offre) vs réels (candidat). La dégradation est exponentielle par palier
# CEFR au-dessus du niveau du candidat.
_CEFR = {"a1": 1, "a2": 2, "b1": 3, "b2": 4, "c1": 5, "c2": 6}
_CEFR_LABEL = {0: "aucune notion", 1: "A1", 2: "A2", 3: "B1", 4: "B2", 5: "C1", 6: "C2"}


def _cefr_level(text, *, high: bool) -> int:
    """Niveau CEFR (1-6) déduit d'un texte libre ; 0 si rien de détecté.

    `high=True` prend la borne HAUTE d'une plage (ex. "A2-B1" -> B1) — généreux
    pour le candidat. `high=False` prend la borne BASSE d'une exigence (ex. offre
    "C1-C2" -> plancher C1) — équitable côté offre.
    """
    if not text:
        return 0
    s = str(text).lower()
    found = [v for k, v in _CEFR.items() if k in s]
    if found:
        return max(found) if high else min(found)
    # Qualitatif (pas de token CEFR explicite).
    if any(w in s for w in ("natif", "native", "mother", "maternel", "rodil", "mateř", "bilingu")):
        return 6
    if any(w in s for w in ("fluent", "plynn", "courant", "proficient", "excellent")):
        return 5
    if any(w in s for w in ("advanced", "avancé", "business", "professional", "professionnel")):
        return 5
    if any(w in s for w in ("upper-intermediate", "upper intermediate")):
        return 4
    if any(w in s for w in ("intermediate", "intermédiaire", "communicative", "conversational")):
        return 3
    if any(w in s for w in ("elementary", "basic", "basique", "élémentaire", "beginner", "débutant", "notion")):
        return 2
    return 0


def _lang_key(name: str) -> str:
    """Clé canonique d'une langue pour apparier offre et candidat."""
    s = (name or "").lower()
    if "angl" in s or "engl" in s or s == "en":
        return "en"
    if any(w in s for w in ("tch", "cze", "czech", "češ", "česk", "čeɕ")) or s == "cs":
        return "cs"
    if any(w in s for w in ("allem", "german", "deutsch", "němč", "nemč")) or s == "de":
        return "de"
    if any(w in s for w in ("franç", "french", "franc")) or s == "fr":
        return "fr"
    if "slov" in s or s == "sk":
        return "sk"
    if any(w in s for w in ("espagn", "spanish", "español")) or s == "es":
        return "es"
    return s.strip()[:4]


def _cap_for_gap(gap: int) -> int:
    """Plafond de score selon l'écart (en paliers CEFR) au-dessus du candidat.

    Dégradation exponentielle : 1 palier = surmontable, 2 = très difficile,
    3+ = hors de portée (ex. B1 -> C2)."""
    if gap <= 0:
        return 100
    if gap == 1:  # ex. B1 -> B2 : envisageable
        return 42
    if gap == 2:  # ex. B1 -> C1 : très difficile
        return 15
    return 6      # ex. B1 -> C2 : illusoire


def _language_cap(profile_struct: dict, offer: dict) -> tuple[int, Optional[dict]]:
    """Plafond de score imposé par les langues IMPÉRATIVES que le candidat ne
    tient pas. Renvoie (cap, worst) où `worst` décrit la langue la plus bloquante.
    """
    cand: dict[str, int] = {}
    for l in (profile_struct.get("languages") or []):
        if isinstance(l, dict):
            k = _lang_key(l.get("language", ""))
            cand[k] = max(cand.get(k, 0), _cefr_level(l.get("level"), high=True))

    langs = offer.get("structured_languages") or offer.get("languages") or []
    cap = 100
    worst = None
    for l in langs:
        if not isinstance(l, dict) or not l.get("mandatory"):
            continue
        k = _lang_key(l.get("language", ""))
        req = _cefr_level(l.get("level"), high=False)
        if req == 0:
            # Impérative sans niveau explicite -> on exige le niveau PROFESSIONNEL
            # (B2) comme prérequis (usage quotidien de la langue).
            req = 4
        have = cand.get(k, 0)
        gap = req - have
        c = _cap_for_gap(gap)
        if c < cap:
            cap = c
            worst = {"language": l.get("language", ""), "req": req, "have": have, "gap": gap,
                     "level_text": l.get("level")}
    return cap, worst


def _band_for_score(score: int) -> str:
    if score >= 85:
        return "excellent"
    if score >= 50:
        return "bon"
    if score >= 30:
        return "moyen"
    return "faible"


def _apply_language_cap(result: dict, profile_struct: dict, offer: dict) -> dict:
    """Applique le plafond déterministe de langue au résultat des agents."""
    cap, worst = _language_cap(profile_struct, offer)
    if worst is None or result.get("score", 0) <= cap:
        return result

    result["score"] = cap
    result["band"] = _band_for_score(cap)

    # S'assurer qu'un point bloquant explicite existe pour cette langue.
    lang = worst["language"]
    blockers = result.get("blockers")
    if not isinstance(blockers, list):
        blockers = []
    already = any(
        isinstance(b, dict) and lang.lower() in str(b.get("issue", "")).lower()
        for b in blockers
    )
    if not already:
        req_txt = worst.get("level_text") or _CEFR_LABEL.get(worst["req"], "niveau professionnel")
        have_txt = _CEFR_LABEL.get(worst["have"], "aucune notion")
        blockers.insert(0, {
            "issue": f"{lang} {req_txt} exigé — hors de portée à court terme "
                     f"(ton niveau : {have_txt}).",
            "severity": "haute",
        })
        result["blockers"] = blockers
    return result


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
    # Plafond DÉTERMINISTE de langue (autoritaire, après les agents).
    result = _apply_language_cap(result, profile_struct, offer)
    result.setdefault("band", "moyen")
    result["match_version"] = MATCH_VERSION
    result["computed_at"] = dt.datetime.utcnow().isoformat() + "Z"
    return result
