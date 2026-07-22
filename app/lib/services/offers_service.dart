import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/offer.dart';

/// Lecture temps réel des offres depuis Firestore + petites mutations locales
/// (marquer lu/non lu). L'écriture des offres elle-même est faite par le backend.
class OffersService {
  final _col = FirebaseFirestore.instance.collection('offers');

  /// Flux des offres, triées par date de première détection (récentes d'abord).
  Stream<List<Offer>> watchOffers() {
    return _col
        .orderBy('first_seen_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Offer.fromDoc(d as DocumentSnapshot<Map<String, dynamic>>))
            .toList());
  }

  /// Flux d'une offre précise (pour refléter en direct un re-match).
  Stream<Offer?> watchOffer(String id) =>
      _col.doc(id).snapshots().map((d) => d.exists ? Offer.fromDoc(d) : null);

  Future<void> markRead(String id, bool read) =>
      _col.doc(id).set({'is_read': read}, SetOptions(merge: true));

  /// Ajoute/retire l'offre des favoris (étoile).
  /// Renvoie null si OK, sinon un message d'erreur. On ATTRAPE l'erreur : une
  /// écriture refusée (règles Firestore non déployées) ou hors-ligne ne doit
  /// JAMAIS lever d'exception non gérée (sinon flood → gel du thread UI).
  Future<String?> toggleFavorite(String id, bool favorite) async {
    try {
      await _col.doc(id).set({'is_favorite': favorite}, SetOptions(merge: true));
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Favoris non activés côté serveur (règles Firestore à déployer).';
      }
      return 'Impossible d\'enregistrer le favori (${e.code}).';
    } catch (_) {
      return 'Impossible d\'enregistrer le favori.';
    }
  }

  /// Marque toutes les offres non lues comme lues (action « tout marquer lu »).
  Future<void> markAllRead(List<Offer> offers) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final o in offers.where((o) => !o.isRead)) {
      batch.set(_col.doc(o.id), {'is_read': true}, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
