import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/offer.dart';
import '../services/company_service.dart';
import '../services/offers_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/backend_activity_bar.dart';
import 'company_detail_screen.dart';

enum CompanySort { alpha, count }

/// Agrégat d'une entreprise (calculé côté client depuis les offres).
class CompanyAgg {
  final String name;
  int active = 0;
  int total = 0;
  CompanyAgg(this.name);
}

/// Onglet « Entreprises » : liste toutes les entreprises ayant eu des offres,
/// avec recherche et tri (alphabétique ou par nb d'offres actives).
class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key});

  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  CompanySort _sort = CompanySort.count;
  String _query = '';
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<CompanyAgg> _aggregate(List<Offer> offers) {
    final byName = <String, CompanyAgg>{};
    for (final o in offers) {
      final name = o.company.trim();
      if (name.isEmpty) continue;
      final c = byName.putIfAbsent(name.toLowerCase(), () => CompanyAgg(name));
      c.total++;
      if (!o.isExpired) c.active++;
    }
    var list = byName.values.toList();
    final q = _query.toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    switch (_sort) {
      case CompanySort.alpha:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case CompanySort.count:
        list.sort((a, b) {
          final byActive = b.active.compareTo(a.active);
          return byActive != 0 ? byActive : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
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
        final companies = _aggregate(all);
        return AppScaffold(
          title: 'Entreprises',
          actions: [
            IconButton(
              tooltip: 'Localiser les entreprises (IA)',
              icon: const Icon(Symbols.pin_drop),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await context.read<CompanyService>().locateAll();
                messenger.showSnackBar(SnackBar(
                  content: Text(ok
                      ? 'Localisation lancée en arrière-plan (entreprises sans fiche).'
                      : 'Impossible de lancer (serveur injoignable ou tâche en cours ?).'),
                ));
              },
            ),
            PopupMenuButton<CompanySort>(
              tooltip: 'Trier',
              icon: const Icon(Symbols.sort),
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: CompanySort.count, child: Text('Trier par nb d\'offres')),
                PopupMenuItem(value: CompanySort.alpha, child: Text('Trier alphabétiquement')),
              ],
            ),
          ],
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Icon(Symbols.apartment, size: 16),
                const SizedBox(width: 6),
                Text('${companies.length} entreprise${companies.length > 1 ? 's' : ''}'),
              ]),
              const BackendActivityBar(fallbackLabel: 'Localisation des entreprises…'),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Rechercher une entreprise…',
                    prefixIcon: Icon(Symbols.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(child: _buildList(companies, snapshot.connectionState)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(List<CompanyAgg> companies, ConnectionState state) {
    if (state == ConnectionState.waiting && companies.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (companies.isEmpty) {
      return const Center(child: Text('Aucune entreprise.'));
    }
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: companies.length,
        itemBuilder: (context, i) => _tile(context, companies[i]),
      ),
    );
  }

  Widget _tile(BuildContext context, CompanyAgg c) {
    final scheme = Theme.of(context).colorScheme;
    final expired = c.total - c.active;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Text(c.name.substring(0, 1).toUpperCase(),
              style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
        ),
        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${c.active} offre${c.active > 1 ? 's' : ''} active${c.active > 1 ? 's' : ''}'
          '${expired > 0 ? ' · $expired expirée${expired > 1 ? 's' : ''}' : ''}',
        ),
        trailing: const Icon(Symbols.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CompanyDetailScreen(company: c.name)),
        ),
      ),
    );
  }
}
