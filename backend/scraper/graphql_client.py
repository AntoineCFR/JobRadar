"""Client pour l'API GraphQL cachée de jobs.cz (capybara/LMC).

Pour une offre donnée (id + lien rpd), on :
 1. suit la redirection `www.jobs.cz/rpd/{id}/` -> `https://{employeur}.jobs.cz/...`
    pour découvrir le sous-domaine employeur ;
 2. récupère `widgetId` + `apiKey` depuis `script.min.js` de ce sous-domaine
    (mis en cache par domaine) ;
 3. POST la `DETAIL_QUERY` avec le header `x-api-key`.

Tout est en HTTP simple : aucun navigateur headless requis.
"""
from __future__ import annotations

import re
import json
import logging
from typing import Optional
from urllib.parse import urlparse

import requests

from config import USER_AGENT
from scraper.queries import GRAPHQL_ENDPOINT, DETAIL_QUERY

log = logging.getLogger("jobradar.graphql")

_WIDGET_RE = re.compile(r'"main-cs":\{"id":"([0-9a-fA-F\-]+)","apiKey":"([^"]+)"')
# Certains sites n'ont qu'un widget générique : filet de secours plus large.
_WIDGET_ANY_RE = re.compile(r'"id":"([0-9a-fA-F\-]{8,})","apiKey":"([^"]+)"')

# Cache {domaine_employeur: (widgetId, apiKey)} pour éviter de re-télécharger le JS.
_widget_cache: dict[str, tuple[str, str]] = {}


def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": USER_AGENT, "Accept-Language": "en,cs;q=0.8"})
    return s


def resolve_employer_host(rpd_url: str, sess: Optional[requests.Session] = None) -> Optional[str]:
    """Suit les redirections du lien d'offre pour trouver le sous-domaine employeur."""
    sess = sess or _session()
    try:
        r = sess.get(rpd_url, timeout=25, allow_redirects=True)
        host = urlparse(r.url).netloc
        return host or None
    except requests.RequestException as e:
        log.warning("resolve_employer_host failed for %s: %s", rpd_url, e)
        return None


def get_widget_credentials(
    host: str, sess: Optional[requests.Session] = None
) -> Optional[tuple[str, str]]:
    """Retourne (widgetId, apiKey) pour un sous-domaine employeur, avec cache."""
    if host in _widget_cache:
        return _widget_cache[host]
    sess = sess or _session()
    js_url = f"https://{host}/assets/js/script.min.js"
    try:
        js = sess.get(js_url, timeout=25).text
    except requests.RequestException as e:
        log.warning("could not fetch script.min.js for %s: %s", host, e)
        return None
    m = _WIDGET_RE.search(js) or _WIDGET_ANY_RE.search(js)
    if not m:
        log.info("no widget creds in script.min.js for %s (essai page inline)", host)
        return None
    creds = (m.group(1), m.group(2))
    _widget_cache[host] = creds
    return creds


# Widget v3 : config inline dans la page -> window.__LMC_CAREER_WIDGET__.push({...}).
_INLINE_WIDGET_RE = re.compile(r'__LMC_CAREER_WIDGET__\.push\((\{.*?\})\)')


def get_widget_credentials_from_page(
    page_url: str, host: str, sess: Optional[requests.Session] = None
) -> Optional[tuple[str, str]]:
    """Fallback : extrait widgetId + apiKey du HTML de la page détail (widget v3)."""
    sess = sess or _session()
    try:
        html = sess.get(page_url, timeout=25).text
    except requests.RequestException as e:
        log.warning("page fetch failed for creds (%s): %s", page_url, e)
        return None
    m = _INLINE_WIDGET_RE.search(html)
    if not m:
        return None
    try:
        cfg = json.loads(m.group(1))
        wid, key = cfg.get("widgetId"), cfg.get("apiKey")
        if wid and key:
            _widget_cache[host] = (wid, key)
            return (wid, key)
    except (ValueError, KeyError):
        pass
    return None


def fetch_job_ad(
    job_id: str, rpd_url: str, sess: Optional[requests.Session] = None
) -> Optional[dict]:
    """Récupère le JSON structuré d'une offre via l'API GraphQL.

    Retourne le dict `jobAd`, ou None si la résolution échoue.
    """
    sess = sess or _session()
    host = resolve_employer_host(rpd_url, sess)
    if not host:
        return None
    creds = get_widget_credentials(host, sess)
    if not creds:  # widget v3 : identifiants inline dans la page détail
        creds = get_widget_credentials_from_page(rpd_url, host, sess)
    if not creds:
        log.warning("aucun identifiant widget pour %s (%s)", job_id, host)
        return None
    widget_id, api_key = creds

    payload = {
        "query": DETAIL_QUERY,
        "variables": {
            "widgetId": widget_id,
            "jobAdId": str(job_id),
            "referer": f"https://{host}/",
            "host": host,
            "version": "v3",
            "rps": 0,
            "isNotLoggableToSessionLog": True,
            "cookieConsent": [],
        },
    }
    headers = {
        "Content-Type": "application/json",
        "Origin": f"https://{host}",
        "Referer": f"https://{host}/",
        "x-api-key": api_key,
    }
    try:
        r = sess.post(GRAPHQL_ENDPOINT, json=payload, headers=headers, timeout=30)
        r.raise_for_status()
        data = r.json()
    except (requests.RequestException, ValueError) as e:
        log.warning("GraphQL detail fetch failed for %s (%s): %s", job_id, host, e)
        return None
    if data.get("errors"):
        log.warning("GraphQL returned errors for %s: %s", job_id, data["errors"])
    job_ad = (data.get("data") or {}).get("widget", {}).get("jobAd")
    return job_ad
