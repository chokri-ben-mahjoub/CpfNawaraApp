import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/responsive.dart';
import '../../alerts/presentation/alerts_screen.dart';
import '../../auth/presentation/widgets/language_switch.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../plant/presentation/plant_screen.dart';
import '../../settings/presentation/sync_section.dart';
import 'app_drawer.dart';
import 'widgets/notification_bell.dart';
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
    case 3:
      action = () => exportPlantAnalyses(ref, context);
      break;
    default:
      return null;
  }
  final locale = ref.watch(localeProvider);
  return IconButton(tooltip: tr(locale, 'exportTooltip'), icon: const Icon(Icons.download_outlined), onPressed: action);
}

final homeTabIndexProvider = StateProvider<int>((ref) => 0);

const _tabTitleKeys = ['dashboardTitle', 'navAlerts', 'wellsTitle', 'plantTitle', 'statsTitle'];

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
    final role = ref.watch(currentRoleProvider);
    final wellsReady = ref.watch(wellsControllerProvider.select((d) => d.ready));
    final plantReady = ref.watch(plantControllerProvider.select((d) => d.ready));
    String s(String key) => tr(locale, key);
    void select(int i) => ref.read(homeTabIndexProvider.notifier).state = i;

    final appBar = AppBar(
      title: Text(s(_tabTitleKeys[index])),
      actions: [
        ?_exportAction(context, ref, index),
        const NotificationBell(),
        SyncStatusIcon(onTap: () => context.push('/settings')),
        if (role.canConfigure)
          IconButton(
            tooltip: s('adminTitle'),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: () => context.push('/admin'),
          ),
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
    // Onglets : squelettes tant que la base locale n'est pas lue, fondu au
    // changement d'onglet.
    final stack = _FadeIndexedStack(
      index: index,
      children: [
        wellsReady ? const DashboardScreen() : const SkeletonPage(layout: SkeletonLayout.dashboard),
        wellsReady && plantReady ? const AlertsScreen() : const SkeletonPage(),
        wellsReady ? const WellsListScreen() : const SkeletonPage(layout: SkeletonLayout.list),
        plantReady ? const PlantScreen() : const SkeletonPage(layout: SkeletonLayout.plant),
        wellsReady ? const StatsScreen() : const SkeletonPage(),
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
                    data: MediaQuery.of(context)
                        .copyWith(size: Size(constraints.maxWidth, MediaQuery.sizeOf(context).height)),
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
      drawer: AppDrawer(index: index, onSelect: select),
      body: stack,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: select,
        destinations: [
          for (final (icon, selectedIcon, key) in homeDestinations)
            NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selectedIcon), label: s(key)),
        ],
      ),
    );
  }
}

/// Menu latéral (grand écran) : logo, bouton "Nouvelle analyse", onglets,
/// raccourcis en bas. Déplié avec les libellés à partir de 1280 px de large,
/// ou à la demande (bouton menu).
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
    final extended = ref.watch(railExtendedProvider) ?? MediaQuery.sizeOf(context).width >= 1280;

    return NavigationRail(
      extended: extended,
      minExtendedWidth: 232,
      backgroundColor: scheme.surfaceContainerLow,
      selectedIndex: index,
      onDestinationSelected: onSelect,
      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      trailingAtBottom: true,
      trailing: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: extended ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            for (final (icon, key, route) in homeShortcuts(role))
              if (route != '/entry')
                extended
                    ? SizedBox(
                        width: 200,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            foregroundColor: scheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          onPressed: () => context.push(route),
                          icon: Icon(icon),
                          label: Text(s(key)),
                        ),
                      )
                    : IconButton(
                        tooltip: s(key),
                        onPressed: () => context.push(route),
                        icon: Icon(icon, color: scheme.onSurfaceVariant),
                      ),
          ],
        ),
      ),
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
        child: Column(
          crossAxisAlignment: extended ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            IconButton(
              tooltip: s(extended ? 'drawerCollapse' : 'drawerExpand'),
              onPressed: () => ref.read(railExtendedProvider.notifier).state = !extended,
              icon: Icon(extended ? Icons.menu_open_rounded : Icons.menu_rounded),
            ),
            const SizedBox(height: 8),
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
        for (final (icon, selectedIcon, key) in homeDestinations)
          NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selectedIcon), label: Text(s(key))),
      ],
    );
  }
}

/// IndexedStack (chaque onglet garde son état) avec un fondu à l'affichage
/// de l'onglet choisi.
class _FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const _FadeIndexedStack({required this.index, required this.children});

  @override
  State<_FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<_FadeIndexedStack> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  @override
  void didUpdateWidget(_FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          FadeTransition(
            opacity: i == widget.index ? fade : kAlwaysCompleteAnimation,
            child: widget.children[i],
          ),
      ],
    );
  }
}
