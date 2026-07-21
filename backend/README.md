# JobRadar — Backend (Flask)

Scrape Jobs.cz, extrait les infos-clés via agents Mistral, écrit dans Firestore
et notifie les nouveautés par push FCM. **100 % HTTP — aucun navigateur headless.**

## Pipeline

```
liste (HTML + BeautifulSoup)
   └─ filtre : ids inconnus en base = nouveautés
        └─ détail :
             ├─ micro-site employeur {employeur}.jobs.cz  → API GraphQL capybara/LMC
             └─ offre sur www.jobs.cz                     → parsing HTML server-rendered
                  └─ agents Mistral (traduction cz→en + extraction)
                       └─ Firestore (offers/{id})
                            └─ push FCM (topic « offers »)
```

### Le mécanisme Jobs.cz (important)
- **Liste** : `https://www.jobs.cz/prace/{ville}/?q[]={motcle}&page={n}`, cartes
  `article.SearchResultCard`.
- **Détail** : le lien `/rpd/{id}/` redirige vers le micro-site de l'employeur.
  Ces pages sont rendues en JS, mais chargent leurs données via l'**API GraphQL
  cachée** `api.capybara.lmc.cz/api/graphql/widget`. On récupère `widgetId` +
  `apiKey` dans le `script.min.js` de l'employeur (header `x-api-key` obligatoire),
  puis on POST la `DETAIL_QUERY`. Renvoie du **structuré** : titre, sections,
  `validFrom`, `languageIso`, salaire, langues, contrat, secteur, benefits, etc.
- Certaines offres restent sur `www.jobs.cz` (pas de micro-site) → fallback
  parsing HTML (`data-test="jd-body-richtext"`, `jd-info-item`, `jd-benefits`).

Détail complet des sélecteurs/queries : commentaires dans `scraper/`.

## Ce que fait Mistral (le reste est déjà structuré par jobs.cz)
Séparation soft/hard skills, logiciels, années d'expérience, nécessité d'une
langue (ex. tchèque déduit), résumé, et **traduction cz→en** (on garde les 2
versions pour la bascule 🇨🇿/🇬🇧 dans l'app).

## Lancer en local
```bash
python -m venv venv && ./venv/Scripts/pip install -r requirements.txt
cp .env.example .env      # renseigner MISTRAL_API_KEY (et FIREBASE_* pour écrire)
# Test du pipeline sans Firestore (dry-run, écrit data/test_output.json) :
./venv/Scripts/python scripts/test_pipeline.py "data engineer" praha 2
# API :
./venv/Scripts/python app.py     # http://localhost:8000/health
```

## Endpoints
| Méthode | Route | Rôle |
|---|---|---|
| GET | `/health` | statut + dépendances prêtes |
| POST | `/scrape` | lance un run (async). Body `{keyword, location, max_pages?}`. Header `X-JobRadar-Key`. |
| GET | `/status` | résumé du dernier run |

## Déploiement (Render)
`render.yaml` crée un **web service** (API) + un **cron** quotidien
(`scripts/run_daily.py`). Secrets à régler dans le dashboard :
`MISTRAL_API_KEY`, `FIREBASE_CREDENTIALS_JSON` (JSON du service account inline),
`API_SHARED_SECRET`. Les recherches du cron sont dans la collection Firestore
`searches` (amorcée avec `config.DEFAULT_DAILY_SEARCHES`).
