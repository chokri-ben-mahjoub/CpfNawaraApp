import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_info.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/presentation/sync_section.dart';
import '../../../core/widgets/profile_avatar.dart';

/// Onglets principaux (icône, icône sélectionnée, clé du libellé).
const homeDestinations = [
  (Icons.fact_check_outlined, Icons.fact_check, 'navToday'),
  (Icons.notifications_outlined, Icons.notifications, 'navAlerts'),
  (Icons.water_drop_outlined, Icons.water_drop, 'navWells'),
  (Icons.factory_outlined, Icons.factory, 'navPlant'),
  (Icons.bar_chart_outlined, Icons.bar_chart, 'navStats'),
];

/// Raccourcis hors onglets (icône, clé du libellé, route), filtrés selon le
/// rôle.
List<(IconData, String, String)> homeShortcuts(UserRole role) => [
      if (role.canEnterData) (Icons.add_circle_outline, 'wellDetailAddAnalysis', '/entry'),
      (Icons.compare_arrows_rounded, 'compareTitle', '/compare'),
      if (role.canEnterData) (Icons.inventory_2_outlined, 'stockTitle', '/stock'),
      if (role.canConfigure) (Icons.admin_panel_settings_outlined, 'adminTitle', '/admin'),
      (Icons.settings_outlined, 'settingsTitle', '/settings'),
    ];

/// Panneau latéral (Drawer) du téléphone : profil, onglets, raccourcis.
class AppDrawer extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const AppDrawer({super.key, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final sync = ref.watch(syncControllerProvider);
    String s(String key) => tr(locale, key);

    void go(String route) {
      Navigator.of(context).pop();
      context.push(route);
    }

    return NavigationDrawer(
      selectedIndex: index,
      onDestinationSelected: (i) {
        Navigator.of(context).pop();
        onSelect(i);
      },
      children: [
        const _DrawerHeader(),
        _SectionLabel(s('drawerNavigation')),
        for (final (icon, selectedIcon, key) in homeDestinations)
          NavigationDrawerDestination(icon: Icon(icon), selectedIcon: Icon(selectedIcon), label: Text(s(key))),
        const Padding(padding: EdgeInsets.fromLTRB(28, 12, 28, 4), child: Divider()),
        _SectionLabel(s('drawerTools')),
        for (final (icon, key, route) in homeShortcuts(role))
          _DrawerTile(icon: icon, label: s(key), onTap: () => go(route)),
        if (sync.isSignedIn)
          _DrawerTile(
            icon: Icons.sync,
            label: s('syncNow'),
            trailing: SyncStatusIcon(onTap: () => go('/settings')),
            onTap: () {
              Navigator.of(context).pop();
              ref.read(syncControllerProvider.notifier).syncNow();
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
          child: Text(
            '${s('appName')} · v$appVersion',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _DrawerHeader extends ConsumerWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final profile = ref.watch(profileProvider);
    final role = ref.watch(currentRoleProvider);
    final sync = ref.watch(syncControllerProvider);
    String s(String key) => tr(locale, key);
    final name = profile?.fullName ?? '';
    const light = Color(0xFFF5EDE8);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [deepNavy, Color(0xFF16344A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset('assets/icon/icon.png', width: 48, height: 48),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s('appName'),
                  style: const TextStyle(color: light, fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const ProfileAvatar(radius: 22, color: light),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? s('accountNoName') : name,
                      style: const TextStyle(color: light, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sync.isSignedIn ? (sync.email ?? '') : s('adminLocalMode'),
                      style: TextStyle(color: light.withValues(alpha: 0.7), fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          RoleChip(role: role),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

/// Ligne de raccourci, même forme que les onglets du panneau.
class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;

  const _DrawerTile({required this.icon, required this.label, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 56,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Menu latéral du grand écran déplié (libellés) ou réduit (icônes) ;
/// `null` : automatique selon la largeur.
final railExtendedProvider = StateProvider<bool?>((ref) => null);
