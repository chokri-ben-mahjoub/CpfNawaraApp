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

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final name = ref.watch(pendingNameProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final today = DateTime.now();
    final dueTypes = data.analysisTypes.where((t) => t.isDueOn(today)).toList();
    final activeWells = data.wells.where((w) => w.active).toList();

    var totalDue = 0;
    var totalDone = 0;
    for (final well in activeWells) {
      for (final type in dueTypes) {
        totalDue++;
        if (controller.statusFor(well.id, type.id, now: today) == DailyStatus.done) totalDone++;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          name == null || name.isEmpty ? s('dashboardGreeting') : '${s('dashboardGreeting')}, $name',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(s('dashboardSummary'), style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        _ProgressBanner(done: totalDone, total: totalDue),
        const SizedBox(height: 20),
        if (totalDue == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(s('dashboardEmpty'), style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          )
        else
          for (final well in activeWells)
            _WellDashboardSection(well: well, dueTypes: dueTypes, today: today),
      ],
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  final int done;
  final int total;

  const _ProgressBanner({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 1.0 : done / total;
    final allDone = total > 0 && done == total;
    return Consumer(
      builder: (context, ref, _) {
        final locale = ref.watch(localeProvider);
        String s(String key) => tr(locale, key);
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accentColor, deepNavy],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                allDone ? s('dashboardAllDone') : '$done / $total',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WellDashboardSection extends ConsumerWidget {
  final Well well;
  final List<AnalysisType> dueTypes;
  final DateTime today;

  const _WellDashboardSection({required this.well, required this.dueTypes, required this.today});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => context.push('/wells/${well.id}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${well.name} · ${well.code}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
              const Divider(height: 18),
              for (final type in dueTypes)
                _AnalysisStatusRow(well: well, type: type, today: today),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalysisStatusRow extends ConsumerWidget {
  final Well well;
  final AnalysisType type;
  final DateTime today;

  const _AnalysisStatusRow({required this.well, required this.type, required this.today});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final status = controller.statusFor(well.id, type.id, now: today);
    final record = controller.todayRecord(well.id, type.id, now: today);

    late final Color color;
    late final IconData icon;
    late final String label;
    switch (status) {
      case DailyStatus.done:
        color = Colors.green.shade600;
        icon = Icons.check_circle_outline;
        label = s('dashboardDone');
        break;
      case DailyStatus.pending:
        color = accentColor;
        icon = Icons.hourglass_empty_rounded;
        label = s('dashboardPending');
        break;
      case DailyStatus.overdue:
        color = scheme.error;
        icon = Icons.warning_amber_rounded;
        label = s('dashboardOverdue');
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s(type.labelKey)} (${type.unit})', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (status == DailyStatus.done && record != null)
                  Text(
                    '${record.value} ${type.unit} · ${s('dashboardDoneBy')} ${record.operatorName}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (status == DailyStatus.done || !role.canEnterData)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
              child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
            )
          else
            OutlinedButton(
              onPressed: () => context.push('/entry?wellId=${well.id}&typeId=${type.id}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
