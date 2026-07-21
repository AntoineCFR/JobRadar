"""Scraper Jobs.cz.

- `search()` : liste des offres (HTML + BeautifulSoup) pour un mot-clé + une ville.
- `fetch_detail()` : détail structuré d'une offre via l'API GraphQL cachée.

Repris et modernisé depuis l'ancien `JobScraper/src/scraping.py`.
"""
from __future__ import annotations

import time
import random
import logging
from dataclasses import dataclass, field
from typing import Optional
from urllib.parse import quote

import requests
from bs4 import BeautifulSoup

from config import USER_AGENT, SCRAPE_MIN_DELAY, SCRAPE_MAX_DELAY, SCRAPE_MAX_PAGES
from scraper.graphql_client import fetch_job_ad, resolve_employer_host, _session
from scraper.html_detail import fetch_detail_html

log = logging.getLogger("jobradar.jobs_cz")

SITE = "jobs.cz"
# Chaîne présente sur la page quand il n'y a plus de résultats.
_STOP_CONDITIONS = ["Bohužel jsme nenašli", "Sorry, we didn't find", "žádné nabídky"]


@dataclass
class ListingCard:
    """Offre telle que vue dans la liste de résultats (avant extraction détaillée)."""

    site: str
    id: str
    title: str
    company: str
    location: str
    link: str

    def to_dict(self) -> dict:
        return {
            "site": self.site,
            "id": self.id,
            "title": self.title,
            "company": self.company,
            "location": self.location,
            "link": self.link,
        }


def build_search_url(keyword: str, location: str, page: int = 1) -> str:
    """Construit l'URL de recherche Jobs.cz.

    Ex. keyword='data engineer', location='praha'
        -> https://www.jobs.cz/prace/praha/?q%5B%5D=data%20engineer&page=1
    """
    loc = (location or "").strip().lower().replace(" ", "-")
    path = f"/prace/{quote(loc)}/" if loc else "/prace/"
    q = quote(keyword.strip())
    return f"https://www.jobs.cz{path}?q%5B%5D={q}&page={page}"


def _parse_cards(html: str) -> list[ListingCard]:
    soup = BeautifulSoup(html, "html.parser")
    cards: list[ListingCard] = []
    for art in soup.select("article.SearchResultCard"):
        a = art.select_one("header > h2 > a")
        h2 = art.select_one("header > h2")
        lis = art.select("footer > ul > li")
        if not a or not a.get("data-jobad-id"):
            continue
        cards.append(
            ListingCard(
                site=SITE,
                id=str(a["data-jobad-id"]),
                title=(h2.get("data-test-ad-title") if h2 else None) or a.get_text(strip=True),
                company=lis[0].get_text(strip=True) if len(lis) > 0 else "",
                location=lis[1].get_text(strip=True) if len(lis) > 1 else "",
                link=a.get("href", ""),
            )
        )
    return cards


def search(
    keyword: str,
    location: str,
    max_pages: int = SCRAPE_MAX_PAGES,
    sess: Optional[requests.Session] = None,
    polite: bool = True,
) -> list[ListingCard]:
    """Parcourt les pages de résultats et retourne les cartes d'offres."""
    sess = sess or _session()
    results: list[ListingCard] = []
    seen: set[str] = set()
    for page in range(1, max_pages + 1):
        url = build_search_url(keyword, location, page)
        log.info("scraping page %s: %s", page, url)
        try:
            resp = sess.get(url, timeout=25)
        except requests.RequestException as e:
            log.warning("page %s failed: %s", page, e)
            break
        if any(cond in resp.text for cond in _STOP_CONDITIONS):
            log.info("stop condition reached at page %s", page)
            break
        cards = _parse_cards(resp.text)
        if not cards:
            log.info("no cards on page %s, ending", page)
            break
        new_on_page = 0
        for c in cards:
            if c.id in seen:
                continue
            seen.add(c.id)
            results.append(c)
            new_on_page += 1
        log.info("page %s: %s offers (%s new)", page, len(cards), new_on_page)
        if new_on_page == 0:  # pagination bouclée
            break
        if polite and page < max_pages:
            time.sleep(random.uniform(SCRAPE_MIN_DELAY, SCRAPE_MAX_DELAY))
    log.info("search done: %s unique offers", len(results))
    return results


def fetch_detail(card: ListingCard, sess: Optional[requests.Session] = None) -> Optional[dict]:
    """Récupère le détail structuré d'une offre.

    Deux voies :
      - offre sur un micro-site employeur ({employeur}.jobs.cz) -> API GraphQL ;
      - offre hébergée sur www.jobs.cz -> parsing HTML server-rendered.
    """
    sess = sess or _session()
    host = resolve_employer_host(card.link, sess)
    if host and host != "www.jobs.cz":
        job_ad = fetch_job_ad(card.id, card.link, sess=sess)
        if job_ad:
            return job_ad
        log.info("GraphQL failed for %s, trying HTML fallback", card.id)
    # www.jobs.cz ou échec GraphQL -> fallback HTML
    return fetch_detail_html(card, sess=sess)
