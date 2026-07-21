import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../services/scrape_service.dart';

/// Barre de progression affichée en bas de page quand un traitement tourne
/// côté serveur. Interroge `/status` en boucle. Si le backend fournit
/// l'avancement (done/total), affiche une **vraie jauge « X / Y »** ; sinon
/// une barre indéterminée.
class BackendActivityBar extends StatefulWidget {
  final String fallbackLabel;
  const BackendActivityBar({super.key, this.fallbackLabel = 'Traitement en cours…'});

  @override
  State<BackendActivityBar> createState() => _BackendActivityBarState();
}

class _BackendActivityBarState extends State<BackendActivityBar> {
  late final ScrapeService _scrape;
  Timer? _timer;
  bool _running = false;
  int? _done;
  int? _total;
  String _phase = '';

  @override
  void initState() {
    super.initState();
    _scrape = context.read<ScrapeService>();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final s = await _scrape.status();
    if (!mounted) return;
    final running = s?['running'] == true;
    final p = s?['progress'];
    setState(() {
      _running = running;
      if (p is Map) {
        _done = p['done'] is int ? p['done'] as int : null;
        _total = p['total'] is int ? p['total'] as int : null;
        _phase = (p['phase'] ?? '').toString();
      } else {
        _done = _total = null;
        _phase = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_running) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final hasGauge = _total != null && _total! > 0 && _done != null;
    final label = _phase.isNotEmpty ? _phase : widget.fallbackLabel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(children: [
            Icon(Symbols.autorenew, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
            if (hasGauge)
              Text('$_done / $_total',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700, color: scheme.primary)),
          ]),
        ),
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(3)),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: hasGauge ? (_done! / _total!).clamp(0.0, 1.0) : null,
          ),
        ),
      ],
    );
  }
}
