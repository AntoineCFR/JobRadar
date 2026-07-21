import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/offer.dart';

/// Liste à puces sobre : « nom + explication dessous ». Typographie légère.
/// Utilisée pour les avantages (les compétences/technos ont leur propre bloc).
class ExplainedList extends StatelessWidget {
  final List<SkillItem> items;
  final IconData bullet;
  const ExplainedList({super.key, required this.items, this.bullet = Symbols.chevron_right});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Icon(bullet, size: 17, color: scheme.onSurfaceVariant),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.name,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5)),
                      if (it.explanation.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(it.explanation,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant, height: 1.3)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
