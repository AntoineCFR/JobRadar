import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/offer.dart';

/// Tuile d'offre dans la liste. Affiche titre, entreprise, lieu, quelques
/// méta-données et un badge « NOUVEAU » si l'offre n'a pas encore été lue.
class OfferTile extends StatelessWidget {
  final Offer offer;
  final VoidCallback onTap;
  final VoidCallback? onToggleRead;

  const OfferTile({super.key, required this.offer, required this.onTap, this.onToggleRead});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = offer.hasTranslation ? offer.translated!.title : offer.title;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (offer.match != null) ...[
                    _scoreBadge(context, offer.match!.score),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600, height: 1.2)),
                  ),
                  if (!offer.isRead)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('NOUVEAU',
                          style: TextStyle(
                              color: scheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              _iconLine(context, Symbols.apartment,
                  offer.intermediary.isNotEmpty
                      ? '${offer.company} · via ${offer.intermediary}'
                      : offer.company),
              if (offer.locationLabel.isNotEmpty)
                _iconLine(context, Symbols.location_on, offer.locationLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (offer.salaryLabel != null)
                    _miniChip(context, Symbols.payments, offer.salaryLabel!),
                  if (offer.workArrangement.isNotEmpty)
                    _miniChip(context, Symbols.home_work, offer.workArrangement),
                  if (offer.experienceYears != null)
                    _miniChip(context, Symbols.trending_up, '${offer.experienceYears}+ ans'),
                  if (offer.isCzech) _miniChip(context, Symbols.translate, 'CZ→EN'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreBadge(BuildContext context, int score) {
    final color = score >= 75
        ? Colors.green.shade600
        : score >= 50
            ? Colors.lightGreen.shade700
            : score >= 30
                ? Colors.orange.shade700
                : Colors.red.shade600;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text('$score',
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
    );
  }

  Widget _iconLine(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(BuildContext context, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }
}
