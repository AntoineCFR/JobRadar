import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/offer.dart';

/// Tuile d'offre : à gauche titre/entreprise/lieu/date ; à droite les
/// indicateurs (langue, junior) + les jauges Pertinence et Match.
class OfferTile extends StatelessWidget {
  final Offer offer;
  final VoidCallback onTap;
  final ValueChanged<bool>? onToggleFavorite;
  const OfferTile({super.key, required this.offer, required this.onTap, this.onToggleFavorite});

  static Color scoreColor(int s) => s >= 75
      ? Colors.green.shade600
      : s >= 50
          ? Colors.lightGreen.shade700
          : s >= 30
              ? Colors.orange.shade700
              : Colors.red.shade600;

  bool _isCzech(String l) {
    final s = l.toLowerCase();
    return s.contains('tch') || s.contains('cze') || s.contains('czech') || s.contains('češ') || s == 'cs';
  }

  bool _isEnglish(String l) {
    final s = l.toLowerCase();
    return s.contains('angl') || s.contains('engl') || s == 'en';
  }

  /// Le tchèque impératif est un critère bloquant : il prime sur les autres langues.
  RequiredLanguage? get _czechBarrier {
    for (final l in offer.languages) {
      if (l.mandatory && _isCzech(l.language)) return l;
    }
    return null;
  }

  RequiredLanguage? get _displayLanguage {
    if (_czechBarrier != null) return _czechBarrier;
    final mand = offer.languages.where((l) => l.mandatory).toList();
    final pool = mand.isNotEmpty ? mand : offer.languages;
    return pool.isEmpty ? null : pool.first;
  }

  String? get _publishedLabel {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final pub = offer.publishedDate;
    if (pub != null) return 'Publiée le ${fmt(pub)}';
    final seen = offer.seenDate;
    if (seen != null) return 'Vue le ${fmt(seen)}'; // date de publication non exposée par jobs.cz
    return null;
  }

  /// Info-bulle noire discrète, déclenchée au clic (mobile-friendly).
  Widget _tip(String msg, Widget child) => Tooltip(
        message: msg,
        triggerMode: TooltipTriggerMode.tap,
        preferBelow: false,
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                          child: Text(offer.displayTitle,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600, height: 1.2)),
                        ),
                        if (offer.isExpired)
                          _pill(scheme, 'EXPIRÉE', scheme.errorContainer, scheme.onErrorContainer)
                        else if (!offer.isRead)
                          _newDot(scheme),
                        _favStar(scheme),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _iconLine(context, Symbols.apartment,
                        offer.intermediary.isNotEmpty
                            ? '${offer.company} · via ${offer.intermediary}'
                            : offer.company),
                    if (offer.locationLabel.isNotEmpty)
                      _iconLine(context, Symbols.location_on, offer.locationLabel),
                    if (_publishedLabel != null)
                      _iconLine(context, Symbols.event, _publishedLabel!),
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
    final lang = _displayLanguage;
    final junior = offer.experienceYears != null && offer.experienceYears! <= 1;
    final senior = offer.experienceYears != null && offer.experienceYears! >= 4;
    return SizedBox(
      width: 84,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (junior)
                _tip('Poste junior : ≤ 1 an d\'expérience demandé',
                    Icon(Symbols.local_florist, size: 18, color: Colors.green.shade600)),
              if (senior)
                _tip('Expérience élevée demandée (≥ 4 ans)',
                    Icon(Symbols.workspace_premium, size: 18, color: Colors.orange.shade700)),
              if (lang != null) ...[const SizedBox(width: 4), _langBadge(lang)],
            ],
          ),
          if (offer.relevanceScore != null) ...[
            const SizedBox(height: 9),
            _gauge(context, 'Pertinence', offer.relevanceScore!,
                tip: offer.relevanceReason.isNotEmpty
                    ? 'Pertinence vs ta recherche : ${offer.relevanceReason}'
                    : 'Pertinence de l\'offre par rapport au mot-clé recherché'),
          ],
          if (offer.match != null) ...[
            const SizedBox(height: 9),
            _gauge(context, 'Match', offer.match!.score,
                tip: 'Compatibilité avec ton profil'),
          ],
        ],
      ),
    );
  }

  Widget _langBadge(RequiredLanguage lang) {
    final cz = _isCzech(lang.language);
    final en = _isEnglish(lang.language);
    final flag = cz ? '🇨🇿' : (en ? '🇬🇧' : '🌐');
    final barrier = cz && lang.mandatory;
    return _tip(
      '${lang.language}${lang.level != null && lang.level!.isNotEmpty ? ' (${lang.level})' : ''}'
      '${lang.mandatory ? ' — impérative' : ''}'
      '${barrier ? '\nCritère potentiellement bloquant pour toi.' : ''}',
      Container(
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

  Widget _gauge(BuildContext context, String label, int score, {String? tip}) {
    final color = scoreColor(score);
    final bar = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          Text('$score%', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
        ]),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: 84,
            child: LinearProgressIndicator(
              value: (score.clamp(0, 100)) / 100,
              minHeight: 5,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
    return tip != null ? _tip(tip, bar) : bar;
  }

  /// Étoile de favori : jaune si l'offre est marquée, contour sinon.
  Widget _favStar(ColorScheme scheme) => InkResponse(
        onTap: onToggleFavorite == null ? null : () => onToggleFavorite!(!offer.isFavorite),
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.only(left: 6, top: 1),
          child: Icon(
            offer.isFavorite ? Symbols.star : Symbols.star,
            fill: offer.isFavorite ? 1 : 0,
            size: 22,
            color: offer.isFavorite ? Colors.amber.shade600 : scheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _newDot(ColorScheme scheme) =>
      _pill(scheme, 'NEW', scheme.primary, scheme.onPrimary);

  Widget _pill(ColorScheme scheme, String label, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(left: 8, top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: fg, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
