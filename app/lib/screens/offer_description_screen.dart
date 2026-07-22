import 'package:flutter/material.dart';

import '../models/offer.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/lang_flag_selector.dart';

/// Page dédiée à la description complète de l'offre (accessible depuis la fiche).
/// Dispose de son propre sélecteur de langue (drapeaux) quand une traduction existe.
class OfferDescriptionScreen extends StatefulWidget {
  final Offer offer;
  final bool english;
  const OfferDescriptionScreen({super.key, required this.offer, required this.english});

  @override
  State<OfferDescriptionScreen> createState() => _OfferDescriptionScreenState();
}

class _OfferDescriptionScreenState extends State<OfferDescriptionScreen> {
  late bool _english = widget.english;
  Offer get offer => widget.offer;

  @override
  Widget build(BuildContext context) {
    final text = (_english && offer.hasTranslation)
        ? offer.translated!.descriptionText
        : offer.descriptionText;
    return AppScaffold(
      title: "Offre complète",
      actions: [
        LangFlagSelector(
          offer: offer,
          english: _english,
          onChanged: (v) => setState(() => _english = v),
        ),
      ],
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
