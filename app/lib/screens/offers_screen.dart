import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/offer.dart';
import '../services/offers_service.dart';
import '../services/scrape_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/backend_activity_bar.dart';
import '../widgets/filter_dialog.dart';
import '../widgets/offer_tile.dart';
import '../widgets/options_drawer.dart';
import '../widgets/scrape_dialog.dart';
import 'offer_detail_screen.dart';
import 'profile_screen.dart';

enum SortMode { pertinence, match, date }

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  SortMode _sort = SortMode.pertinence;
  OfferFilters _filters = OfferFilters();
  String _query = '';

  Future<void> _launchSearch() async {
    final scrapeService = context.read<ScrapeService>();
    final messenger = ScaffoldMessenger.of(context);
    final req = await ScrapeDialog.show(context);
    if (req == null) return;
    final result = await scrapeService.launch(
        site: req.site, keyword: req.keyword, location: req.location);
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

  Future<void> _openFilters() async {
    final res = await FilterDialog.show(context, _filters);
    if (res != null) setState(() => _filters = res);
  }

  List<Offer> _prepare(List<Offer> offers) {
    final q = _query.toLowerCase();
    var list = offers.where((o) {
      if (_filters.unreadOnly && o.isRead) return false;
      if (_filters.juniorOnly && !o.isJunior) return false;
      if (_filters.hideCzechMandatory && o.requiresMandatoryCzech) return false;
      if (_filters.minRelevance > 0 &&
          (o.relevanceScore == null || o.relevanceScore! < _filters.minRelevance)) {
        return false;
      }
      if (_filters.minMatch > 0 && (o.match == null || o.match!.score < _filters.minMatch)) {
        return false;
      }
      if (_filters.workArrangement.isNotEmpty &&
          !o.workArrangement.toLowerCase().contains(_filters.workArrangement)) {
        return false;
      }
      if (q.isNotEmpty) {
        final hit = o.title.toLowerCase().contains(q) ||
            o.company.toLowerCase().contains(q) ||
            o.software.any((s) => s.name.toLowerCase().contains(q)) ||
            o.technicalSkills.any((s) => s.name.toLowerCase().contains(q));
        if (!hit) return false;
      }
      return true;
    }).toList();

    switch (_sort) {
      case SortMode.pertinence:
        list.sort((a, b) => (b.relevanceScore ?? -1).compareTo(a.relevanceScore ?? -1));
        break;
      case SortMode.match:
        list.sort((a, b) => (b.match?.score ?? -1).compareTo(a.match?.score ?? -1));
        break;
      case SortMode.date:
        final epoch = DateTime.fromMillisecondsSinceEpoch(0);
        list.sort((a, b) =>
            (b.effectiveDate ?? epoch).compareTo(a.effectiveDate ?? epoch));
        break;
    }
    return list;
  }

  String get _sortLabel => switch (_sort) {
        SortMode.pertinence => 'Pertinence',
        SortMode.match => 'Compatibilité',
        SortMode.date => 'Date',
      };

  @override
  Widget build(BuildContext context) {
    final offersService = context.read<OffersService>();
    return StreamBuilder<List<Offer>>(
      stream: offersService.watchOffers(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? [];
        final offers = _prepare(all);
        final unread = all.where((o) => !o.isRead).length;
        final nFilters = _filters.activeCount;

        return AppScaffold(
          title: 'Offres',
          drawer: OptionsDrawer(
            onNewSearch: _launchSearch,
            onMarkAllRead: () => offersService.markAllRead(all),
            onOpenProfile: _openProfile,
            onScanNew: _scanNew,
          ),
          actions: [
            IconButton(
              tooltip: 'Filtrer',
              onPressed: _openFilters,
              icon: Badge(
                isLabelVisible: nFilters > 0,
                label: Text('$nFilters'),
                child: const Icon(Symbols.filter_alt),
              ),
            ),
            PopupMenuButton<SortMode>(
              tooltip: 'Trier',
              icon: const Icon(Symbols.sort),
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: SortMode.pertinence, child: Text('Trier par pertinence')),
                PopupMenuItem(value: SortMode.match, child: Text('Trier par compatibilité')),
                PopupMenuItem(value: SortMode.date, child: Text('Trier par date')),
              ],
            ),
          ],
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _launchSearch,
            icon: const Icon(Symbols.travel_explore),
            label: const Text('Rechercher'),
          ),
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Icon(Symbols.radar, size: 16),
                const SizedBox(width: 6),
                Text('${offers.length}/${all.length} offres · $unread nouvelles · tri : $_sortLabel'),
                const Spacer(),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const BackendActivityBar(fallbackLabel: 'Récupération / analyse des offres…'),
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
            const Text('Aucune offre à afficher.'),
            const SizedBox(height: 4),
            Text('Lance une recherche ou ajuste les filtres.',
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
