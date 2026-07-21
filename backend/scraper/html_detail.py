"""Fallback d'extraction pour les offres hébergées directement sur www.jobs.cz
(sans micro-site employeur, donc pas d'API GraphQL widget).

Ces pages sont rendues côté serveur : le contenu est dans le HTML, exposé via
des attributs `data-test` (jd-body-richtext, jd-info-item, jd-benefits...).
On produit un dict de la MÊME forme que le `jobAd` GraphQL pour réutiliser
`base_record_from_graphql` sans changement.
"""
from __future__ import annotations

import re
import logging
from typing import Optional

import requests
from bs4 import BeautifulSoup

from config import USER_AGENT

log = logging.getLogger("jobradar.html_detail")

# Correspondance étiquettes tchèques -> champs (page jobs.cz standard).
_LABELS = {
    "vzdělání": "education",
    "jazyky": "languages",
    "zařazeno": "sector",
    "typ pracovního poměru": "employment_type",
    "délka pracovního poměru": "employment_duration",
    "typ smluvního vztahu": "contract_type",
    "zadavatel": "advertiser",
    "společnost": "company",
    "mzda": "salary",
    "plat": "salary",
}


def detect_language(text: str) -> str:
    """Détection légère cs/en : les lettres ř ů ě sont quasi propres au tchèque."""
    if not text:
        return "en"
    cz_specific = len(re.findall(r"[řůěŘŮĚ]", text))
    return "cs" if cz_specific >= 3 else "en"


def _info_items(soup) -> dict:
    out: dict[str, str] = {}
    for it in soup.select('[data-test="jd-info-item"]'):
        parts = [p.strip() for p in it.get_text("|", strip=True).split("|") if p.strip()]
        if len(parts) < 2:
            continue
        label = parts[0].lower()
        value = " ".join(parts[1:]).strip()
        for key, field in _LABELS.items():
            if key in label:
                out[field] = value
                break
    return out


def _parse_languages(cz_value: str) -> list[dict]:
    # "Čeština (Výborná), Angličtina (Mírně pokročilá)"
    langs = []
    for chunk in cz_value.split(","):
        m = re.match(r"\s*([^(]+?)\s*(?:\(([^)]*)\))?\s*$", chunk)
        if m and m.group(1):
            langs.append({"language": m.group(1).strip(), "skill": (m.group(2) or "").strip()})
    return langs


def fetch_detail_html(card, sess: Optional[requests.Session] = None) -> Optional[dict]:
    """Récupère et parse une page www.jobs.cz standard -> dict façon `jobAd`."""
    sess = sess or requests.Session()
    try:
        r = sess.get(card.link, headers={"User-Agent": USER_AGENT, "Accept-Language": "cs,en;q=0.8"}, timeout=25)
        r.raise_for_status()
    except requests.RequestException as e:
        log.warning("html fallback fetch failed for %s: %s", card.id, e)
        return None

    soup = BeautifulSoup(r.text, "html.parser")
    body = soup.select_one('[data-test="jd-body-richtext"]') or soup.select_one("[class*=RichContent]")
    if not body:
        log.warning("no richtext body found for %s", card.id)
        return None

    html_content = body.decode_contents()
    text = body.get_text(" ", strip=True)
    h1 = soup.select_one("h1")
    info = _info_items(soup)
    benefits = [b.get_text(" ", strip=True) for b in soup.select('[data-test="jd-benefits"]')]

    job_ad: dict = {
        "id": card.id,
        "title": (h1.get_text(strip=True) if h1 else card.title),
        "headerText": None,
        "teaser": "",
        "validFrom": None,
        "languageIso": detect_language(text),
        "content": {"htmlContent": html_content, "sections": []},
        "salary": None,  # parsé plus bas si présent
        "suitableForGraduate": None,
        "fieldsObjects": [{"label": s.strip()} for s in info.get("sector", "").split(",") if s.strip()],
        "professionsObjects": [],
        "locationsObjects": [],
        "parameters": {
            "hoursPerWeek": None,
            "requiredEducation": info.get("education", ""),
            "allLanguagesRequired": None,
            "requiredLanguages": _parse_languages(info.get("languages", "")),
            "contractTypesObjects": [{"label": info["contract_type"]}] if info.get("contract_type") else [],
            "employmentTypesObjects": [{"label": info["employment_type"]}] if info.get("employment_type") else [],
            "employmentDurationsObjects": [{"label": info["employment_duration"]}] if info.get("employment_duration") else [],
            "benefitsObjects": [{"label": b} for b in benefits],
        },
        "employer": {
            "companyName": info.get("company", card.company),
            # "Zadavatel: Personální agentura" => intermédiaire ; sinon employeur direct.
            "contactCompanyName": info.get("company", card.company)
            if "agentura" in info.get("advertiser", "").lower() else None,
            "phone": None,
            "email": None,
        },
    }
    return job_ad
