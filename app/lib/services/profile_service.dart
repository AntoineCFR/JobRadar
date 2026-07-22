import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/profile.dart';

class ProfileService {
  final _col = FirebaseFirestore.instance.collection('profiles');

  /// Flux du profil de l'utilisateur (null tant qu'aucun profil analysé).
  Stream<Profile?> watch(String uid) =>
      _col.doc(uid).snapshots().map((s) => s.exists ? Profile.fromDoc(s) : null);

  /// Met à jour UNE section du profil structuré à la volée (édition manuelle).
  /// Merge Firestore : n'écrase que `structured.<key>`, garde le reste.
  Future<void> updateSection(String uid, String key, dynamic value) =>
      _col.doc(uid).set({
        'structured': {key: value},
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  static const _skillWeights = <String, int>{
    'Maîtrise': 90,
    'Pratique habituelle': 70,
    'Déjà pratiqué': 45,
    'Notion': 20,
  };

  /// Ajoute / ajuste / retire une compétence (appariée par NOM, insensible à la
  /// casse) dans une section de compétences du profil. [level] == null -> retire.
  /// Utilisé pour éditer son niveau directement depuis une offre.
  Future<void> setSkill({
    required String uid,
    required String sectionKey, // 'hard_skills' | 'software'
    required List<dynamic> current,
    required String name,
    String domain = '',
    String? level,
  }) async {
    final list = List<dynamic>.from(current);
    final key = name.toLowerCase().trim();
    final idx = list.indexWhere((e) =>
        e is Map && (e['name'] ?? '').toString().toLowerCase().trim() == key);
    if (level == null) {
      if (idx >= 0) list.removeAt(idx);
    } else if (idx >= 0) {
      final m = Map<String, dynamic>.from(list[idx] as Map);
      m['level'] = level;
      m['weight'] = _skillWeights[level];
      list[idx] = m;
    } else {
      list.add({
        'name': name,
        'domain': domain,
        'level': level,
        'weight': _skillWeights[level],
        'explanation': '',
      });
    }
    await updateSection(uid, sectionKey, list);
  }

  /// Envoie le PDF au backend pour OCR + structuration + re-matching.
  Future<String?> analyze({
    required String uid,
    required List<int> pdfBytes,
    required String filename,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/profile/analyze');
    final req = http.MultipartRequest('POST', uri)
      ..fields['uid'] = uid
      ..files.add(http.MultipartFile.fromBytes('file', pdfBytes, filename: filename));
    if (AppConfig.apiKey.isNotEmpty) req.headers['X-JobRadar-Key'] = AppConfig.apiKey;
    try {
      final streamed = await req.send().timeout(const Duration(seconds: 120));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode == 200) return null; // succès
      final msg = (jsonDecode(body) as Map)['error']?.toString();
      return msg ?? 'Erreur serveur (${streamed.statusCode}).';
    } catch (e) {
      return 'Impossible de joindre le serveur.';
    }
  }
}
