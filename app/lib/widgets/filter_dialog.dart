import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Critères de filtrage des offres (tous inactifs par défaut).
class OfferFilters {
  int minRelevance;
  int minMatch;
  String workArrangement; // '' = tous | remote | hybrid | on-site
  bool juniorOnly;
  bool hideCzechMandatory;
  bool unreadOnly;

  OfferFilters({
    this.minRelevance = 0,
    this.minMatch = 0,
    this.workArrangement = '',
    this.juniorOnly = false,
    this.hideCzechMandatory = false,
    this.unreadOnly = false,
  });

  OfferFilters copy() => OfferFilters(
        minRelevance: minRelevance,
        minMatch: minMatch,
        workArrangement: workArrangement,
        juniorOnly: juniorOnly,
        hideCzechMandatory: hideCzechMandatory,
        unreadOnly: unreadOnly,
      );

  int get activeCount =>
      (minRelevance > 0 ? 1 : 0) +
      (minMatch > 0 ? 1 : 0) +
      (workArrangement.isNotEmpty ? 1 : 0) +
      (juniorOnly ? 1 : 0) +
      (hideCzechMandatory ? 1 : 0) +
      (unreadOnly ? 1 : 0);
}

class FilterDialog extends StatefulWidget {
  final OfferFilters initial;
  const FilterDialog({super.key, required this.initial});

  static Future<OfferFilters?> show(BuildContext context, OfferFilters current) =>
      showDialog<OfferFilters>(context: context, builder: (_) => FilterDialog(initial: current));

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  late OfferFilters f = widget.initial.copy();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [Icon(Symbols.filter_alt), SizedBox(width: 10), Text('Filtrer')]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _slider('Pertinence min.', f.minRelevance, (v) => setState(() => f.minRelevance = v)),
            _slider('Compatibilité min.', f.minMatch, (v) => setState(() => f.minMatch = v)),
            const SizedBox(height: 8),
            Text('Mode de travail', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final e in const [
                  ['', 'Tous'],
                  ['remote', 'Remote'],
                  ['hybrid', 'Hybride'],
                  ['on-site', 'Sur site'],
                ])
                  ChoiceChip(
                    label: Text(e[1]),
                    selected: f.workArrangement == e[0],
                    onSelected: (_) => setState(() => f.workArrangement = e[0]),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Postes junior seulement (≤ 1 an)'),
              value: f.juniorOnly,
              onChanged: (v) => setState(() => f.juniorOnly = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Masquer si tchèque impératif'),
              value: f.hideCzechMandatory,
              onChanged: (v) => setState(() => f.hideCzechMandatory = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nouveautés seulement'),
              value: f.unreadOnly,
              onChanged: (v) => setState(() => f.unreadOnly = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, OfferFilters()),
          child: const Text('Réinitialiser'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context, f), child: const Text('Appliquer')),
      ],
    );
  }

  Widget _slider(String label, int value, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
          Text(value == 0 ? 'Off' : '$value%'),
        ]),
        Slider(
          value: value.toDouble(),
          max: 100,
          divisions: 20,
          label: '$value%',
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}
