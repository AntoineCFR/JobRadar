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

  Future<void> markRead(String id, bool read) =>
      _col.doc(id).set({'is_read': read}, SetOptions(merge: true));

  /// Marque toutes les offres non lues comme lues (action « tout marquer lu »).
  Future<void> markAllRead(List<Offer> offers) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final o in offers.where((o) => !o.isRead)) {
      batch.set(_col.doc(o.id), {'is_read': true}, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
