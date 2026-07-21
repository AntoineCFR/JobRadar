/// Configuration de l'app (endpoint backend + secret partagé).
///
/// Le secret est passé au build via --dart-define pour ne pas le committer :
///   flutter run --dart-define=JOBRADAR_API=https://jobradar-api.onrender.com \
///               --dart-define=JOBRADAR_KEY=xxxxx
class AppConfig {
  /// URL du backend Flask (Render). Réglable via --dart-define.
  static const String apiBaseUrl = String.fromEnvironment(
    'JOBRADAR_API',
    defaultValue: 'http://10.0.2.2:8000', // émulateur Android -> localhost
  );

  /// Secret partagé exigé par POST /scrape (X-JobRadar-Key).
  static const String apiKey = String.fromEnvironment('JOBRADAR_KEY', defaultValue: '');

  /// Sites de recherche proposés dans le portail (V1 : Jobs.cz seul).
  static const List<JobSite> sites = [
    JobSite(id: 'jobs.cz', label: 'Jobs.cz', country: '🇨🇿'),
  ];
}

class JobSite {
  final String id;
  final String label;
  final String country;
  const JobSite({required this.id, required this.label, required this.country});
}
