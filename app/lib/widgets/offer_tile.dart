import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/offer.dart';

/// Tuile d'offre : à gauche titre/entreprise/lieu ; à droite 2 indicateurs
/// (langue, junior) + la jauge de compatibilité.
class OfferTile extends StatelessWidget {
  final Offer offer;
  final VoidCallback onTap;
  const OfferTile({super.key, required this.offer, required this.onTap});

  static Color scoreColor(int s) => s >= 75
      ? Colors.green.shade600
      : s >= 50
          ? Colors.lightGreen.shade700
          : s >= 30
              ? Colors.orange.shade700
              : Colors.red.shade600;

  RequiredLanguage? get _mainLanguage {
    final mand = offer.languages.where((l) => l.mandatory).toList();
    final pool = mand.isNotEmpty ? mand : offer.languages;
    return pool.isEmpty ? null : pool.first;
  }

  bool _isCzech(String l) {
    final s = l.toLowerCase();
    return s.contains('tch') || s.contains('cze') || s.contains('czech') || s.contains('češ') || s == 'cs';
  }

  bool _isEnglish(String l) {
    final s = l.toLowerCase();
    return s.contains('angl') || s.contains('engl') || s == 'en';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = offer.displayTitle;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600, height: 1.2)),
                        ),
                        if (!offer.isRead) _newDot(scheme),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _iconLine(context, Symbols.apartment,
                        offer.intermediary.isNotEmpty
                            ? '${offer.company} · via ${offer.intermediary}'
                            : offer.company),
                    if (offer.locationLabel.isNotEmpty)
                      _iconLine(context, Symbols.location_on, offer.locationLabel),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _rightColumn(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rightColumn(BuildContext context) {
    final lang = _mainLanguage;
    final junior = offer.experienceYears != null && offer.experienceYears! <= 1;
    final senior = offer.experienceYears != null && offer.experienceYears! >= 4;
    final m = offer.match;
    return SizedBox(
      width: 74,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (junior)
                _statusIcon(Symbols.local_florist, Colors.green.shade600, 'Junior OK (≤ 1 an)'),
              if (senior)
                _statusIcon(Symbols.workspace_premium, Colors.orange.shade700,
                    'Expérience élevée demandée'),
              if (lang != null) _langBadge(lang),
            ],
          ),
          if (m != null) ...[
            const SizedBox(height: 10),
            _compat(context, m.score),
          ],
        ],
      ),
    );
  }

  Widget _langBadge(RequiredLanguage lang) {
    final cz = _isCzech(lang.language);
    final en = _isEnglish(lang.language);
    final flag = cz ? '🇨🇿' : (en ? '🇬🇧' : '🌐');
    final barrier = cz && lang.mandatory; // le tchèque impératif = frein pour l'utilisateur
    return Tooltip(
      message:
          '${lang.language}${lang.level != null && lang.level!.isNotEmpty ? ' (${lang.level})' : ''}'
          '${lang.mandatory ? ' — impérative' : ''}',
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.all(2),
        decoration: barrier
            ? BoxDecoration(
                border: Border.all(color: Colors.red.shade400, width: 1.5),
                borderRadius: BorderRadius.circular(6))
            : null,
        child: Text(flag, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget _statusIcon(IconData icon, Color color, String tip) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Tooltip(message: tip, child: Icon(icon, size: 18, color: color)),
      );

  Widget _compat(BuildContext context, int score) {
    final color = scoreColor(score);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$score%',
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: score / 100,
            minHeight: 5,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _newDot(ColorScheme scheme) => Container(
        margin: const EdgeInsets.only(left: 8, top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration:
            BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(20)),
        child: Text('NEW',
            style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5)),
      );

  Widget _iconLine(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
