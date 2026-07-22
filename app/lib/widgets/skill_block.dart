import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/offer.dart';

/// Bloc unique « Compétences & technologies » : fusionne logiciels et
/// compétences techniques, regroupés par domaine (mêmes catégories des 2 côtés).
/// Une icône distingue logiciel/techno vs compétence ; le niveau est indiqué
/// par un petit compteur discret à droite.
/// Niveaux de maîtrise sélectionnables pour « ton niveau » (édition depuis l'offre).
const _kUserLevels = <String>['Maîtrise', 'Pratique habituelle', 'Déjà pratiqué', 'Notion'];

class SkillBlock extends StatelessWidget {
  final List<SkillItem> software;
  final List<SkillItem> technical;

  /// Édition « ton niveau » (facultatif) : niveau de l'utilisateur par nom de
  /// compétence (clé en minuscules) + callback de sauvegarde. Si `onSetUserLevel`
  /// est fourni, chaque ligne affiche un sélecteur de niveau personnel.
  final Map<String, String>? userLevels;
  final void Function(SkillItem item, bool isSoftware, String? level)? onSetUserLevel;

  const SkillBlock({
    super.key,
    required this.software,
    required this.technical,
    this.userLevels,
    this.onSetUserLevel,
  });

  static Color _levelColor(String? level) => switch (level) {
        'Maîtrise' => Colors.green.shade600,
        'Pratique habituelle' => Colors.blue.shade600,
        'Déjà pratiqué' => Colors.orange.shade700,
        'Notion' => Colors.blueGrey.shade400,
        _ => Colors.blue.shade600,
      };

  int _rank(SkillItem it) {
    switch (it.level) {
      case 'Maîtrise':
        return 4;
      case 'Pratique habituelle':
        return 3;
      case 'Déjà pratiqué':
        return 2;
      case 'Notion':
        return 1;
    }
    if (it.weight != null) return (it.weight! / 25).ceil().clamp(1, 4);
    return 0;
  }

  int _maxWeight(List<_Entry> l) =>
      l.map((e) => e.item.weight ?? 0).fold(0, (a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = <_Entry>[
      ...software.map((s) => _Entry(s, isSoftware: true)),
      ...technical.map((s) => _Entry(s, isSoftware: false)),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    final byDomain = <String, List<_Entry>>{};
    for (final e in entries) {
      (byDomain[e.item.domain.isEmpty ? 'Autres' : e.item.domain] ??= []).add(e);
    }
    final domains = byDomain.keys.toList()
      ..sort((a, b) => _maxWeight(byDomain[b]!).compareTo(_maxWeight(byDomain[a]!)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Row(children: [
            Icon(Symbols.stacks, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text('Compétences & technologies',
                style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
        _legend(context),
        const SizedBox(height: 8),
        for (final d in domains) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(d.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ),
          for (final e in byDomain[d]!..sort((a, b) => (b.item.weight ?? 0).compareTo(a.item.weight ?? 0)))
            _row(context, e),
        ],
      ],
    );
  }

  Widget _legend(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    TextStyle st = Theme.of(context).textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant);
    return Row(children: [
      Icon(Symbols.terminal, size: 14, color: scheme.primary),
      const SizedBox(width: 4),
      Text('Logiciel / techno', style: st),
      const SizedBox(width: 14),
      Icon(Symbols.build, size: 14, color: Colors.teal.shade600),
      const SizedBox(width: 4),
      Text('Compétence', style: st),
    ]);
  }

  Widget _row(BuildContext context, _Entry e) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Tooltip(
                message: e.isSoftware ? 'Logiciel / techno' : 'Compétence technique',
                child: Icon(e.isSoftware ? Symbols.terminal : Symbols.build,
                    size: 16, color: e.isSoftware ? scheme.primary : Colors.teal.shade600),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(e.item.name,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5)),
              ),
              if (e.item.level != null && e.item.level!.isNotEmpty) ...[
                Text(e.item.level!,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _levelColor(e.item.level))),
                const SizedBox(width: 6),
              ],
              _meter(context, _rank(e.item), _levelColor(e.item.level)),
            ],
          ),
          if (e.item.explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text(e.item.explanation,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant, height: 1.3)),
            ),
          if (onSetUserLevel != null) _userLevelEditor(context, e),
        ],
      ),
    );
  }

  /// Sélecteur « ton niveau » : ajuste (ou ajoute/retire) la compétence dans le profil.
  Widget _userLevelEditor(BuildContext context, _Entry e) {
    final scheme = Theme.of(context).colorScheme;
    final current = userLevels?[e.item.name.toLowerCase().trim()];
    final has = current != null && _kUserLevels.contains(current);
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 3),
      child: Row(
        children: [
          Icon(has ? Symbols.person_check : Symbols.person_add,
              size: 14, color: has ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('Ton niveau :',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(width: 6),
          DropdownButton<String>(
            value: has ? current : null,
            hint: Text('je ne l’ai pas',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            isDense: true,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
            underline: const SizedBox.shrink(),
            items: [
              ..._kUserLevels.map((l) => DropdownMenuItem(value: l, child: Text(l))),
              const DropdownMenuItem(value: '__none__', child: Text('je ne l’ai pas')),
            ],
            onChanged: (v) =>
                onSetUserLevel!(e.item, e.isSoftware, v == '__none__' ? null : v),
          ),
        ],
      ),
    );
  }

  Widget _meter(BuildContext context, int rank, Color color) {
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            margin: const EdgeInsets.only(left: 2),
            width: 4,
            height: 10,
            decoration: BoxDecoration(
              color: i < rank ? color : empty,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }
}

class _Entry {
  final SkillItem item;
  final bool isSoftware;
  _Entry(this.item, {required this.isSoftware});
}
