import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/analysis_type.dart';
import '../../../core/models/user_role.dart';
import '../../../core/models/well.dart';
import '../../../core/theme/app_theme.dart';

class _OverdueItem {
  final Well well;
  final AnalysisType type;
  const _OverdueItem(this.well, this.type);
}

class _OutOfRangeItem {
  final Well well;
  final AnalysisType type;
  final double value;
  const _OutOfRangeItem(this.well, this.type, this.value);
}

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final today = DateTime.now();
    final activeWells = data.wells.where((w) => w.active).toList();

    final overdue = <_OverdueItem>[];
    final outOfRange = <_OutOfRangeItem>[];
    for (final well in activeWells) {
      for (final type in data.analysisTypes) {
        if (type.isDueOn(today) && controller.statusFor(well.id, type.id, now: today) == DailyStatus.overdue) {
          overdue.add(_OverdueItem(well, type));
        }
        final last = controller.lastRecord(well.id, type.id);
        if (last != null && type.isOutOfRange(last.value) && last.isSameDay(today)) {
          outOfRange.add(_OutOfRangeItem(well, type, last.value));
        }
      }
    }

    final hasAlerts = overdue.isNotEmpty || outOfRange.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (!hasAlerts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text(s('alertsEmpty'), textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ),
        if (outOfRange.isNotEmpty) ...[
          _SectionTitle(s('alertsOutOfRangeSection')),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < outOfRange.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.error.withValues(alpha: 0.12),
                      child: Icon(Icons.warning_amber_rounded, color: scheme.error),
                    ),
                    title: Text(
                      '${outOfRange[i].well.name} · ${s(outOfRange[i].type.labelKey)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${outOfRange[i].value} ${outOfRange[i].type.unit} '
                      '(${outOfRange[i].type.min}–${outOfRange[i].type.max} ${outOfRange[i].type.unit})',
                      style: TextStyle(color: scheme.error),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/wells/${outOfRange[i].well.id}/trend/${outOfRange[i].type.id}'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (overdue.isNotEmpty) ...[
          _SectionTitle(s('alertsOverdueSection')),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < overdue.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: accentColor.withValues(alpha: 0.12),
                      child: const Icon(Icons.hourglass_empty_rounded, color: accentColor),
                    ),
                    title: Text(
                      '${overdue[i].well.name} · ${s(overdue[i].type.labelKey)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(s('alertsOverdueSince'), style: TextStyle(color: scheme.onSurfaceVariant)),
                    trailing: role.canEnterData
                        ? FilledButton(
                            onPressed: () =>
                                context.push('/entry?wellId=${overdue[i].well.id}&typeId=${overdue[i].type.id}'),
                            child: Text(s('wellDetailAddAnalysis')),
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700));
  }
}
