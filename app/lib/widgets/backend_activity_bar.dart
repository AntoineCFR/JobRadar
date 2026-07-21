import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../services/scrape_service.dart';

/// Barre de progression affichée en bas de page quand un traitement tourne
/// côté serveur (scrape / extraction / matching). Interroge `/status` en boucle
/// et ne s'affiche que pendant un run.
class BackendActivityBar extends StatefulWidget {
  final String label;
  const BackendActivityBar({super.key, this.label = 'Traitement en cours…'});

  @override
  State<BackendActivityBar> createState() => _BackendActivityBarState();
}

class _BackendActivityBarState extends State<BackendActivityBar> {
  late final ScrapeService _scrape;
  Timer? _timer;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _scrape = context.read<ScrapeService>();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final s = await _scrape.status();
    if (!mounted) return;
    final r = s?['running'] == true;
    if (r != _running) setState(() => _running = r);
  }

  @override
  Widget build(BuildContext context) {
    if (!_running) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(children: [
            Icon(Symbols.autorenew, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Text(widget.label, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(3)),
          child: LinearProgressIndicator(minHeight: 5),
        ),
      ],
    );
  }
}
