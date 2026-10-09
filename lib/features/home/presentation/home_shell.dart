import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/widgets/responsive.dart';
import '../../account/presentation/account_screen.dart';
import '../../alerts/presentation/alerts_screen.dart';
import '../../auth/presentation/widgets/language_switch.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../stats/presentation/stats_screen.dart';
import '../../wells/presentation/wells_list_screen.dart';

/// Action d'export (Excel/CSV, télécharger ou partager) disponible dans l'AppBar pour les onglets qui ont
/// quelque chose à exporter (tableau de bord, alertes).
Widget? _exportAction(BuildContext context, WidgetRef ref, int index) {
  Future<void> Function()? action;
  switch (index) {
    case 0:
      action = () => exportDashboardPeriod(ref, context);
      break;
    case 1:
      action = () => exportAlerts(ref, context);
      break;
    default:
      return null;
  }
  final locale = ref.watch(localeProvider);
  return IconButton(
    tooltip: tr(locale, 'exportTooltip'),
    icon: const Icon(Icons.download_outlined),
    onPressed: action,
  );
}

final homeTabIndexProvider = StateProvider<int>((ref) => 0);

const _tabTitleKeys = ['dashboardTitle', 'navAlerts', 'wellsTitle', 'statsTitle', 'navAccount'];

/// Onglets principaux (icône, icône sélectionnée, clé du libellé).
const _destinations = [
  (Icons.fact_check_outlined, Icons.fact_check, 'navToday'),
  (Icons.notifications_outlined, Icons.notifications, 'navAlerts'),
  (Icons.water_drop_outlined, Icons.water_drop, 'navWells'),
  (Icons.bar_chart_outlined, Icons.bar_chart, 'navStats'),
  (Icons.person_outline, Icons.person, 'navAccount'),
];

/// Coquille principale de l'app une fois connecté : navigation par onglets
/// entre le tableau de bord du jour, les alertes, les puits, les stats et le
/// compte — barre du bas sur téléphone, menu latéral sur grand écran (web,
/// PC, tablette).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabIndexProvider);
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    void select(int i) => ref.read(homeTabIndexProvider.notifier).state = i;

    final appBar = AppBar(
      title: Text(s(_tabTitleKeys[index])),
      actions: [
        ?_exportAction(context, ref, index),
        IconButton(
          tooltip: s('settingsTitle'),
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push('/settings'),
        ),
        const Padding(
          padding: EdgeInsets.only(right: 12),
          child: Center(child: LanguageSwitch()),
        ),
      ],
    );
    final stack = IndexedStack(
      index: index,
      children: const [
        DashboardScreen(),
        AlertsScreen(),
        WellsListScreen(),
        StatsScreen(),
        AccountScreen(),
      ],
    );

    if (isWideLayout(context)) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _SideRail(index: index, onSelect: select),
              VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
              // Les écrans des onglets calculent leurs marges d'après la
              // largeur réellement disponible (écran moins le menu latéral).
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: Size(constraints.maxWidth, MediaQuery.sizeOf(context).height),
                    ),
                    child: Scaffold(appBar: appBar, body: stack),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: stack,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: select,
        destinations: [
          for (final (icon, selectedIcon, key) in _destinations)
            NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selectedIcon), label: s(key)),
        ],
      ),
    );
  }
}

/// Menu latéral (grand écran) : logo, bouton "Nouvelle analyse", onglets.
/// Déplié avec les libellés à partir de 1280 px de large.
class _SideRail extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const _SideRail({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    String s(String key) => tr(locale, key);
    final extended = MediaQuery.sizeOf(context).width >= 1280;

    return NavigationRail(
      extended: extended,
      minExtendedWidth: 232,
      backgroundColor: scheme.surfaceContainerLow,
      selectedIndex: index,
      onDestinationSelected: onSelect,
      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 20),
        child: Column(
          crossAxisAlignment: extended ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset('assets/icon/icon.png', width: 40, height: 40),
                ),
                if (extended) ...[
                  const SizedBox(width: 12),
                  Text(
                    s('appName'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
            if (role.canEnterData) ...[
              const SizedBox(height: 20),
              extended
                  ? FloatingActionButton.extended(
                      heroTag: 'rail-entry',
                      elevation: 0,
                      onPressed: () => context.push('/entry'),
                      icon: const Icon(Icons.add),
                      label: Text(s('wellDetailAddAnalysis')),
                    )
                  : FloatingActionButton(
                      heroTag: 'rail-entry',
                      elevation: 0,
                      tooltip: s('wellDetailAddAnalysis'),
                      onPressed: () => context.push('/entry'),
                      child: const Icon(Icons.add),
                    ),
            ],
          ],
        ),
      ),
      destinations: [
        for (final (icon, selectedIcon, key) in _destinations)
          NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selectedIcon), label: Text(s(key))),
      ],
    );
  }
}
