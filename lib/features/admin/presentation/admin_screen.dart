import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/shared_config.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/sync/firebase_config_provider.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../settings/presentation/sync_section.dart';

/// Administration (rôle admin) : tout le paramétrage de l'app au même
/// endroit, sans passer par la console Firebase.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final wells = ref.watch(wellsControllerProvider);
    final plant = ref.watch(plantControllerProvider);
    final shared = ref.watch(sharedConfigProvider);
    final config = ref.watch(firebaseConfigProvider);
    final sync = ref.watch(syncControllerProvider);
    String s(String key) => tr(locale, key);
    final team = config != null && sync.isSignedIn;
    final thresholdCount = plant.thresholds.values.fold<int>(0, (n, m) => n + m.length);

    final tiles = [
      _AdminTile(
        icon: Icons.group_outlined,
        title: s('adminUsers'),
        subtitle: team ? s('adminUsersHint') : s('adminUsersLocal'),
        onTap: () => context.push('/admin/users'),
      ),
      _AdminTile(
        icon: Icons.water_drop_outlined,
        title: s('wellsManageTitle'),
        subtitle: fill(s('adminWellsCount'), {'n': '${wells.wells.length}'}),
        onTap: () => context.push('/admin/wells'),
      ),
      _AdminTile(
        icon: Icons.factory_outlined,
        title: s('adminPoints'),
        subtitle: fill(s('adminPointsCount'), {'n': '${plant.points.length}'}),
        onTap: () => context.push('/admin/points'),
      ),
      _AdminTile(
        icon: Icons.notifications_active_outlined,
        title: s('adminThresholds'),
        subtitle: fill(s('adminThresholdsCount'), {
          'n': '$thresholdCount',
          'time': formatDeadline(shared.missingDeadline),
        }),
        onTap: () => context.push('/admin/thresholds'),
      ),
      _AdminTile(
        icon: Icons.rule,
        title: s('accountAdminSettings'),
        subtitle: fill(s('adminTypesCount'), {'n': '${wells.analysisTypes.length}'}),
        onTap: () => context.push('/admin/analysis-types'),
      ),
      _AdminTile(
        icon: Icons.import_export_rounded,
        title: s('adminData'),
        subtitle: s('adminDataHint'),
        onTap: () => context.push('/admin/data'),
      ),
      _AdminTile(
        icon: Icons.cloud_outlined,
        title: s('adminFirebase'),
        subtitle: config == null ? s('adminFirebaseNone') : '${s('setupProject')} : ${config.projectId}',
        onTap: () => context.push('/admin/firebase'),
      ),
      _AdminTile(
        icon: Icons.history_rounded,
        title: s('adminAudit'),
        subtitle: team ? s('adminAuditHint') : s('adminAuditLocal'),
        onTap: () => context.push('/admin/audit'),
      ),
      _AdminTile(
        icon: Icons.tune,
        title: s('adminDevicePrefs'),
        subtitle: s('adminDevicePrefsHint'),
        onTap: () => context.push('/settings'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(s('adminTitle')),
        actions: [SyncStatusIcon(onTap: () => context.push('/settings'))],
      ),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentColor.withValues(alpha: 0.16), accentColor.withValues(alpha: 0.04)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const Icon(Icons.admin_panel_settings_outlined, color: accentColor, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team ? (sync.email ?? '') : s('adminLocalMode'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        team ? s('adminTeamModeHint') : s('adminLocalModeHint'),
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ResponsiveWrapGrid(minItemWidth: 300, spacing: 12, children: tiles),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
