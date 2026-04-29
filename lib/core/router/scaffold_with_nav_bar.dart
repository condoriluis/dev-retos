import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/retos_repository.dart';

class ScaffoldWithNavBar extends ConsumerWidget {
  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        destinations: const [
          NavigationDestination(
            label: 'DIARIO',
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
          ),
          NavigationDestination(
            label: 'PRÁCTICA',
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
          ),
          NavigationDestination(
            label: 'RANKING',
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
          ),
          NavigationDestination(
            label: 'PERFIL',
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
          ),
        ],
        onDestinationSelected: (index) => _goBranch(index, ref),
      ),
    );
  }

  void _goBranch(int index, WidgetRef ref) {
    if (index == 0) {
      ref.invalidate(dailyChallengesProvider);
    } else if (index == 1) {
      ref.invalidate(userSessionsProvider);
    } else if (index == 2) {
      ref.invalidate(globalRankingProvider);
    } else if (index == 3) {
      ref.invalidate(userProfileProvider);
      ref.invalidate(userStatsProvider);
    }

    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
