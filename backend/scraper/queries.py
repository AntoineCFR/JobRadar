"""Requêtes GraphQL vers l'API cachée capybara/LMC (jobs.cz).

Voir la doc du mécanisme dans le README. On n'utilise que la requête DETAIL :
la liste des offres est récupérée en HTML classique (voir jobs_cz.py).

La requête ci-dessous est une version épurée de la `DETAIL_QUERY` du bundle
`api.min.js` : elle ne demande que les champs réellement exploités. Les noms de
champs correspondent au schéma réel (vérifié en live le 2026-07-20).
"""

GRAPHQL_ENDPOINT = "https://api.capybara.lmc.cz/api/graphql/widget"

DETAIL_QUERY = """
query DETAIL_QUERY(
  $widgetId: ID!
  $jobAdId: ID!
  $referer: String
  $host: String
  $version: String
  $rps: Int
  $isNotLoggableToSessionLog: Boolean
  $cookieConsent: [String]
) {
  widget(
    id: $widgetId
    referer: $referer
    host: $host
    version: $version
    rps: $rps
    isNotLoggableToSessionLog: $isNotLoggableToSessionLog
    cookieConsent: $cookieConsent
  ) {
    jobAd(id: $jobAdId, rps: $rps, isNotLoggableToSessionLog: $isNotLoggableToSessionLog) {
      id
      title
      headerText
      teaser
      validFrom
      languageIso
      content {
        htmlContent
        sections { title text }
      }
      salary { min max period currency }
      suitableForGraduate
      fieldsObjects { id label }
      professionsObjects { id label }
      locationsObjects {
        country { id label }
        region { id label }
        city { id label }
      }
      parameters {
        hoursPerWeek
        requiredEducation
        allLanguagesRequired
        requiredLanguages { language skill }
        contractTypesObjects { id label }
        employmentTypesObjects { id label }
        employmentDurationsObjects { id label }
        benefitsObjects { id label }
      }
      employer {
        companyName
        contactCompanyName
        phone
        email
      }
    }
  }
}
""".strip()
