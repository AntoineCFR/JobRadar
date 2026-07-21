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
