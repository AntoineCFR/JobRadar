import 'package:cloud_firestore/cloud_firestore.dart';

/// Profil candidat structuré par l'agent (document Firestore `profiles/{uid}`).
class Profile {
  final String filename;
  final String version;
  final String source; // 'ocr' (PDF) | 'text' (.md/.txt)
  final Map<String, dynamic> structured;
  final Timestamp? updatedAt;

  Profile({
    required this.filename,
    required this.version,
    required this.source,
    required this.structured,
    required this.updatedAt,
  });

  bool get isText => source == 'text';

  String get headline => (structured['headline'] ?? '').toString();
  String get summary => (structured['summary'] ?? '').toString();

  List<String> _s(String key) {
    final v = structured[key];
    return (v is List) ? v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList() : <String>[];
  }

  List<String> get strengths => _s('strengths');
  List<String> get gaps => _s('gaps');
  List<String> get hardSkills => _s('hard_skills');
  List<String> get software => _s('software');

  List<String> get languages {
    final v = structured['languages'];
    if (v is! List) return [];
    return v.map((e) {
      if (e is Map) {
        final lvl = e['level'];
        return '${e['language']}${lvl != null && '$lvl'.isNotEmpty ? ' ($lvl)' : ''}';
      }
      return e.toString();
    }).toList();
  }

  factory Profile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Profile(
      filename: (d['filename'] ?? '').toString(),
      version: (d['version'] ?? '').toString(),
      source: (d['source'] ?? '').toString(),
      structured: d['structured'] is Map ? Map<String, dynamic>.from(d['structured']) : {},
      updatedAt: d['updated_at'] is Timestamp ? d['updated_at'] as Timestamp : null,
    );
  }
}
