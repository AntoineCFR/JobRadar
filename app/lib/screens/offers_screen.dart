import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/offer.dart';
import '../services/offers_service.dart';
import '../services/scrape_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/offer_tile.dart';
import '../widgets/options_drawer.dart';
import '../widgets/scrape_dialog.dart';
import 'offer_detail_screen.dart';
import 'profile_screen.dart';

/// Écran principal : liste des offres (tuiles) + lancement de recherche.
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  bool _unreadOnly = false;
  bool _sortByRelevance = false;
  String _query = '';

  Future<void> _launchSearch() async {
    final scrapeService = context.read<ScrapeService>();
    final messenger = ScaffoldMessenger.of(context);
    final req = await ScrapeDialog.show(context);
    if (req == null) return;
    final result = await scrapeService.launch(
      site: req.site,
      keyword: req.keyword,
      location: req.location,
    );
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _scanNew() async {
    final ok = await context.read<ScrapeService>().scanNewOffers();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Scan lancé : les nouvelles offres sont récupérées et analysées en arrière-plan.'
          : 'Impossible de lancer le scan (serveur injoignable ?).'),
    ));
  }

  void _openProfile() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));

  List<Offer> _prepare(List<Offer> offers) {
    var list = offers.where((o) {
      if (_unreadOnly && o.isRead) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return o.title.toLowerCase().contains(q) ||
          o.company.toLowerCase().contains(q) ||
          o.software.any((s) => s.name.toLowerCase().contains(q)) ||
          o.technicalSkills.any((s) => s.name.toLowerCase().contains(q));
    }).toList();
    if (_sortByRelevance) {
      list.sort((a, b) => (b.match?.score ?? -1).compareTo(a.match?.score ?? -1));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final offersService = context.read<OffersService>();
    return StreamBuilder<List<Offer>>(
      stream: offersService.watchOffers(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? [];
        final offers = _prepare(all);
        final unread = all.where((o) => !o.isRead).length;

        return AppScaffold(
          title: 'Offres',
          drawer: OptionsDrawer(
            onNewSearch: _launchSearch,
            onMarkAllRead: () => offersService.markAllRead(all),
            onOpenProfile: _openProfile,
            onScanNew: _scanNew,
            unreadOnly: _unreadOnly,
            onUnreadOnlyChanged: (v) => setState(() => _unreadOnly = v),
            sortByRelevance: _sortByRelevance,
            onSortChanged: (v) => setState(() => _sortByRelevance = v),
          ),
          actions: [
            IconButton(
              tooltip: 'Trier par pertinence',
              icon: Icon(_sortByRelevance ? Symbols.sort : Symbols.schedule),
              onPressed: () => setState(() => _sortByRelevance = !_sortByRelevance),
            ),
          ],
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _launchSearch,
            icon: const Icon(Symbols.travel_explore),
            label: const Text('Rechercher'),
          ),
          footer: Row(
            children: [
              const Icon(Symbols.radar, size: 16),
              const SizedBox(width: 6),
              Text('${all.length} offres · $unread nouvelles'),
              const Spacer(),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Filtrer (titre, entreprise, techno…)',
                    prefixIcon: Icon(Symbols.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(child: _buildList(offers, snapshot.connectionState)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(List<Offer> offers, ConnectionState state) {
    if (state == ConnectionState.waiting && offers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (offers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.search_off, size: 48),
            const SizedBox(height: 12),
            const Text('Aucune offre pour le moment.'),
            const SizedBox(height: 4),
            Text('Lancez une recherche pour commencer.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
      itemCount: offers.length,
      itemBuilder: (context, i) {
        final offer = offers[i];
        return OfferTile(
          offer: offer,
          onTap: () {
            context.read<OffersService>().markRead(offer.id, true);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => OfferDetailScreen(offer: offer)),
            );
          },
        );
      },
    );
  }
}
