import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../services/profile_service.dart';
import '../widgets/app_scaffold.dart';

/// Nature d'une section éditable → détermine l'éditeur utilisé.
enum SectionKind { strings, skills, languages, experience }

/// Définition d'une section du profil (tuile de la grille + page d'édition).
class ProfileSection {
  final String key; // clé dans structured{}
  final String title;
  final IconData icon;
  final SectionKind kind;
  const ProfileSection(this.key, this.title, this.icon, this.kind);
}

/// Sections proposées à l'édition (ordre = ordre d'affichage dans la grille).
const kProfileSections = <ProfileSection>[
  ProfileSection('languages', 'Langues', Symbols.translate, SectionKind.languages),
  ProfileSection('hard_skills', 'Compétences techniques', Symbols.psychology_alt, SectionKind.skills),
  ProfileSection('software', 'Logiciels & technos', Symbols.terminal, SectionKind.skills),
  ProfileSection('soft_skills', 'Compétences humaines', Symbols.diversity_3, SectionKind.strings),
  ProfileSection('experience', 'Expériences', Symbols.work_history, SectionKind.experience),
  ProfileSection('education', 'Formations', Symbols.school, SectionKind.strings),
  ProfileSection('certifications', 'Certifications', Symbols.verified, SectionKind.strings),
  ProfileSection('strengths', 'Points forts', Symbols.thumb_up, SectionKind.strings),
  ProfileSection('gaps', 'Lacunes', Symbols.warning, SectionKind.strings),
];

/// Niveaux de maîtrise (compétences/logiciels) → poids de la barre.
const kSkillLevels = <String, int>{
  'Maîtrise': 90,
  'Pratique habituelle': 70,
  'Déjà pratiqué': 45,
  'Notion': 20,
};

