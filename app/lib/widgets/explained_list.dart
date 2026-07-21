import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/offer.dart';

/// Liste « item + (barre de niveau) + explication dessous ».
/// Typographie légère : le nom n'est pas en gras, l'explication est secondaire.
class ExplainedList extends StatelessWidget {
  final List<SkillItem> items;
  final IconData bullet;
  const ExplainedList({super.key, required this.items, this.bullet = Symbols.chevron_right});

  static Color levelColor(String? level) => switch (level) {
        'Maîtrise' => Colors.green.shade600,
        'Pratique' => Colors.blue.shade600,
        'Connaissance' => Colors.orange.shade700,
        'Culture générale' => Colors.blueGrey.shade400,
        _ => Colors.blue.shade600,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(it.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500, fontSize: 14.5)),
                          ),
                          if (it.level != null && it.level!.isNotEmpty)
                            Text(it.level!,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: levelColor(it.level))),
                        ],
                      ),
                      if (it.weight != null) ...[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (it.weight!.clamp(0, 100)) / 100,
                            minHeight: 5,
                            backgroundColor: scheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(levelColor(it.level)),
                          ),
                        ),
                      ],
                      if (it.explanation.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
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
