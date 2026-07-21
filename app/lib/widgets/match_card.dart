import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/offer.dart';

/// Carte de conseil : note de confiance + synthèse + blockers + plan d'attaque.
class MatchCard extends StatelessWidget {
  final MatchResult match;
  const MatchCard({super.key, required this.match});

  Color _scoreColor(BuildContext c) {
    final s = match.score;
    if (s >= 75) return Colors.green.shade600;
    if (s >= 50) return Colors.lightGreen.shade700;
    if (s >= 30) return Colors.orange.shade700;
    return Colors.red.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _scoreColor(context);
    return Card(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Gauge(score: match.score, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Symbols.target, size: 18, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text('Ta correspondance',
                            style: Theme.of(context).textTheme.titleSmall),
                      ]),
                      const SizedBox(height: 2),
                      Text(match.band.toUpperCase(),
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      if (match.verdict.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(match.verdict,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (match.synthese.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(match.synthese, style: const TextStyle(height: 1.35)),
            ],
            if (match.blockers.isNotEmpty) ...[
              const SizedBox(height: 12),
              _section(context, Symbols.warning, 'Points bloquants', scheme.error),
              for (final b in match.blockers) _blocker(context, b),
            ],
            if (match.matches.isNotEmpty) ...[
              const SizedBox(height: 12),
              _section(context, Symbols.check_circle, 'Ce qui joue pour toi', Colors.green.shade600),
              for (final m in match.matches) _bullet(context, m, Symbols.check, Colors.green.shade600),
            ],
            if (match.plan.isNotEmpty) ...[
              const SizedBox(height: 12),
              _section(context, Symbols.strategy, "Plan d'attaque", scheme.primary),
              for (final p in match.plan) _bullet(context, p, Symbols.arrow_right, scheme.primary),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, IconData icon, String title, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(title, style: Theme.of(context).textTheme.labelLarge),
        ]),
      );

  Widget _bullet(BuildContext context, String text, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 5, left: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Icon(icon, size: 15, color: color)),
          Expanded(child: Text(text, style: const TextStyle(height: 1.3))),
        ]),
      );

  Widget _blocker(BuildContext context, MatchBlocker b) {
    final sevColor = switch (b.severity) {
      'haute' => Colors.red.shade600,
      'basse' => Colors.orange.shade400,
      _ => Colors.orange.shade700,
    };
    return _bullet(context, b.issue, Symbols.priority_high, sevColor);
  }
}

class _Gauge extends StatelessWidget {
  final int score;
  final Color color;
  const _Gauge({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 6,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text('$score', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
