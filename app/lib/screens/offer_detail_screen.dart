import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/offer.dart';
import '../widgets/app_scaffold.dart';

/// Fiche offre : mise en page soignée, icônes Material Symbols, bascule 🇨🇿/🇬🇧
/// quand une traduction existe.
class OfferDetailScreen extends StatefulWidget {
  final Offer offer;
  const OfferDetailScreen({super.key, required this.offer});

  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  late bool _showEnglish = widget.offer.isCzech; // par défaut, la version EN pour une offre CZ

  Offer get o => widget.offer;

  String get _title =>
      (_showEnglish && o.hasTranslation) ? o.translated!.title : o.title;
  String get _summary =>
      (_showEnglish && o.hasTranslation) ? o.translated!.summary : o.summary;
  String get _description =>
      (_showEnglish && o.hasTranslation) ? o.translated!.descriptionText : o.descriptionText;

  Future<void> _apply() async {
    final uri = Uri.tryParse(o.applyUrl);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
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
          Text(_title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          _line(Symbols.apartment, o.company),
          if (o.intermediary.isNotEmpty)
            _line(Symbols.handshake, 'Recruté via ${o.intermediary}'),
          if (o.locationLabel.isNotEmpty) _line(Symbols.location_on, o.locationLabel),
          if (o.publishedAt != null) _line(Symbols.event, _fmtDate(o.publishedAt!)),
          const SizedBox(height: 16),

          _metaGrid(context),

          if (_summary.isNotEmpty) ...[
            _sectionTitle(context, Symbols.summarize, 'Résumé'),
            Text(_summary, style: const TextStyle(height: 1.4)),
          ],

          _chipSection(context, Symbols.psychology, 'Compétences humaines', o.softSkills),
          _chipSection(context, Symbols.construction, 'Compétences techniques', o.technicalSkills),
          _chipSection(context, Symbols.terminal, 'Logiciels & technos', o.software),

          if (o.languages.isNotEmpty) _languages(context),

          _chipSection(context, Symbols.card_giftcard, 'Avantages', o.benefits),

          if (_description.isNotEmpty) ...[
            _sectionTitle(context, Symbols.description, 'Description complète'),
            Text(_description, style: const TextStyle(height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _metaGrid(BuildContext context) {
    final items = <List<dynamic>>[
      if (o.salaryLabel != null) [Symbols.payments, 'Salaire', o.salaryLabel!],
      if (o.workArrangement.isNotEmpty) [Symbols.home_work, 'Mode', o.workArrangement],
      if (o.experienceYears != null) [Symbols.trending_up, 'Expérience', '${o.experienceYears}+ ans'],
      if (o.education.isNotEmpty) [Symbols.school, 'Études', o.education],
      if (o.contractType.isNotEmpty) [Symbols.assignment, 'Contrat', o.contractType],
      if (o.sector.isNotEmpty) [Symbols.category, 'Secteur', o.sector],
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: items
            .map((it) => _metaRow(context, it[0] as IconData, it[1] as String, it[2] as String))
            .toList(),
      ),
    );
  }

  Widget _metaRow(BuildContext context, IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }

  Widget _languages(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(context, Symbols.translate, 'Langues'),
      ...o.languages.map((l) {
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(l.mandatory ? Symbols.priority_high : Symbols.chevron_right,
                size: 18, color: l.mandatory ? scheme.error : scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${l.language}${l.level != null && l.level!.isNotEmpty ? ' — ${l.level}' : ''}'
                  '${l.mandatory ? '  (impérative)' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (l.reason.isNotEmpty)
                  Text(l.reason,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        );
      }),
    ]);
  }

  Widget _chipSection(BuildContext context, IconData icon, String title, List<String> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(context, icon, title),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((e) => Chip(label: Text(e), visualDensity: VisualDensity.compact)).toList(),
      ),
    ]);
  }

  Widget _sectionTitle(BuildContext context, IconData icon, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ]),
    );
  }

  Widget _line(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]),
    );
  }

  String _fmtDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return 'Publiée le ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}
