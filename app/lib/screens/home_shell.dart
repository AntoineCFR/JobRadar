import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'companies_screen.dart';
import 'offers_screen.dart';
import 'profile_screen.dart';

/// Coquille principale de l'app avec bandeau de navigation inférieur :
/// Offres · Favoris · Profil. Chaque onglet est une page autonome (le profil
/// n'a donc plus de bouton retour). Les pages sont conservées (IndexedStack)
/// pour préserver leur état (scroll, filtres) au changement d'onglet.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  // Change la clé de l'onglet Favoris à chaque entrée -> son état est recréé et
  // l'ensemble figé des favoris est recapturé (les offres dé-favorisées pendant
  // la visite disparaissent alors seulement au rechargement).
  int _favGen = 0;

  void _select(int i) {
    setState(() {
      if (i == 1 && _index != 1) _favGen++;
      _index = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: [
        const OffersScreen(),
        OffersScreen(favoritesOnly: true, key: ValueKey('fav-$_favGen')),
        const CompaniesScreen(),
        const ProfileScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Symbols.radar),
            selectedIcon: Icon(Symbols.radar, fill: 1),
            label: 'Offres',
          ),
          NavigationDestination(
            icon: Icon(Symbols.star),
            selectedIcon: Icon(Symbols.star, fill: 1),
            label: 'Favoris',
          ),
          NavigationDestination(
            icon: Icon(Symbols.apartment),
            selectedIcon: Icon(Symbols.apartment, fill: 1),
            label: 'Entreprises',
          ),
          NavigationDestination(
            icon: Icon(Symbols.badge),
            selectedIcon: Icon(Symbols.badge, fill: 1),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
