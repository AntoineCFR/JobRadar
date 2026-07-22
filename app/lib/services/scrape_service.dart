import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ScrapeResult {
  final bool started;
  final String message;
  ScrapeResult(this.started, this.message);
}

/// Déclenche un scraping côté backend (Render). Le backend écrit ensuite dans
/// Firestore, que l'app observe en direct — pas besoin d'attendre la réponse.
class ScrapeService {
  Future<ScrapeResult> launch({
    required String site,
    required String keyword,
    required String location,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/scrape');
    try {
      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (AppConfig.apiKey.isNotEmpty) 'X-JobRadar-Key': AppConfig.apiKey,
            },
            body: jsonEncode({'site': site, 'keyword': keyword, 'location': location}),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 202) {
        return ScrapeResult(true, 'Recherche lancée. Les nouvelles offres arrivent…');
      }
      if (resp.statusCode == 409) {
        return ScrapeResult(false, 'Un scraping est déjà en cours.');
      }
      if (resp.statusCode == 401) {
        return ScrapeResult(false, 'Accès refusé (clé API).');
      }
      return ScrapeResult(false, 'Erreur serveur (${resp.statusCode}).');
    } catch (e) {
      return ScrapeResult(false, 'Impossible de joindre le serveur.');
    }
  }

  Future<bool> _post(String path) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}$path'),
        headers: {
          'Content-Type': 'application/json',
          if (AppConfig.apiKey.isNotEmpty) 'X-JobRadar-Key': AppConfig.apiKey,
        },
        body: '{}',
      ).timeout(const Duration(seconds: 20));
      return resp.statusCode == 202;
    } catch (_) {
      return false;
    }
  }

  /// Scanne les nouvelles offres : re-scrape les recherches surveillées, seules
  /// les offres inconnues sont analysées (+ matching).
  Future<bool> scanNewOffers() => _post('/run-searches');

  /// Ré-analyse TOUTE la collection : regénère l'analyse IA de chaque offre.
  Future<bool> reanalyzeAll() => _post('/admin/reprocess-all');

  /// Déclenche le (re)matching des offres côté backend.
  /// `force: true` recalcule TOUTES les offres (nécessaire après une édition
  /// manuelle du profil, qui ne change pas la version du document).
  Future<bool> triggerMatch({bool force = false}) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/match'),
        headers: {
          'Content-Type': 'application/json',
          if (AppConfig.apiKey.isNotEmpty) 'X-JobRadar-Key': AppConfig.apiKey,
        },
        body: jsonEncode({'force': force}),
      ).timeout(const Duration(seconds: 20));
      return resp.statusCode == 202;
    } catch (_) {
      return false;
    }
  }

  /// (Re)matche UNE seule offre côté backend (synchrone). Renvoie true si OK.
  /// Timeout long : le matching d'une offre enchaîne 2 appels IA.
  Future<bool> matchOne(String offerId) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/match-one'),
        headers: {
          'Content-Type': 'application/json',
          if (AppConfig.apiKey.isNotEmpty) 'X-JobRadar-Key': AppConfig.apiKey,
        },
        body: jsonEncode({'id': offerId}),
      ).timeout(const Duration(seconds: 90));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> status() async {
    try {
      final resp = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/status'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }
}
