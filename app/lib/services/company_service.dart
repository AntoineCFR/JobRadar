import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Localisation d'une entreprise (déduite par agent, stockée dans `companies`).
class CompanyLocation {
  final String? city;
  final String? region;
  final String? country;
  final String? address;
  final String? mapsQuery;
  final String? confidence;
  // Géocodage réel (OpenStreetMap) : adresse résolue + coordonnées.
  final double? lat;
  final double? lon;
  final String? displayName;

  CompanyLocation({
    this.city,
    this.region,
    this.country,
    this.address,
    this.mapsQuery,
    this.confidence,
    this.lat,
    this.lon,
    this.displayName,
  });

  bool get isGeocoded => lat != null && lon != null;

  /// Libellé lisible : adresse OSM résolue si dispo, sinon adresse agent, sinon
  /// ville/région/pays.
  String get label {
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    final parts = <String>[
      if (address != null && address!.isNotEmpty) address!,
      if (city != null && city!.isNotEmpty) city!,
      if (region != null && region!.isNotEmpty && region != city) region!,
      if (country != null && country!.isNotEmpty) country!,
    ];
    return parts.join(' · ');
  }

  /// Requête Maps : coordonnées précises si géocodé, sinon la requête textuelle.
  String get query {
    if (isGeocoded) return '$lat,$lon';
    if (mapsQuery != null && mapsQuery!.isNotEmpty) return mapsQuery!;
    return [city, country].where((e) => e != null && e.isNotEmpty).join(', ');
  }

  static CompanyLocation? from(dynamic v) {
    if (v is! Map) return null;
    final geo = v['geo'];
    double? lat, lon;
    String? displayName;
    if (geo is Map) {
      lat = (geo['lat'] as num?)?.toDouble();
      lon = (geo['lon'] as num?)?.toDouble();
      displayName = geo['display_name']?.toString();
    }
    return CompanyLocation(
      city: v['city']?.toString(),
      region: v['region']?.toString(),
      country: v['country']?.toString(),
      address: v['address']?.toString(),
      mapsQuery: v['maps_query']?.toString(),
      confidence: v['confidence']?.toString(),
      lat: lat,
      lon: lon,
      displayName: displayName,
    );
  }
}

class Company {
  final String name;
  final CompanyLocation? location;
  Company({required this.name, this.location});

  factory Company.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Company(
      name: (d['name'] ?? '').toString(),
      location: CompanyLocation.from(d['location']),
    );
  }
}

/// Lecture des fiches entreprises + déclenchement de la localisation (backend).
class CompanyService {
  final _col = FirebaseFirestore.instance.collection('companies');

  /// Clé de doc IDENTIQUE à celle du backend (`companies.company_key`).
  static String keyFor(String name) => name
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase()
      .replaceAll('/', '-');

  Stream<Company?> watch(String name) =>
      _col.doc(keyFor(name)).snapshots().map((s) => s.exists ? Company.fromDoc(s) : null);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (AppConfig.apiKey.isNotEmpty) 'X-JobRadar-Key': AppConfig.apiKey,
      };

  /// Lance la localisation de toutes les entreprises sans fiche (tâche de fond).
  Future<bool> locateAll() async {
    try {
      final resp = await http
          .post(Uri.parse('${AppConfig.apiBaseUrl}/companies/locate'),
              headers: _headers, body: jsonEncode({'only_missing': true}))
          .timeout(const Duration(seconds: 20));
      return resp.statusCode == 202;
    } catch (_) {
      return false;
    }
  }

  /// Localise UNE entreprise (synchrone côté backend). null = OK, sinon message.
  Future<String?> locateOne(String name) async {
    try {
      final resp = await http
          .post(Uri.parse('${AppConfig.apiBaseUrl}/companies/locate-one'),
              headers: _headers, body: jsonEncode({'company': name}))
          .timeout(const Duration(seconds: 90));
      if (resp.statusCode == 200) return null;
      final msg = (jsonDecode(resp.body) as Map)['error']?.toString();
      return msg ?? 'Localisation impossible (${resp.statusCode}).';
    } catch (_) {
      return 'Serveur injoignable.';
    }
  }
}
