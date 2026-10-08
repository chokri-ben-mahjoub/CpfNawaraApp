import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../account/presentation/account_screen.dart';
import '../../alerts/presentation/alerts_screen.dart';
import '../../auth/presentation/widgets/language_switch.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../wells/presentation/wells_list_screen.dart';

final homeTabIndexProvider = StateProvider<int>((ref) => 0);

const _tabTitleKeys = ['dashboardTitle', 'navAlerts', 'wellsTitle', 'navAccount'];

/// Coquille principale de l'app une fois connecté : navigation par onglets
/// entre le tableau de bord du jour, les alertes, les puits et le compte.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabIndexProvider);
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);

    return Scaffold(
      appBar: AppBar(
        title: Text(s(_tabTitleKeys[index])),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: LanguageSwitch()),
          ),
        ],
      ),
      body: IndexedStack(
        index: index,
        children: const [
          DashboardScreen(),
          AlertsScreen(),
          WellsListScreen(),
          AccountScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(homeTabIndexProvider.notifier).state = i,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.fact_check_outlined),
            selectedIcon: const Icon(Icons.fact_check),
            label: s('navToday'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_outlined),
            selectedIcon: const Icon(Icons.notifications),
            label: s('navAlerts'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.water_drop_outlined),
            selectedIcon: const Icon(Icons.water_drop),
            label: s('navWells'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: s('navAccount'),
          ),
        ],
      ),
    );
  }
}
