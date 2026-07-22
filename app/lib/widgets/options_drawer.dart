import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

/// Drawer latéral : actions globales.
class OptionsDrawer extends StatelessWidget {
  final VoidCallback onNewSearch;
  final VoidCallback onScanNew;
  final VoidCallback onOpenExpired;

  const OptionsDrawer({
    super.key,
    required this.onNewSearch,
    required this.onScanNew,
    required this.onOpenExpired,
  });

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthService>().currentUser;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Symbols.radar, size: 28),
                const SizedBox(width: 10),
                Text('JobRadar', style: Theme.of(context).textTheme.titleLarge),
              ]),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Symbols.travel_explore),
              title: const Text('Nouvelle recherche'),
              onTap: () {
                Navigator.pop(context);
                onNewSearch();
              },
            ),
            ListTile(
              leading: const Icon(Symbols.radar),
              title: const Text('Scanner les nouvelles offres'),
              subtitle: const Text('récupère + analyse les nouveautés'),
              onTap: () {
                Navigator.pop(context);
                onScanNew();
              },
            ),
            ListTile(
              leading: const Icon(Symbols.history),
              title: const Text('Offres expirées'),
              subtitle: const Text('offres non retrouvées au scraping'),
              onTap: () {
                Navigator.pop(context);
                onOpenExpired();
              },
            ),
            const Spacer(),
            const Divider(height: 1),
            if (user != null)
              ListTile(
                leading: const Icon(Symbols.account_circle),
                title: Text(user.displayName ?? user.email ?? 'Compte'),
                subtitle: const Text('Se déconnecter'),
                onTap: () async {
                  await context.read<AuthService>().signOut();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}
