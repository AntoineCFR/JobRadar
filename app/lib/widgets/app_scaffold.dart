import 'package:flutter/material.dart';

/// Structure commune : AppBar en haut, drawer latéral (options), bandeau footer
/// en bas. Conforme aux conventions du projet (pas de barre de nav inférieure,
/// pas de bottom sheet).
class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? drawer;
  final Widget? footer;
  final Widget? floatingActionButton;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.drawer,
    this.footer,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      body: body,
      bottomNavigationBar: footer == null ? null : _FooterBand(child: footer!),
    );
  }
}

class _FooterBand extends StatelessWidget {
  final Widget child;
  const _FooterBand({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.bodySmall!,
            child: child,
          ),
        ),
      ),
    );
  }
}
