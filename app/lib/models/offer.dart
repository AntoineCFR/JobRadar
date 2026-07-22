import 'package:cloud_firestore/cloud_firestore.dart';

/// Un item de compétence/logiciel : nom + domaine + niveau + poids + explication.
class SkillItem {
  final String name;
  final String explanation;
  final String? level; // Maîtrise / Pratique / Connaissance / Culture générale
  final String domain; // sous-domaine data/IT (ETL/ELT, CI/CD, ...)
  final int? weight; // 0-100, remplit la barre de progression

  SkillItem({
    required this.name,
    this.explanation = '',
    this.level,
    this.domain = '',
    this.weight,
  });

  /// Tolérant : accepte une String (ancien format) ou un objet {name,...}.
  static SkillItem from(dynamic v) {
    if (v is String) return SkillItem(name: v);
    if (v is Map) {
      return SkillItem(
        name: (v['name'] ?? '').toString(),
        explanation: (v['explanation'] ?? '').toString(),
        level: v['level']?.toString(),
        domain: (v['domain'] ?? '').toString(),
        weight: v['weight'] is int ? v['weight'] as int : int.tryParse('${v['weight']}'),
      );
    }
    return SkillItem(name: v.toString());
  }

  static List<SkillItem> list(dynamic v) =>
      (v is List) ? v.map(SkillItem.from).where((s) => s.name.isNotEmpty).toList() : <SkillItem>[];
}

/// Avantages classés en 4 catégories.
class BenefitCategories {
  final List<SkillItem> flexibility;
  final List<SkillItem> financial;
  final List<SkillItem> training;
  final List<SkillItem> other;
  BenefitCategories({
    required this.flexibility,
    required this.financial,
    required this.training,
    required this.other,
  });

  bool get isEmpty =>
      flexibility.isEmpty && financial.isEmpty && training.isEmpty && other.isEmpty;

  static BenefitCategories? from(dynamic v) {
    if (v is! Map) return null;
    return BenefitCategories(
      flexibility: SkillItem.list(v['flexibility']),
      financial: SkillItem.list(v['financial']),
      training: SkillItem.list(v['training']),
      other: SkillItem.list(v['other']),
    );
  }
}

class MatchBlocker {
  final String issue;
  final String severity; // haute | moyenne | basse
  MatchBlocker({required this.issue, this.severity = 'moyenne'});

  /// Normalise une sévérité (accepte l'anglais que le LLM produit parfois).
  static String _sev(dynamic v) {
    final s = (v ?? '').toString().toLowerCase().trim();
    const map = {
      'high': 'haute', 'haute': 'haute', 'critical': 'haute', 'severe': 'haute',
      'medium': 'moyenne', 'moderate': 'moyenne', 'moyenne': 'moyenne',
      'low': 'basse', 'basse': 'basse', 'minor': 'basse',
    };
    return map[s] ?? 'moyenne';
  }

  /// Tolérant : le LLM renvoie parfois `{reason,severity}` au lieu de
  /// `{issue,severity}`, ou imbrique l'objet sous `issue`. On récupère le texte
  /// où qu'il soit et on évite d'afficher une Map brute (`{severity: …}`).
  factory MatchBlocker.from(dynamic v) {
    if (v is Map) {
      dynamic raw = v['issue'] ?? v['reason'] ?? v['description'] ?? v['text'] ?? '';
      dynamic sevRaw = v['severity'] ?? v['level'];
      if (raw is Map) {
        sevRaw ??= raw['severity'] ?? raw['level'];
        raw = raw['issue'] ?? raw['reason'] ?? raw['description'] ?? raw['text'] ?? '';
      }
      return MatchBlocker(issue: raw.toString().trim(), severity: _sev(sevRaw));
    }
    return MatchBlocker(issue: v.toString().trim());
  }
}

/// Résultat du matching offre × profil.
class MatchResult {
  final int score;
  final String band; // faible | moyen | bon | excellent
  final String verdict;
  final String synthese;
  final List<MatchBlocker> blockers;
  final List<String> matches;
  final List<String> plan;

