import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The three tabs. Each keeps its own stack and scroll position.
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        // Tapping the current tab again returns to its first screen.
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.list_alt_outlined),
            selectedIcon: const Icon(Icons.list_alt),
            label: l10n.navDebts,
          ),
          NavigationDestination(
            icon: const Icon(Icons.show_chart),
            label: l10n.navPlans,
          ),
        ],
      ),
    );
  }
}
