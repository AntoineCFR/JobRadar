import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

/// Drawer latéral : options et actions globales (conforme aux conventions —
/// tout ce qui n'est pas contextuel passe ici).
class OptionsDrawer extends StatelessWidget {
  final VoidCallback onNewSearch;
  final VoidCallback onMarkAllRead;
  final bool unreadOnly;
  final ValueChanged<bool> onUnreadOnlyChanged;

  const OptionsDrawer({
    super.key,
    required this.onNewSearch,
    required this.onMarkAllRead,
    required this.unreadOnly,
    required this.onUnreadOnlyChanged,
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
            SwitchListTile(
              secondary: const Icon(Symbols.mark_email_unread),
              title: const Text('Nouveautés seulement'),
              value: unreadOnly,
              onChanged: onUnreadOnlyChanged,
            ),
            ListTile(
              leading: const Icon(Symbols.done_all),
              title: const Text('Tout marquer comme lu'),
              onTap: () {
                Navigator.pop(context);
                onMarkAllRead();
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