  MatchResult({
    required this.score,
    required this.band,
    required this.verdict,
    required this.synthese,
    required this.blockers,
    required this.matches,
    required this.plan,
  });

  static List<String> _s(dynamic v) =>
      (v is List) ? v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList() : <String>[];

  static MatchResult? from(dynamic v) {
    if (v is! Map) return null;
    return MatchResult(
      score: v['score'] is int ? v['score'] as int : int.tryParse('${v['score']}') ?? 0,
      band: (v['band'] ?? 'moyen').toString(),
      verdict: (v['verdict'] ?? '').toString(),
      synthese: (v['synthese'] ?? '').toString(),
      blockers: (v['blockers'] is List)
          ? (v['blockers'] as List)
              .map(MatchBlocker.from)
              .where((b) => b.issue.isNotEmpty) // pas de puce vide (cf. point 4)
              .toList()
          : <MatchBlocker>[],
      matches: _s(v['matches']),
      plan: _s(v['plan']),
    );
  }
}

class RequiredLanguage {
  final String language;
  final String? level;
  final bool mandatory;
  final String reason;
  RequiredLanguage({required this.language, this.level, this.mandatory = false, this.reason = ''});
  factory RequiredLanguage.fromMap(Map<String, dynamic> m) => RequiredLanguage(
        language: (m['language'] ?? '').toString(),
        level: m['level']?.toString(),
        mandatory: m['mandatory'] == true,
        reason: (m['reason'] ?? '').toString(),
      );
}

class Translation {
  final String title;
  final String summary;
  final String descriptionText;
  Translation({required this.title, required this.summary, required this.descriptionText});
  factory Translation.fromMap(Map<String, dynamic> m) => Translation(
        title: (m['title'] ?? '').toString(),
        summary: (m['summary'] ?? '').toString(),
        descriptionText: (m['description_text'] ?? '').toString(),
      );
}

/// Une offre d'emploi enrichie (document Firestore `offers/{id}`).
class Offer {
  final String id;
  final String site;
  final String link;
  final String applyUrl;
  final String title;
  final String company;
  final String intermediary;
  final String? publishedAt;
  final String sourceLanguage;
  final String locationCity;
  final String locationRegion;
  final String locationCountry;
  final String sector;
  final String contractType;
  final String employmentType;
  final String workArrangement;
  final String education;
  final int? experienceYears;
  final List<String> softSkills;
  final List<SkillItem> technicalSkills;
  final List<SkillItem> software;
  final List<RequiredLanguage> languages;
  final Map<String, dynamic>? salary;
  final List<String> benefitsFlat;
  final BenefitCategories? benefits;
  final String summary;
  final String descriptionText;
  final Translation? translated;
  final MatchResult? match;
  final int? relevanceScore; // pertinence de l'offre vs le mot-clé recherché
  final String relevanceReason;
  final bool isRead;
  final bool isFavorite;
  final String status; // active | expired
  final Timestamp? expiredAt;
  final Timestamp? firstSeenAt;

  Offer({
    required this.id,
    required this.site,
    required this.link,
    required this.applyUrl,
    required this.title,
    required this.company,
    required this.intermediary,
    required this.publishedAt,
    required this.sourceLanguage,
    required this.locationCity,
    required this.locationRegion,
    required this.locationCountry,
    required this.sector,
    required this.contractType,
    required this.employmentType,
    required this.workArrangement,
    required this.education,
    required this.experienceYears,
    required this.softSkills,
    required this.technicalSkills,
    required this.software,
    required this.languages,
    required this.salary,
    required this.benefitsFlat,
    required this.benefits,
    required this.summary,
    required this.descriptionText,
    required this.translated,
    required this.match,
    required this.relevanceScore,
    required this.relevanceReason,
    required this.isRead,
    required this.isFavorite,
    required this.status,
    required this.expiredAt,
    required this.firstSeenAt,
  });

  bool get isExpired => status == 'expired';

