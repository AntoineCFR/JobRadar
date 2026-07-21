"""Schéma cible d'une offre + normalisation des données brutes GraphQL.

Le document final écrit dans Firestore combine :
  - les champs déjà structurés par jobs.cz (GraphQL) -> normalisés ici ;
  - les champs déduits par Mistral (soft/hard skills, logiciels, XP, langues
    impératives, résumé, traduction) -> ajoutés dans extraction/agents.py.
"""
from __future__ import annotations

import re
from html import unescape
from typing import Optional

# Ordre / liste de référence des champs de la fiche offre (pour l'app).
OFFER_FIELDS = [
    "id", "site", "link", "apply_url",
    "title", "company", "intermediary",
    "published_at", "scraped_at", "source_language",
    "location_city", "location_region", "location_country",
    "sector", "profession",
    "contract_type", "employment_type", "work_arrangement", "hours_per_week",
    "education", "experience_years",
    "soft_skills", "technical_skills", "software",
    "languages",           # [{language, level, mandatory, reason}]
    "salary",              # {min, max, period, currency, raw}
    "benefits",
    "summary",             # résumé court (langue de travail de l'app)
    "description_html",    # contenu original nettoyé
    "translated",          # {title, summary, description_text} si traduit en EN
    "is_new",              # flag calculé au moment du run
]


def html_to_text(html: str) -> str:
    """Convertit le htmlContent de l'offre en texte lisible (pour Mistral)."""
    if not html:
        return ""
    text = re.sub(r"<\s*(br|/p|/li|/h\d)\s*>", "\n", html, flags=re.I)
    text = re.sub(r"<li[^>]*>", "\n• ", text, flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    text = unescape(text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n\s*\n\s*\n+", "\n\n", text)
    return text.strip()


def _labels(objs) -> list[str]:
    if not objs:
        return []
    out = []
    for o in objs:
        if isinstance(o, dict):
            lbl = o.get("label") or o.get("id")
            if lbl:
                out.append(str(lbl))
    return out


def _first_label(obj) -> Optional[str]:
    if isinstance(obj, dict):
        return obj.get("label") or obj.get("id")
    return None


def normalize_salary(sal: Optional[dict]) -> Optional[dict]:
    if not sal:
        return None
    mn, mx = sal.get("min"), sal.get("max")
    if mn is None and mx is None:
        return None
    cur = sal.get("currency") or "CZK"
    period = sal.get("period") or ""
    parts = []
    if mn and mx and mn != mx:
        parts.append(f"{mn:,}–{mx:,}".replace(",", " "))
    else:
        parts.append(f"{(mn or mx):,}".replace(",", " "))
    raw = f"{' '.join(parts)} {cur}{('/' + period.lower()) if period else ''}".strip()
    return {"min": mn, "max": mx, "period": period, "currency": cur, "raw": raw}


def base_record_from_graphql(card, job_ad: Optional[dict]) -> dict:
    """Construit le squelette normalisé à partir de la carte + du JSON GraphQL.

    Les champs "IA" (soft/hard skills, logiciels, XP, langues impératives,
    résumé, traduction) restent vides ici : ils sont remplis par les agents.
    """
    rec: dict = {
        "id": card.id,
        "site": card.site,
        "link": card.link,
        "apply_url": card.link,
        "title": card.title,
        "company": card.company or "",
        "intermediary": "",
        "published_at": None,
        "source_language": None,
        "location_city": card.location or "",
        "location_region": "",
        "location_country": "",
        "sector": "",
        "profession": "",
        "contract_type": "",
        "employment_type": "",
        "work_arrangement": "",
        "hours_per_week": None,
        "education": "",
        "experience_years": None,
        "soft_skills": [],
        "technical_skills": [],
        "software": [],
        "languages": [],
        "salary": None,
        "benefits": [],
        "benefits_categorized": None,
        "extraction_version": None,
        "summary": "",
        "description_html": "",
        "description_text": "",
        "translated": None,
        "raw_sections": [],
    }
    if not job_ad:
        return rec

    rec["title"] = job_ad.get("title") or rec["title"]
    rec["published_at"] = job_ad.get("validFrom")
    rec["source_language"] = (job_ad.get("languageIso") or "").lower() or None

    content = job_ad.get("content") or {}
    rec["description_html"] = content.get("htmlContent") or ""
    rec["description_text"] = html_to_text(rec["description_html"])
    rec["raw_sections"] = [
        {"title": s.get("title", ""), "text": s.get("text", "")}
        for s in (content.get("sections") or [])
    ]

    loc_objs = job_ad.get("locationsObjects")
    if isinstance(loc_objs, list):
        loc = loc_objs[0] if loc_objs else {}
    else:
        loc = loc_objs or {}
    if isinstance(loc, dict):
        rec["location_country"] = _first_label(loc.get("country")) or rec["location_country"]
        rec["location_region"] = _first_label(loc.get("region")) or rec["location_region"]
        rec["location_city"] = _first_label(loc.get("city")) or rec["location_city"]

    rec["sector"] = ", ".join(_labels(job_ad.get("fieldsObjects"))) or rec["sector"]
    rec["profession"] = ", ".join(_labels(job_ad.get("professionsObjects"))) or rec["profession"]

    params = job_ad.get("parameters") or {}
    rec["contract_type"] = ", ".join(_labels(params.get("contractTypesObjects")))
    rec["employment_type"] = ", ".join(_labels(params.get("employmentTypesObjects")))
    rec["hours_per_week"] = params.get("hoursPerWeek")
    rec["education"] = params.get("requiredEducation") or ""
    rec["benefits"] = _labels(params.get("benefitsObjects"))
    # langues structurées (code + niveau) ; enrichies ensuite par l'agent.
    langs = []
    for rl in params.get("requiredLanguages") or []:
        langs.append(
            {
                "language": rl.get("language"),
                "level": rl.get("skill"),
                "mandatory": bool(params.get("allLanguagesRequired")),
                "reason": "",
            }
        )
    rec["languages"] = langs

    rec["salary"] = normalize_salary(job_ad.get("salary"))
    rec["summary"] = job_ad.get("teaser") or ""

    emp = job_ad.get("employer") or {}
    company_name = emp.get("companyName") or rec["company"]
    rec["company"] = company_name or rec["company"]
    # L'intermédiaire (cabinet RH) est décidé par Mistral (cf. agents.py) ou par
    # le champ "Zadavatel" du fallback HTML : on ne devine PAS depuis
    # contactCompanyName (faux positifs intra-groupe).
    contact_company = emp.get("contactCompanyName") or ""
    if contact_company and "agentura" in contact_company.lower():
        rec["intermediary"] = contact_company
    return rec
