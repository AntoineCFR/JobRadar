import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/offer.dart';
import '../services/company_service.dart';
import '../services/offers_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/offer_tile.dart';
import 'offer_detail_screen.dart';

/// Ouvre Google Maps sur une requête de lieu.
Future<void> openMaps(String query) async {
  final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Fiche entreprise : la liste de ses offres (actives + expirées).
class CompanyDetailScreen extends StatefulWidget {
  final String company;
  const CompanyDetailScreen({super.key, required this.company});

  @override
  State<CompanyDetailScreen> createState() => _CompanyDetailScreenState();
}

class _CompanyDetailScreenState extends State<CompanyDetailScreen> {
  final _scrollController = ScrollController();
  bool _locating = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    final err = await context.read<CompanyService>().locateOne(widget.company);
    if (!mounted) return;
    setState(() => _locating = false);
    if (err != null) messenger.showSnackBar(SnackBar(content: Text(err)));
  }

  Widget _locationCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<Company?>(
      stream: context.read<CompanyService>().watch(widget.company),
      builder: (context, snap) {
        final loc = snap.data?.location;
        return Card(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Symbols.location_on, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: (loc != null && loc.label.isNotEmpty)
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Localisation',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant)),
                        Text(loc.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (loc.confidence != null)
                          Text('confiance : ${loc.confidence}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant)),
                      ])
                    : Text('Lieu non renseigné.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 8),
              if (loc != null && loc.query.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: () => openMaps(loc.query),
                  icon: const Icon(Symbols.directions, size: 18),
                  label: const Text('Itinéraire'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: _locating ? null : _locate,
                  icon: _locating
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Symbols.pin_drop, size: 18),
                  label: const Text('Localiser'),
                ),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final offersService = context.read<OffersService>();
    final key = widget.company.toLowerCase().trim();
    return AppScaffold(
      title: widget.company,
      body: Column(children: [
        _locationCard(context),
        Expanded(
          child: StreamBuilder<List<Offer>>(
        stream: offersService.watchOffers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final offers = (snapshot.data ?? [])
              .where((o) => o.company.toLowerCase().trim() == key)
              .toList()
            ..sort((a, b) {
              // Actives d'abord, puis par date effective décroissante.
              if (a.isExpired != b.isExpired) return a.isExpired ? 1 : -1;
              final epoch = DateTime.fromMillisecondsSinceEpoch(0);
              return (b.effectiveDate ?? epoch).compareTo(a.effectiveDate ?? epoch);
            });
          if (offers.isEmpty) {
            return const Center(child: Text('Aucune offre pour cette entreprise.'));
          }
          return Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: offers.length,
              itemBuilder: (context, i) {
                final offer = offers[i];
                return OfferTile(
                  offer: offer,
                  onToggleFavorite: (fav) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final err = await offersService.toggleFavorite(offer.id, fav);
                    if (err != null) messenger.showSnackBar(SnackBar(content: Text(err)));
                  },
                  onTap: () {
                    offersService.markRead(offer.id, true);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => OfferDetailScreen(offer: offer)),
                    );
                  },
                );
              },
            ),
          );
        },
          ),
        ),
      ]),
    );
  }
}