  bool get hasTranslation => translated != null;
  bool get isCzech => sourceLanguage == 'cs';
  String get displayTitle => hasTranslation ? translated!.title : title;

  /// L'offre exige-t-elle une langue tchèque impérative (critère bloquant) ?
  bool get requiresMandatoryCzech => languages.any((l) {
        final s = l.language.toLowerCase();
        final cz = s.contains('tch') || s.contains('cze') || s.contains('czech') || s.contains('češ') || s == 'cs';
        return l.mandatory && cz;
      });

  bool get isJunior => experienceYears != null && experienceYears! <= 1;

  DateTime? get publishedDate =>
      (publishedAt != null && publishedAt!.isNotEmpty) ? DateTime.tryParse(publishedAt!) : null;

  /// Date de détection par nous (fallback quand la publication est inconnue).
  DateTime? get seenDate => firstSeenAt?.toDate();

  /// Date effective pour le tri (publication si connue, sinon détection).
  DateTime? get effectiveDate => publishedDate ?? seenDate;

  String get locationLabel {
    final parts = <String>[];
    if (locationCity.isNotEmpty) parts.add(locationCity);
    if (locationRegion.isNotEmpty && locationRegion != locationCity) parts.add(locationRegion);
    return parts.join(' · ');
  }

  String? get salaryLabel => salary?['raw']?.toString();

  static List<String> _strList(dynamic v) =>
      (v is List) ? v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList() : <String>[];

  factory Offer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Offer(
      id: doc.id,
      site: (d['site'] ?? 'jobs.cz').toString(),
      link: (d['link'] ?? '').toString(),
      applyUrl: (d['apply_url'] ?? d['link'] ?? '').toString(),
      title: (d['title'] ?? '').toString(),
      company: (d['company'] ?? '').toString(),
      intermediary: (d['intermediary'] ?? '').toString(),
      publishedAt: d['published_at']?.toString(),
      sourceLanguage: (d['source_language'] ?? 'en').toString(),
      locationCity: (d['location_city'] ?? '').toString(),
      locationRegion: (d['location_region'] ?? '').toString(),
      locationCountry: (d['location_country'] ?? '').toString(),
      sector: (d['sector'] ?? '').toString(),
      contractType: (d['contract_type'] ?? '').toString(),
      employmentType: (d['employment_type'] ?? '').toString(),
      workArrangement: (d['work_arrangement'] ?? '').toString(),
      education: (d['education'] ?? '').toString(),
      experienceYears: d['experience_years'] is int ? d['experience_years'] as int : null,
      softSkills: _strList(d['soft_skills']),
      technicalSkills: SkillItem.list(d['technical_skills']),
      software: SkillItem.list(d['software']),
      languages: (d['languages'] is List)
          ? (d['languages'] as List)
              .whereType<Map>()
              .map((m) => RequiredLanguage.fromMap(Map<String, dynamic>.from(m)))
              .toList()
          : <RequiredLanguage>[],
      salary: d['salary'] is Map ? Map<String, dynamic>.from(d['salary']) : null,
      benefitsFlat: _strList(d['benefits']),
      benefits: BenefitCategories.from(d['benefits_categorized']),
      summary: (d['summary'] ?? '').toString(),
      descriptionText: (d['description_text'] ?? '').toString(),
      translated: d['translated'] is Map
          ? Translation.fromMap(Map<String, dynamic>.from(d['translated']))
          : null,
      match: MatchResult.from(d['match']),
      relevanceScore: (d['relevance'] is Map && d['relevance']['score'] is int)
          ? d['relevance']['score'] as int
          : null,
      relevanceReason:
          (d['relevance'] is Map) ? (d['relevance']['reason'] ?? '').toString() : '',
      isRead: d['is_read'] == true,
      isFavorite: d['is_favorite'] == true,
      status: (d['status'] ?? 'active').toString(),
      expiredAt: d['expired_at'] is Timestamp ? d['expired_at'] as Timestamp : null,
      firstSeenAt: d['first_seen_at'] is Timestamp ? d['first_seen_at'] as Timestamp : null,
    );
  }
}
