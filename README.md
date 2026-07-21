# JobRadar

Portail de veille d'offres d'emploi. On choisit un site (Jobs.cz pour l'instant),
un mot-clé et une localisation, on lance un scraping ; des **agents Mistral**
ouvrent chaque offre, en extraient les infos-clés (et traduisent le tchèque en
anglais), et l'app affiche le tout en tuiles + fiches détaillées, en flaguant les
nouveautés. Un cron quotidien récupère les nouvelles offres et envoie une notif push.

> Refonte complète de l'ancien `JobScraper` (laissé intact à côté).

## Architecture
```
app/ (Flutter, Android+iOS)  ──lit en direct──►  Firestore  ◄──écrit──  backend/ (Flask, Render)
        │  déclenche POST /scrape ─────────────────────────────────────────►  │
        └──────────────────  push FCM « X nouvelles offres »  ◄───────────────┘
```
- **backend/** — scraping Jobs.cz (HTTP, y c. une API GraphQL cachée) + agents
  Mistral + écriture Firestore + push FCM + cron quotidien. Voir `backend/README.md`.
- **app/** — Flutter : login Google, liste d'offres (tuiles, badge NOUVEAU),
  fiche détaillée (icônes Material Symbols, bascule 🇨🇿/🇬🇧), lancement de recherche
  en pop-up. AppBar + drawer d'options + bandeau footer (conventions maison).

## État (v0.1.0)
✅ **Cœur validé en conditions réelles** : scraping liste + détail (2 voies) et
extraction Mistral testés sur des offres live Jobs.cz (voir
`backend/data/test_output.json`). Backend compile et tourne. App Flutter compile
sans erreur (`flutter analyze` = 0).

⏳ **Reste** : brancher Firebase (config native + service account), déployer sur
Render, générer les artefacts de build. → voir **« Ta liste de courses »** ci-dessous.

## 🛒 Ta liste de courses (ce que je ne peux pas faire en CLI)

1. **Projet Firebase** (console Firebase → nouveau projet, ex. `jobradar-app`) :
   - Activer **Firestore** (mode production) et **Authentication → Google**.
   - Activer **Cloud Messaging** (push).
   - **Android** : ajouter une app Android `com.AntoineCFR.jobradar`, télécharger
     `google-services.json` → `app/android/app/google-services.json`.
   - **iOS** : ajouter une app iOS `com.AntoineCFR.jobradar`, télécharger
     `GoogleService-Info.plist` → `app/ios/Runner/GoogleService-Info.plist`.
     (Push iOS = clé APNs à charger dans Firebase, comme pour Track-It.)
   - **Service account** (Paramètres → Comptes de service → générer une clé privée) :
     le JSON servira au backend (`FIREBASE_CREDENTIALS_JSON` sur Render).
   - Déployer les règles : `firebase deploy --only firestore:rules` (fichier
     `firestore.rules` fourni ; y coller ton UID si tu veux verrouiller au compte).
2. **Clé Mistral** : je réutilise `MISTRAL_API_KEY` (déjà dans l'ancien projet) —
   confirme si tu veux une clé dédiée. À mettre sur Render.
3. **Render** : créer les 2 services depuis `render.yaml` (web + cron), et régler
   les secrets `MISTRAL_API_KEY`, `FIREBASE_CREDENTIALS_JSON`, `API_SHARED_SECRET`.
   (Les recherches du cron vivent dans la collection Firestore `searches`, pas
   dans une variable d'environnement.)
4. **Build de l'app** avec l'URL du backend + le secret :
   `flutter run --dart-define=JOBRADAR_API=https://<ton-api>.onrender.com --dart-define=JOBRADAR_KEY=<API_SHARED_SECRET>`
   (iOS toujours via Codemagic — hand-edit pbxproj comme Track-It).
5. **Vérifs à me remonter** : le login Google, l'arrivée des tuiles après un
   scrape, la bascule 🇨🇿/🇬🇧 sur une offre tchèque, la notif quotidienne.

## Notes de version
### v0.6.0 (2026-07-21) — pertinence, filtres, tri, correctifs
- **Agent de pertinence** (premier rideau) : score offre vs mot-clé recherché → affiché sur la tuile (jauge « Pertinence », sous les icônes, au-dessus de « Match »).
- **Filtres** (dialogue) : pertinence min., compatibilité min., mode de travail, junior only, masquer si tchèque impératif, nouveautés. Badge de compte sur l'icône.
- **Tri** par menu : pertinence / compatibilité / date.
- **Tchèque impératif** : le drapeau 🇨🇿 encadré rouge prime désormais sur les autres langues (critère bloquant) ; prompt d'extraction renforcé.
- **Info-bulles noires au clic** sur les icônes des tuiles.
- **Offres vides corrigées** : support du widget capybara v3 (identifiants inline `__LMC_CAREER_WIDGET__` dans la page) → sites type Bühler désormais récupérés.

### v0.5.3 (2026-07-21) — vraie jauge de progression X / Y
- Le backend expose l'avancement en direct (`/status.progress` = {done, total, phase}) pendant scrape / extraction / ré-analyse / matching.
- La barre en bas des pages Offres et Profil devient une **vraie jauge « X / Y »** (déterminée), avec le libellé de la phase en cours ; repli indéterminé si le total n'est pas connu.

### v0.5.2 (2026-07-21) — barre de progression d'activité
- Barre d'activité en bas des pages Offres et Profil (indéterminée), pilotée par `/status`.

### v0.5.1 (2026-07-21) — profil : PDF ou .md
- Le profil accepte désormais **PDF (→ OCR Mistral)** ou **.md/.txt (→ ingestion directe**, plus léger/fiable). Détection par extension côté backend.

### v0.5.0 (2026-07-21) — bloc compétences fusionné + 2 actions distinctes
- **Deux actions séparées** : « Scanner les nouvelles offres » (drawer → scrape + analyse des nouveautés) et « Ré-analyser toutes les offres » (page Profil → regénère l'analyse IA de toute la collection).
- **Bloc unique « Compétences & technologies »** : logiciels et compétences techniques **fusionnés et regroupés par domaine**, avec une **icône** distinguant logiciel/techno vs compétence (+ légende).
- **Indicateur de niveau discret** : petit compteur 4 segments à droite (au niveau du libellé Maîtrise/Pratique…) au lieu des barres pleine largeur.

### v0.4.1 (2026-07-21) — actualisation complète + date sur la tuile
- « Actualiser toutes les offres » (drawer) = **boucle complète** : re-scrape des recherches surveillées → extraction → matching (endpoint `/run-searches`).
- **Date de publication** affichée sur chaque tuile.
- Rappel : le scraper parcourt jusqu'à 10 pages (~300 offres) ; les tests précédents étaient limités à 1 page.

### v0.4.0 (2026-07-21) — technos par domaine + niveaux, tuiles repensées
- **Technos/logiciels catégorisés par domaine data** (ETL/ELT, CI/CD, Data cleaning…) avec **niveau de maîtrise gradué** (Maîtrise/Pratique/Connaissance/Culture générale) → barre de progression + explication FR sous chaque item.
- **Avantages extraits du texte** (plus seulement la liste structurée) + détails chiffrés dans l'explication. Format encadré (majuscule, phrase).
- **Tuiles repensées** : 2 indicateurs à droite (langue principale — 🇨🇿 encadré rouge si tchèque impératif ; « Junior OK » si ≤ 1 an) + jauge de compatibilité (% + barre rouge→verte). Fin des mini-encadrés peu utiles.
- Typographie allégée (fin du « tout en gras »). `re-traitement complet des offres` possible via `/admin/reprocess-all` (re-fetch du détail des offres vides inclus).
- **Dev confort** : URL backend par défaut dans l'app + `dart_defines.json` (+ `.vscode/launch.json`) → plus besoin de retaper les `--dart-define`.

### v0.3.0 (2026-07-21) — multi-agents (extraction + conseil) & refonte fiche
- **Extraction multi-agents** : `extract → data_expert (ordre par niveau + regroupement logique + explication par item) → benefits (4 catégories) → verify (anti-hallucination) → translate`. Logiciels/compétences/avantages passent en `{nom, explication, niveau}`.
- **Conseil / matching** : profil candidat (upload PDF → OCR Mistral → structuration), puis par offre un **score de confiance** + synthèse + **points bloquants** + **plan d'attaque** (agents match + calibrage). Recalcul uniquement si match absent ou profil changé.
- **Refonte de la fiche** : ordre en-tête → résumé → langues → logiciels → compétences techniques → humaines → avantages ; listes explicatives ; description complète sur page dédiée ; en-tête aligné (Table) ; carte de matching en tête.
- **App** : écran Profil (PDF), tri par pertinence + badge de score sur les tuiles, action « Analyser les offres ».

### v0.2.0 (2026-07-21) — déploiement + agents dédiés + login email
- **Déployé en prod** : API sur Render (`https://jobradar-tlqj.onrender.com`), Firebase `jobradar-3610d` (Firestore + règles), 1er scrape validé (30 offres, 0 erreur).
- **Agents Mistral dédiés** (`JobRadar · Extraction offre`, `JobRadar · Traduction CZ→EN`) créés via l'API et mis en cache Firestore ; repli automatique sur `chat.complete` si la clé n'a pas l'API Agents.
- **Connexion email/mot de passe** (+ création de compte) en plus de Google — utile pour tester sur émulateur.
- Recherches du cron déplacées dans Firestore (`searches`) ; config Firebase retirée du suivi git.

### v0.1.0 (2026-07-20) — fondations
- Backend Flask complet : scraper Jobs.cz (liste HTML + détail GraphQL + fallback
  HTML), agents Mistral (extraction + traduction cz→en), store Firestore, push FCM,
  API `/scrape`, cron quotidien, `render.yaml`. Pipeline validé sur offres live.
- App Flutter : login Google, liste temps réel + filtre/nouveautés, fiche détaillée
  riche (Material Symbols, bascule de langue), lancement de recherche en pop-up.
- Règles Firestore, docs et cette liste de courses.