/// Niveaux de langue (CEFR + natif).
const kLangLevels = <String>['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'Natif'];

/// Page d'édition d'une section, sauvegarde à la volée (pas de bouton enregistrer).
class ProfileSectionScreen extends StatefulWidget {
  final String uid;
  final ProfileSection section;
  final dynamic initialValue; // valeur courante de structured[section.key]
  const ProfileSectionScreen({
    super.key,
    required this.uid,
    required this.section,
    required this.initialValue,
  });

  @override
  State<ProfileSectionScreen> createState() => _ProfileSectionScreenState();
}

class _ProfileSectionScreenState extends State<ProfileSectionScreen> {
  late List<dynamic> _items;

  @override
  void initState() {
    super.initState();
    final v = widget.initialValue;
    _items = (v is List) ? List<dynamic>.from(v) : <dynamic>[];
  }

  Future<void> _persist() async {
    await context.read<ProfileService>().updateSection(widget.uid, widget.section.key, _items);
  }

  void _mutate(void Function() change) {
    setState(change);
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.section.title,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _hint(context),
          const SizedBox(height: 8),
          switch (widget.section.kind) {
            SectionKind.strings => _stringsEditor(context),
            SectionKind.skills => _skillsEditor(context),
            SectionKind.languages => _languagesEditor(context),
            SectionKind.experience => _experienceEditor(context),
          },
        ],
      ),
    );
  }

  Widget _hint(BuildContext context) => Row(children: [
        Icon(Symbols.bolt, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Les modifications sont enregistrées automatiquement.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]);

  // ---------------------------------------------------------------- strings --
  Widget _stringsEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _items.length; i++)
          Card(
            child: ListTile(
              dense: true,
              title: Text('${_items[i]}'),
              trailing: IconButton(
                icon: const Icon(Symbols.delete, size: 20),
                onPressed: () => _mutate(() => _items.removeAt(i)),
              ),
            ),
          ),
        const SizedBox(height: 8),
        _AddField(
          hint: 'Ajouter…',
          onAdd: (text) => _mutate(() => _items.add(text)),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- skills --
  Widget _skillsEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _items.length; i++) _skillRow(context, i),
        const SizedBox(height: 8),
        _AddField(
          hint: 'Ajouter une compétence…',
          onAdd: (text) => _mutate(() => _items.add({
                'name': text,
                'level': 'Déjà pratiqué',
                'weight': kSkillLevels['Déjà pratiqué'],
                'domain': '',
                'explanation': '',
              })),
        ),
      ],
    );
  }

  Widget _skillRow(BuildContext context, int i) {
    final m = _items[i] is Map ? Map<String, dynamic>.from(_items[i]) : <String, dynamic>{'name': '${_items[i]}'};
    final level = kSkillLevels.containsKey(m['level']) ? m['level'] as String : 'Déjà pratiqué';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((m['name'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButton<String>(
                    value: level,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: kSkillLevels.keys
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) => _mutate(() {
                      m['level'] = v;
                      m['weight'] = kSkillLevels[v];
                      _items[i] = m;
                    }),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Symbols.delete, size: 20),
              onPressed: () => _mutate(() => _items.removeAt(i)),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- languages --
  Widget _languagesEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _items.length; i++) _languageRow(context, i),
        const SizedBox(height: 8),
        _AddField(
          hint: 'Ajouter une langue…',
          onAdd: (text) => _mutate(() => _items.add({'language': text, 'level': 'B1'})),
        ),
      ],
    );
  }

  Widget _languageRow(BuildContext context, int i) {
    final m = _items[i] is Map ? Map<String, dynamic>.from(_items[i]) : <String, dynamic>{'language': '${_items[i]}'};
    final scheme = Theme.of(context).colorScheme;
    final rawLevel = (m['level'] ?? '').toString();
    // Niveau reconnu (CEFR) -> sélectionné dans le menu ; sinon on garde le
    // texte verbatim en sous-titre (ex. « A2 solide, proche B1 ») et le menu
    // sert à le normaliser. Le hint reste COURT pour ne pas déborder.
    final lvl = kLangLevels.contains(m['level']) ? m['level'] as String : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((m['language'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (lvl == null && rawLevel.isNotEmpty)
                    Text('actuel : $rawLevel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: lvl,
              hint: const Text('niveau', style: TextStyle(fontSize: 13)),
              isDense: true,
              underline: const SizedBox.shrink(),
              items: kLangLevels
                  .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                  .toList(),
              onChanged: (v) => _mutate(() {
                m['level'] = v;
                _items[i] = m;
              }),
            ),
            IconButton(
              icon: const Icon(Symbols.delete, size: 20),
              onPressed: () => _mutate(() => _items.removeAt(i)),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- experience --
  Widget _experienceEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _items.length; i++) _experienceRow(context, i),
        const SizedBox(height: 8),
        _AddField(
          hint: 'Ajouter un poste (intitulé)…',
          onAdd: (text) => _mutate(() => _items.add({'role': text, 'years': null, 'field': ''})),
        ),
      ],
    );
  }

  Widget _experienceRow(BuildContext context, int i) {
    final m = _items[i] is Map ? Map<String, dynamic>.from(_items[i]) : <String, dynamic>{'role': '${_items[i]}'};
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: (m['role'] ?? '').toString(),
                    decoration: const InputDecoration(labelText: 'Poste', isDense: true),
                    onChanged: (v) {
                      m['role'] = v;
                      _items[i] = m;
                      _persist();
                    },
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        initialValue: m['years']?.toString() ?? '',
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Années', isDense: true),
                        onChanged: (v) {
                          m['years'] = int.tryParse(v);
                          _items[i] = m;
                          _persist();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        initialValue: (m['field'] ?? '').toString(),
                        decoration: const InputDecoration(labelText: 'Domaine', isDense: true),
                        onChanged: (v) {
                          m['field'] = v;
                          _items[i] = m;
                          _persist();
                        },
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Symbols.delete, size: 20),
              onPressed: () => _mutate(() => _items.removeAt(i)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Champ « ajouter » réutilisable : texte + bouton +.
class _AddField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onAdd;
  const _AddField({required this.hint, required this.onAdd});

  @override
  State<_AddField> createState() => _AddFieldState();
}

class _AddFieldState extends State<_AddField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    widget.onAdd(t);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(hintText: widget.hint, isDense: true),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(icon: const Icon(Symbols.add), onPressed: _submit),
      ],
    );
  }
}
