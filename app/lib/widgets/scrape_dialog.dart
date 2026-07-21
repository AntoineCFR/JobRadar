import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../config/app_config.dart';

class ScrapeRequest {
  final String site;
  final String keyword;
  final String location;
  ScrapeRequest(this.site, this.keyword, this.location);
}

/// Pop-up de lancement d'une recherche : site, mot-clé, localisation.
class ScrapeDialog extends StatefulWidget {
  const ScrapeDialog({super.key});

  static Future<ScrapeRequest?> show(BuildContext context) =>
      showDialog<ScrapeRequest>(context: context, builder: (_) => const ScrapeDialog());

  @override
  State<ScrapeDialog> createState() => _ScrapeDialogState();
}

class _ScrapeDialogState extends State<ScrapeDialog> {
  String _site = AppConfig.sites.first.id;
  final _keyword = TextEditingController();
  final _location = TextEditingController();

  @override
  void dispose() {
    _keyword.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [
        Icon(Symbols.radar),
        SizedBox(width: 10),
        Text('Nouvelle recherche'),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _site,
            decoration: const InputDecoration(labelText: 'Site', prefixIcon: Icon(Symbols.public)),
            items: AppConfig.sites
                .map((s) => DropdownMenuItem(value: s.id, child: Text('${s.country}  ${s.label}')))
                .toList(),
            onChanged: (v) => setState(() => _site = v ?? _site),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyword,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'Mot-clé',
              hintText: 'ex. data engineer',
              prefixIcon: Icon(Symbols.search),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Localisation',
              hintText: 'ex. praha',
              prefixIcon: Icon(Symbols.location_on),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton.icon(
          onPressed: () {
            if (_keyword.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              ScrapeRequest(_site, _keyword.text.trim(), _location.text.trim()),
            );
          },
          icon: const Icon(Symbols.play_arrow),
          label: const Text('Lancer'),
        ),
      ],
    );
  }
}
