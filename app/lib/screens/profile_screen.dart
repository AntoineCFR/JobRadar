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
import 'profile_section_screen.dart';

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

  Future<void> _recalcMatching() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await context.read<ScrapeService>().triggerMatch(force: true);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Matching recalculé en arrière-plan avec ton profil à jour. Les scores se mettront à jour au fil de l\'eau.'
          : 'Impossible de lancer le recalcul (serveur injoignable ou déjà en cours ?).'),
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
          tooltip: 'Recalculer le matching (prend en compte tes modifications)',
          icon: const Icon(Symbols.calculate),
          onPressed: _recalcMatching,
        ),
        IconButton(
          tooltip: 'Ré-analyser toutes les offres',
          icon: const Icon(Symbols.autorenew),
          onPressed: _reanalyzeAll,
        ),
      ],
      footer: const BackendActivityBar(fallbackLabel: 'Analyse / matching des offres…'),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-profile-attach', // tag unique : évite la collision Hero
        onPressed: _busy ? null : _pickAndUpload,
        icon: _busy
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Symbols.upload_file),
        label: Text(_busy ? 'Analyse…' : 'Joindre / compléter (PDF ou .md)'),
      ),
      body: uid == null
          ? const Center(child: Text('Non connecté.'))
          : StreamBuilder<Profile?>(
              stream: context.read<ProfileService>().watch(uid),
              builder: (context, snap) {
                final p = snap.data;
                if (p == null) return _empty(context);
                return _profileView(context, uid, p);
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

  Widget _profileView(BuildContext context, String uid, Profile p) {
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
        const SizedBox(height: 20),
        Text('Mes informations',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Touche une section pour l’éditer (ajout, suppression, niveau).',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            for (final s in kProfileSections) _sectionTile(context, uid, p, s),
          ],
        ),
      ],
    );
  }

  Widget _sectionTile(BuildContext context, String uid, Profile p, ProfileSection s) {
    final scheme = Theme.of(context).colorScheme;
    final v = p.structured[s.key];
    final count = v is List ? v.length : 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileSectionScreen(uid: uid, section: s, initialValue: v),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(s.icon, size: 30, color: scheme.primary),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title,
                      style: const TextStyle(fontWeight: FontWeight.w600, height: 1.15)),
                  const SizedBox(height: 2),
                  Text(count == 0 ? 'à compléter' : '$count élément${count > 1 ? 's' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
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
            Text('Un nouveau document ne met à jour que les sections qu\'il '
                'mentionne — le reste de ton profil est conservé.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

}
