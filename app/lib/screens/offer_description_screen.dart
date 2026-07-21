import 'package:flutter/material.dart';

import '../models/offer.dart';
import '../widgets/app_scaffold.dart';

/// Page dédiée à la description complète de l'offre (accessible depuis la fiche).
class OfferDescriptionScreen extends StatelessWidget {
  final Offer offer;
  final bool english;
  const OfferDescriptionScreen({super.key, required this.offer, required this.english});

  @override
  Widget build(BuildContext context) {
    final text = (english && offer.hasTranslation)
        ? offer.translated!.descriptionText
        : offer.descriptionText;
    return AppScaffold(
      title: "Offre complète",
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(offer.displayTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(offer.company, style: Theme.of(context).textTheme.bodyMedium),
          const Divider(height: 24),
          SelectableText(
            text.isEmpty ? 'Description indisponible.' : text,
            style: const TextStyle(height: 1.45),
          ),
        ],
      ),
    );
  }
}
