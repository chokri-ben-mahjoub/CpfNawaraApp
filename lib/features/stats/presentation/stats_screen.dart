import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/analysis_type.dart';
import '../../../core/models/well.dart';
import 'widgets/threshold_gauge.dart';

enum StatsPeriod { week, month, all }

enum StatsViewMode { compliance, thresholds }

final statsPeriodProvider = StateProvider<StatsPeriod>((ref) => StatsPeriod.week);

final statsViewModeProvider = StateProvider<StatsViewMode>((ref) => StatsViewMode.compliance);

DateTime _statsStart(StatsPeriod period, DateTime today) {
  switch (period) {
    case StatsPeriod.week:
      return today.subtract(const Duration(days: 6));
    case StatsPeriod.month:
      return today.subtract(const Duration(days: 29));
    case StatsPeriod.all:
      return DateTime(2000);
  }
}

Color _complianceColor(double rate) {
  if (rate >= 0.95) return Colors.green.shade600;
  if (rate >= 0.8) return Colors.orange.shade700;
  return Colors.red.shade600;
}

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final mode = ref.watch(statsViewModeProvider);
    ref.watch(wellsControllerProvider); // reconstruit après chaque nouvelle saisie
    String s(String key) => tr(locale, key);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SegmentedButton<StatsViewMode>(
          segments: [
            ButtonSegment(value: StatsViewMode.compliance, label: Text(s('statsModeCompliance'))),
            ButtonSegment(value: StatsViewMode.thresholds, label: Text(s('statsModeThresholds'))),
          ],
          selected: {mode},
          onSelectionChanged: (selection) => ref.read(statsViewModeProvider.notifier).state = selection.first,
        ),
        const SizedBox(height: 16),
        if (mode == StatsViewMode.compliance) const _ComplianceView() else const _ThresholdsView(),
      ],
    );
  }
}

class _ComplianceView extends ConsumerWidget {
  const _ComplianceView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final period = ref.watch(statsPeriodProvider);
    final controller = ref.watch(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final today = DateTime.now();
    final groups = controller.statsForPeriod(_statsStart(period, today), today);
    final hasAnyRecord = groups.any((g) => g.totalRecords > 0);

    return Column(
      children: [
        SegmentedButton<StatsPeriod>(
          segments: [
            ButtonSegment(value: StatsPeriod.week, label: Text(s('statsPeriod7'))),
            ButtonSegment(value: StatsPeriod.month, label: Text(s('statsPeriod30'))),
            ButtonSegment(value: StatsPeriod.all, label: Text(s('statsPeriodAll'))),
          ],
          selected: {period},
          onSelectionChanged: (selection) => ref.read(statsPeriodProvider.notifier).state = selection.first,
        ),
        const SizedBox(height: 16),
        if (!hasAnyRecord)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(child: Text(s('statsNoData'), style: TextStyle(color: scheme.onSurfaceVariant))),
          )
        else
          for (final group in groups)
            if (group.totalRecords > 0) _GroupStatsCard(group: group),
      ],
    );
  }
}

class _GroupStatsCard extends ConsumerWidget {
  final GroupStats group;
  const _GroupStatsCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final groupColor = _complianceColor(group.complianceRate);
    final groupLabel = group.group == unassignedGroupLabel ? s('statsUnassignedGroup') : group.group;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(groupLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: groupColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '${(group.complianceRate * 100).round()}% ${s('statsCompliance')}',
                      style: TextStyle(color: groupColor, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ],
              ),
              Text(
                '${group.totalRecords} ${s('statsAnalysesCount')} · ${group.outOfRangeCount} ${s('statsOutOfRangeCount')}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const Divider(height: 24),
              for (final wellStats in group.wells) _WellStatsRow(stats: wellStats),
            ],
          ),
        ),
      ),
    );
  }
}

class _WellStatsRow extends ConsumerWidget {
  final WellStats stats;
  const _WellStatsRow({required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final color = _complianceColor(stats.complianceRate);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${stats.well.name} (${stats.well.code})',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Text(
                '${stats.totalRecords} ${s('statsAnalysesCount')}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: stats.complianceRate,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vue "diagramme" des seuils : pour chaque puits actif, où se situe la
/// dernière valeur de chaque analyse par rapport à son seuil attendu — sans
/// notion de période, juste l'état actuel.
class _ThresholdsView extends ConsumerWidget {
  const _ThresholdsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.watch(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final activeWells = data.wells.where((w) => w.active).toList();
    final byGroup = <String, List<Well>>{};
    for (final well in activeWells) {
      final key = well.group.trim().isEmpty ? unassignedGroupLabel : well.group.trim();
      (byGroup[key] ??= []).add(well);
    }
    final groupNames = byGroup.keys.toList()..sort();
    for (final list in byGroup.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }

    final hasAnyData =
        activeWells.any((w) => data.analysisTypes.any((t) => controller.lastRecord(w.id, t.id) != null));

    if (!hasAnyData) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(child: Text(s('statsNoData'), style: TextStyle(color: scheme.onSurfaceVariant))),
      );
    }

    return Column(
      children: [
        for (final groupName in groupNames) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                groupName,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          for (final well in byGroup[groupName]!) _WellThresholdsCard(well: well),
        ],
      ],
    );
  }
}

class _WellThresholdsCard extends ConsumerWidget {
  final Well well;
  const _WellThresholdsCard({required this.well});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.watch(wellsControllerProvider.notifier);

    final rows = <(AnalysisType, double)>[];
    for (final type in data.analysisTypes) {
      final last = controller.lastRecord(well.id, type.id);
      if (last != null) rows.add((type, last.value));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${well.name} (${well.code})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 14),
              for (final (type, value) in rows) _ThresholdRow(type: type, value: value),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThresholdRow extends ConsumerWidget {
  final AnalysisType type;
  final double value;
  const _ThresholdRow({required this.type, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final outOfRange = type.isOutOfRange(value);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(type.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              Text(
                '$value ${type.unit}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: outOfRange ? scheme.error : scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ThresholdGauge(min: type.min, max: type.max, value: value),
          const SizedBox(height: 4),
          Text(
            '${type.min} – ${type.max} ${type.unit}',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
