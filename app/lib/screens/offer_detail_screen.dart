import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/offer.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/explained_list.dart';
import '../widgets/match_card.dart';
import '../widgets/skill_block.dart';
import 'offer_description_screen.dart';

/// Fiche offre : en-tête → (matching) → résumé → langues → logiciels →
/// compétences techniques → humaines → avantages. Bascule 🇨🇿/🇬🇧.
class OfferDetailScreen extends StatefulWidget {
  final Offer offer;
  const OfferDetailScreen({super.key, required this.offer});

  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  late bool _showEnglish = widget.offer.isCzech;
  Offer get o => widget.offer;

  String get _summary => (_showEnglish && o.hasTranslation) ? o.translated!.summary : o.summary;

  Future<void> _apply() async {
    final uri = Uri.tryParse(o.applyUrl);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final benefits = o.benefits;
    return AppScaffold(
      title: 'Fiche offre',
      actions: [
        if (o.hasTranslation)
          PopupMenuButton<bool>(
            tooltip: 'Langue',
            icon: Text(_showEnglish ? '🇬🇧' : '🇨🇿', style: const TextStyle(fontSize: 20)),
            initialValue: _showEnglish,
            onSelected: (v) => setState(() => _showEnglish = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: false, child: Text('🇨🇿  Original (tchèque)')),
              PopupMenuItem(value: true, child: Text('🇬🇧  Anglais (traduit)')),
            ],
          ),
      ],
      floatingActionButton: o.applyUrl.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _apply,
              icon: const Icon(Symbols.open_in_new),
              label: const Text('Postuler'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          // 1) En-tête
          Text(o.displayTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          _line(Symbols.apartment, o.company),
          if (o.intermediary.isNotEmpty) _line(Symbols.handshake, 'Recruté via ${o.intermediary}'),
          if (o.locationLabel.isNotEmpty) _line(Symbols.location_on, o.locationLabel),
          if (o.publishedAt != null) _line(Symbols.event, _fmtDate(o.publishedAt!)),
          const SizedBox(height: 14),
          _metaTable(context),

          // 2) Matching (si calculé)
          if (o.match != null) ...[
            const SizedBox(height: 16),
            MatchCard(match: o.match!),
          ],

          // 3) Résumé + accès offre complète
          if (_summary.isNotEmpty) ...[
            _sectionTitle(context, Symbols.summarize, 'Résumé'),
            Text(_summary, style: const TextStyle(height: 1.4)),
          ],
          if (o.descriptionText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          OfferDescriptionScreen(offer: o, english: _showEnglish),
                    ),
                  ),
                  icon: const Icon(Symbols.article),
                  label: const Text("Accéder à l'offre complète"),
                ),
              ),
            ),

          // 4) Langues
          if (o.languages.isNotEmpty) _languages(context),

          // 5) Compétences & technologies (logiciels + compétences fusionnés, par domaine)
          if (o.software.isNotEmpty || o.technicalSkills.isNotEmpty)
            SkillBlock(software: o.software, technical: o.technicalSkills),

          // 7) Compétences humaines
          if (o.softSkills.isNotEmpty) ...[
            _sectionTitle(context, Symbols.psychology, 'Compétences humaines'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: o.softSkills
                  .map((s) => Chip(label: Text(s), visualDensity: VisualDensity.compact))
                  .toList(),
            ),
          ],

          // 8) Avantages (4 catégories)
          if (benefits != null && !benefits.isEmpty) ...[
            _sectionTitle(context, Symbols.card_giftcard, 'Avantages'),
            _benefitGroup(context, 'Flexibilité du travail', benefits.flexibility, Symbols.schedule),
            _benefitGroup(context, 'Contributions financières', benefits.financial, Symbols.payments),
            _benefitGroup(context, 'Formations', benefits.training, Symbols.school),
            _benefitGroup(context, 'Autres', benefits.other, Symbols.more_horiz),
          ] else if (o.benefitsFlat.isNotEmpty) ...[
            _sectionTitle(context, Symbols.card_giftcard, 'Avantages'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: o.benefitsFlat
                  .map((b) => Chip(label: Text(b), visualDensity: VisualDensity.compact))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaTable(BuildContext context) {
    final rows = <List<dynamic>>[
      if (o.salaryLabel != null) [Symbols.payments, 'Salaire', o.salaryLabel!],
      if (o.workArrangement.isNotEmpty) [Symbols.home_work, 'Mode', o.workArrangement],
      if (o.experienceYears != null) [Symbols.trending_up, 'Expérience', '${o.experienceYears}+ ans'],
      if (o.education.isNotEmpty) [Symbols.school, 'Études', o.education],
      if (o.contractType.isNotEmpty) [Symbols.assignment, 'Contrat', o.contractType],
      if (o.sector.isNotEmpty) [Symbols.category, 'Secteur', o.sector],
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (final r in rows)
          TableRow(children: [
            Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(r[0] as IconData, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(r[1] as String,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(r[2] as String, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ]),
      ],
    );
  }

  Widget _languages(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(context, Symbols.translate, 'Langues'),
      ...o.languages.map((l) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Icon(l.mandatory ? Symbols.priority_high : Symbols.chevron_right,
                    size: 18, color: l.mandatory ? scheme.error : scheme.primary),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${l.language}${l.level != null && l.level!.isNotEmpty ? ' — ${l.level}' : ''}'
                    '${l.mandatory ? '  (impérative)' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5),
                  ),
                  if (l.reason.isNotEmpty)
                    Text(l.reason,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant, height: 1.3)),
                ]),
              ),
            ]),
          )),
    ]);
  }

  Widget _benefitGroup(BuildContext context, String title, List<SkillItem> items, IconData icon) {
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
        ExplainedList(items: items, bullet: Symbols.check_small),
      ]),
    );
  }

  Widget _sectionTitle(BuildContext context, IconData icon, String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Row(children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ]),
      );

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );

  String _fmtDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return 'Publiée le ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}
