import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../widgets/app_scaffold.dart';

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
      allowedExtensions: ['pdf'],
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

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthService>().currentUser?.uid;
    return AppScaffold(
      title: 'Mon profil',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _pickAndUpload,
        icon: _busy
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Symbols.upload_file),
        label: Text(_busy ? 'Analyse…' : 'Joindre un PDF'),
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
              'Joins un PDF de tes compétences / ton CV. L\'IA l\'analysera pour '
              'évaluer chaque offre selon ton profil (score, points bloquants, plan).',
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
        if (p.headline.isNotEmpty)
          Text(p.headline, style: Theme.of(context).textTheme.titleLarge),
        Row(children: [
          const Icon(Symbols.description, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(p.filename,
                style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          ),
        ]),
        if (p.summary.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(p.summary, style: const TextStyle(height: 1.4)),
        ],
        _chips(context, Symbols.thumb_up, 'Points forts', p.strengths, Colors.green.shade600),
        _chips(context, Symbols.warning, 'Lacunes', p.gaps, Colors.orange.shade700),
        _chips(context, Symbols.construction, 'Compétences', p.hardSkills, null),
        _chips(context, Symbols.terminal, 'Logiciels', p.software, null),
        _chips(context, Symbols.translate, 'Langues', p.languages, null),
      ],
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
