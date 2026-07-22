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

enum SortMode { pertinence, match, date }

class OffersScreen extends StatefulWidget {
  /// Onglet « Favoris » : n'affiche que les offres étoilées, sans recherche.
  final bool favoritesOnly;

  /// Page « Offres expirées » : n'affiche que les offres expirées, sans recherche.
  final bool expiredOnly;
  const OffersScreen({super.key, this.favoritesOnly = false, this.expiredOnly = false});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  SortMode _sort = SortMode.pertinence;
  OfferFilters _filters = OfferFilters();
  String _query = '';
  final ScrollController _scrollController = ScrollController();

  /// Onglet Favoris : ensemble figé des offres favorites à l'entrée de la page.
  /// Dé-favoriser une tuile ne la retire PAS tout de suite (anti-misclic) — elle
  /// reste jusqu'au rechargement de la page (nouvelle entrée dans l'onglet, qui
  /// recrée cet état via une clé changeante côté HomeShell).
  Set<String>? _frozenFavIds;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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

  void _openExpired() => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const OffersScreen(expiredOnly: true)));

  Future<void> _openFilters() async {
    final res = await FilterDialog.show(context, _filters);
    if (res != null) setState(() => _filters = res);
  }

  List<Offer> _prepare(List<Offer> offers) {
    final q = _query.toLowerCase();
    var list = offers.where((o) {
      // Sélection de base selon le mode de la page.
      if (widget.expiredOnly) {
        if (!o.isExpired) return false;
      } else if (widget.favoritesOnly) {
        // Vue Favoris : ensemble FIGÉ (pas l'état live) pour ne pas retirer une
        // tuile dès le dé-clic sur l'étoile.
        if (!(_frozenFavIds?.contains(o.id) ?? false)) return false;
      } else {
        // Liste principale : les offres expirées disparaissent (page dédiée).
        if (o.isExpired) return false;
      }
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
        // Fige l'ensemble des favoris à la 1re émission de données de cette page.
        if (widget.favoritesOnly && _frozenFavIds == null && snapshot.hasData) {
          _frozenFavIds = all.where((o) => o.isFavorite).map((o) => o.id).toSet();
        }
        final offers = _prepare(all);
        final unread = all.where((o) => !o.isRead).length;
        final nFilters = _filters.activeCount;

        final secondary = widget.favoritesOnly || widget.expiredOnly;
        return AppScaffold(
          title: widget.expiredOnly
              ? 'Offres expirées'
              : (widget.favoritesOnly ? 'Favoris' : 'Offres'),
          drawer: secondary
              ? null
              : OptionsDrawer(
                  onNewSearch: _launchSearch,
                  onScanNew: _scanNew,
                  onOpenExpired: _openExpired,
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
          floatingActionButton: secondary
              ? null
              : FloatingActionButton.extended(
                  heroTag: 'fab-search', // tag unique : évite la collision Hero
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
            Icon(
                widget.expiredOnly
                    ? Symbols.history
                    : (widget.favoritesOnly ? Symbols.star : Symbols.search_off),
                size: 48),
            const SizedBox(height: 12),
            Text(widget.expiredOnly
                ? 'Aucune offre expirée.'
                : (widget.favoritesOnly ? 'Aucun favori.' : 'Aucune offre à afficher.')),
            const SizedBox(height: 4),
            Text(
                widget.expiredOnly
                    ? 'Les offres non retrouvées au scraping apparaîtront ici.'
                    : (widget.favoritesOnly
                        ? "Touche l'étoile ⭐ sur une offre pour l'ajouter ici."
                        : 'Lance une recherche ou ajuste les filtres.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
        itemCount: offers.length,
        itemBuilder: (context, i) {
          final offer = offers[i];
          return OfferTile(
            offer: offer,
            onToggleFavorite: (fav) async {
              final messenger = ScaffoldMessenger.of(context);
              final err = await context.read<OffersService>().toggleFavorite(offer.id, fav);
              if (err != null) messenger.showSnackBar(SnackBar(content: Text(err)));
            },
            onTap: () {
              context.read<OffersService>().markRead(offer.id, true);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => OfferDetailScreen(offer: offer)),
              );
            },
          );
        },
      ),
    );
  }
}
