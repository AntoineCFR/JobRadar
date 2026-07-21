import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/scrape_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/backend_activity_bar.dart';
import '../widgets/skill_block.dart';

/// Écran « Mon profil » : joindre un PDF de compétences → analysé par l'IA,
/// puis utilisé pour matcher les offres.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;

  Future<void> _pickAndUpload() async {
    final uid = context.read<AuthService>().currentUser?.uid;
    if (uid == null) return;
    final profileService = context.read<ProfileService>();
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'md', 'markdown', 'txt'],
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;

    setState(() => _busy = true);
    final err = await profileService.analyze(
      uid: uid,
      pdfBytes: file.bytes!,
      filename: file.name,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(err ??
          'Profil analysé ✓ Les offres sont en cours de (re)matching en arrière-plan.'),
    ));
  }

  Future<void> _reanalyzeAll() async {
    final scrape = context.read<ScrapeService>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ré-analyser toutes les offres ?'),
        content: const Text(
            'Chaque offre de la collection sera repassée dans les agents IA '
            '(extraction + matching). Cela peut prendre plusieurs minutes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lancer')),
        ],
      ),
    );
    if (ok != true) return;
    final started = await scrape.reanalyzeAll();
    messenger.showSnackBar(SnackBar(
      content: Text(started
          ? 'Ré-analyse lancée en arrière-plan. Les offres se mettront à jour au fil de l\'eau.'
          : 'Impossible de lancer la ré-analyse (une autre est peut-être en cours).'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthService>().currentUser?.uid;
    return AppScaffold(
      title: 'Mon profil',
      actions: [
        IconButton(
          tooltip: 'Ré-analyser toutes les offres',
          icon: const Icon(Symbols.autorenew),
          onPressed: _reanalyzeAll,
        ),
      ],
      footer: const BackendActivityBar(fallbackLabel: 'Analyse / matching des offres…'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _pickAndUpload,
        icon: _busy
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Symbols.upload_file),
        label: Text(_busy ? 'Analyse…' : 'Joindre / remplacer (PDF ou .md)'),
      ),
      body: uid == null
          ? const Center(child: Text('Non connecté.'))
          : StreamBuilder<Profile?>(
              stream: context.read<ProfileService>().watch(uid),
              builder: (context, snap) {
                final p = snap.data;
                if (p == null) return _empty(context);
                return _profileView(context, p);
              },
            ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Symbols.badge, size: 56),
            const SizedBox(height: 16),
            Text('Aucun profil pour le moment',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Joins un PDF ou un fichier .md de tes compétences / ton CV. L\'IA '
              'l\'analysera pour évaluer chaque offre selon ton profil (score, '
              'points bloquants, plan).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ]),
        ),
      );

  Widget _profileView(BuildContext context, Profile p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _referenceCard(context, p),
        const SizedBox(height: 16),
        if (p.headline.isNotEmpty)
          Text(p.headline, style: Theme.of(context).textTheme.titleLarge),
        if (p.summary.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(p.summary, style: const TextStyle(height: 1.4)),
        ],
        _chips(context, Symbols.thumb_up, 'Points forts', p.strengths, Colors.green.shade600),
        _chips(context, Symbols.warning, 'Lacunes', p.gaps, Colors.orange.shade700),
        _chips(context, Symbols.translate, 'Langues', p.languages, null),
        if (p.hardSkillItems.isNotEmpty || p.softwareItems.isNotEmpty)
          SkillBlock(software: p.softwareItems, technical: p.hardSkillItems),
      ],
    );
  }

  Widget _referenceCard(BuildContext context, Profile p) {
    final scheme = Theme.of(context).colorScheme;
    final dt = p.updatedAt?.toDate();
    final dateStr = dt == null
        ? ''
        : 'Analysé le ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
            'à ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Card(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(p.isText ? Symbols.article : Symbols.picture_as_pdf, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Document de référence',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant)),
                  Text(p.filename.isEmpty ? '(sans nom)' : p.filename,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
              Chip(
                label: Text(p.isText ? '.md / texte' : 'PDF'),
                visualDensity: VisualDensity.compact,
              ),
            ]),
            if (dateStr.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Symbols.schedule, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(dateStr, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ],
            const SizedBox(height: 6),
            Text('Joindre un nouveau document remplace celui-ci.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _chips(BuildContext c, IconData icon, String title, List<String> items, Color? color) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: color ?? Theme.of(c).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(c).textTheme.titleSmall),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((e) => Chip(label: Text(e), visualDensity: VisualDensity.compact))
              .toList(),
        ),
      ]),
    );
  }
}
