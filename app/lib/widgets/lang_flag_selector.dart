import 'package:flutter/material.dart';

import '../models/offer.dart';

/// Sélecteur de langue de l'offre, à placer dans les `actions` d'une AppBar :
/// - offre tchèque traduite → menu déroulant avec les deux drapeaux 🇨🇿 / 🇬🇧 ;
/// - offre sans traduction → simple drapeau indicatif de la langue d'origine.
class LangFlagSelector extends StatelessWidget {
  final Offer offer;
  final bool english;
  final ValueChanged<bool>? onChanged;
  const LangFlagSelector({
    super.key,
    required this.offer,
    required this.english,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (offer.hasTranslation && onChanged != null) {
      return PopupMenuButton<bool>(
        tooltip: 'Langue de l\'offre',
        icon: Text(english ? '🇬🇧' : '🇨🇿', style: const TextStyle(fontSize: 20)),
        initialValue: english,
        onSelected: onChanged,
        itemBuilder: (_) => const [
          PopupMenuItem(value: false, child: Text('🇨🇿  Original (tchèque)')),
          PopupMenuItem(value: true, child: Text('🇬🇧  Anglais (traduit)')),
        ],
      );
    }
    // Pas de traduction : drapeau indicatif (anglais si l'offre est en anglais).
    final flag = offer.isCzech ? '🇨🇿' : '🇬🇧';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Center(widthFactor: 1, child: Text(flag, style: const TextStyle(fontSize: 20))),
    );
  }
}
