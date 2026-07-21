import 'package:cloud_firestore/cloud_firestore.dart';

/// Une langue requise par l'offre, avec niveau et caractère impératif.
class RequiredLanguage {
  final String language;
  final String? level;
  final bool mandatory;
  final String reason;

  RequiredLanguage({
    required this.language,
    this.level,
    this.mandatory = false,
    this.reason = '',
  });

  factory RequiredLanguage.fromMap(Map<String, dynamic> m) => RequiredLanguage(
        language: (m['language'] ?? '').toString(),
        level: m['level']?.toString(),
        mandatory: m['mandatory'] == true,
        reason: (m['reason'] ?? '').toString(),
      );
}

/// Bloc de traduction anglaise (présent si l'offre d'origine est en tchèque).
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
  final String sourceLanguage; // 'cs' | 'en'
  final String locationCity;
  final String locationRegion;
  final String locationCountry;
  final String sector;
  final String contractType;
  final String employmentType;
  final String workArrangement; // on-site | hybrid | remote
  final String education;
  final int? experienceYears;
  final List<String> softSkills;
  final List<String> technicalSkills;
  final List<String> software;
  final List<RequiredLanguage> languages;
  final Map<String, dynamic>? salary;
  final List<String> benefits;
  final String summary;
  final String descriptionText;
  final Translation? translated;
  final bool isRead;
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
    required this.benefits,
    required this.summary,
    required this.descriptionText,
    required this.translated,
    required this.isRead,
    required this.firstSeenAt,
  });

  bool get hasTranslation => translated != null;
  bool get isCzech => sourceLanguage == 'cs';

  /// Localisation lisible (ville + région si distincte).
  String get locationLabel {
    final parts = <String>[];
    if (locationCity.isNotEmpty) parts.add(locationCity);
    if (locationRegion.isNotEmpty && locationRegion != locationCity) {
      parts.add(locationRegion);
    }
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
      technicalSkills: _strList(d['technical_skills']),
      software: _strList(d['software']),
      languages: (d['languages'] is List)
          ? (d['languages'] as List)
              .whereType<Map>()
              .map((m) => RequiredLanguage.fromMap(Map<String, dynamic>.from(m)))
              .toList()
          : <RequiredLanguage>[],
      salary: d['salary'] is Map ? Map<String, dynamic>.from(d['salary']) : null,
      benefits: _strList(d['benefits']),
      summary: (d['summary'] ?? '').toString(),
      descriptionText: (d['description_text'] ?? '').toString(),
      translated: d['translated'] is Map
          ? Translation.fromMap(Map<String, dynamic>.from(d['translated']))
          : null,
      isRead: d['is_read'] == true,
      firstSeenAt: d['first_seen_at'] is Timestamp ? d['first_seen_at'] as Timestamp : null,
    );
  }
}
