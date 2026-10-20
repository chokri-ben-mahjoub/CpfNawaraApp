import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/stock_repository.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/pdf_chart.dart';
import '../../../core/export/report_tables.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/analysis_type.dart';
import '../../../core/models/production_types.dart';
import '../../../core/models/user_role.dart';
import '../../../core/models/well.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import 'widgets/aggregate_trend_chart.dart';
import '../../../core/widgets/profile_avatar.dart';

enum DashboardPeriod { day, week, month }

enum ProductionMetric { oil, gas, water }

final dashboardPeriodProvider = StateProvider<DashboardPeriod>((ref) => DashboardPeriod.day);

final dashboardTrendMetricProvider = StateProvider<ProductionMetric>((ref) => ProductionMetric.oil);

/// Début de la période (inclus) pour une vue jour/semaine/mois, la fin étant
/// toujours "aujourd'hui" (on ne calcule que ce qui est déjà passé).
DateTime periodStart(DashboardPeriod period, DateTime today) {
  switch (period) {
    case DashboardPeriod.day:
      return today;
    case DashboardPeriod.week:
      return today.subtract(Duration(days: today.weekday - 1));
    case DashboardPeriod.month:
      return DateTime(today.year, today.month, 1);
  }
}

/// Exporte les analyses de tous les puits sur la période actuellement
/// sélectionnée dans le tableau de bord (jour/semaine/mois), avec la
/// production + ratios et les interventions de la même période.
Future<void> exportDashboardPeriod(WidgetRef ref, BuildContext context) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);

  final data = ref.read(wellsControllerProvider);
  final period = ref.read(dashboardPeriodProvider);
  final today = DateTime.now();
  final start = periodStart(period, today);
  final startDay = DateTime(start.year, start.month, start.day);

  await runExport(
    context: context,
    locale: locale,
    baseName: 'analyses_${s(_periodKey(period))}',
    tables: [
      analysesTable(data, data.records.where((r) => !r.dateTime.isBefore(startDay)).toList(), s, includeWell: true),
      productionTable(data, data.wells, s, from: startDay),
      interventionsTable(data, data.interventions.where((i) => !i.date.isBefore(startDay)).toList(), s),
    ],
    charts: _dashboardCharts(ref, data, startDay, today, s),
  );
}

/// Courbe de production totale (tous puits actifs) pour chaque débit, sur la
/// période exportée — affichées en tête du PDF, avant les tableaux détaillés.
List<PdfReportChart> _dashboardCharts(
  WidgetRef ref,
  WellsState data,
  DateTime startDay,
  DateTime today,
  String Function(String) s,
) {
  final controller = ref.read(wellsControllerProvider.notifier);
  final days = today.difference(startDay).inDays + 1;
  String unitFor(String typeId) => data.analysisTypes.where((t) => t.id == typeId).map((t) => t.unit).firstOrNull ?? '';

  final metrics = [
    (oilFlowTypeId, s('productionOil'), const PdfColor.fromInt(0xFF2E7D32)),
    (gasFlowTypeId, s('productionGas'), const PdfColor.fromInt(0xFFE53935)),
    (waterFlowTypeId, s('productionWater'), const PdfColor.fromInt(0xFF1E88E5)),
  ];

  return [
    for (final (typeId, label, color) in metrics)
      PdfReportChart(
        title: '$label (${unitFor(typeId)})',
        series: [
          PdfChartSeries(
            label: label,
            color: color,
            points: [for (final (day, total) in controller.aggregateDailyTotals(typeId, days: days)) (day, total)],
          ),
        ],
      ),
  ];
}

String _periodKey(DashboardPeriod period) {
  switch (period) {
    case DashboardPeriod.day:
      return 'dashboardPeriodDay';
    case DashboardPeriod.week:
      return 'dashboardPeriodWeek';
    case DashboardPeriod.month:
      return 'dashboardPeriodMonth';
  }
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final name = ref.watch(profileProvider)?.fullName;
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    final period = ref.watch(dashboardPeriodProvider);
    String s(String key) => tr(locale, key);

    final today = DateTime.now();
    final activeWells = data.wells.where((w) => w.active).toList();

    return ListView(
      padding: pagePadding(context, top: 8, bottom: 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name == null || name.isEmpty ? s('dashboardGreeting') : '${s('dashboardGreeting')}, $name',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(s('dashboardSummary'), style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const ProfileAvatar(radius: 26, editable: true),
          ],
        ),
        const _LowStockBanner(),
        const SizedBox(height: 16),
        SegmentedButton<DashboardPeriod>(
          segments: [
            ButtonSegment(value: DashboardPeriod.day, label: Text(s('dashboardPeriodDay'))),
            ButtonSegment(value: DashboardPeriod.week, label: Text(s('dashboardPeriodWeek'))),
            ButtonSegment(value: DashboardPeriod.month, label: Text(s('dashboardPeriodMonth'))),
          ],
          selected: {period},
          onSelectionChanged: (selection) =>
              ref.read(dashboardPeriodProvider.notifier).state = selection.first,
        ),
        const SizedBox(height: 16),
        const _ProductionTrendCard(),
        const SizedBox(height: 16),
        if (period == DashboardPeriod.day)
          _DayView(wells: activeWells, data: data, controller: controller, today: today)
        else
          _PeriodView(
            wells: activeWells,
            controller: controller,
            start: periodStart(period, today),
            end: today,
          ),
      ],
    );
  }
}

/// Bandeau d'alerte si un ou plusieurs articles de stock sont passés sous
/// leur seuil (voir `stock_repository.dart`) — mène directement à l'écran
/// Stock, où ils sont mis en avant dans la section "En alerte".
class _LowStockBanner extends ConsumerWidget {
  const _LowStockBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final lowCount = ref.watch(stockControllerProvider.select((s) => s.lowStockItems.length));
    String s(String key) => tr(locale, key);
    if (lowCount == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                lowCount == 1 ? s('stockBannerMessageOne') : fill(s('stockBannerMessageMany'), {'n': '$lowCount'}),
                style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => context.push('/stock'),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              child: Text(s('stockBannerAction'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vue d'ensemble ("vue haute") : tendance de la production totale (tous
/// puits actifs confondus) sur les 7 derniers jours, pour le paramètre
/// choisi (huile/gaz/eau) — un coup d'œil sur l'évolution générale, sans
/// entrer dans le détail puits par puits.
class _ProductionTrendCard extends ConsumerWidget {
  const _ProductionTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    final metric = ref.watch(dashboardTrendMetricProvider);
    String s(String key) => tr(locale, key);

    AnalysisType? typeOf(String id) {
      for (final t in data.analysisTypes) {
        if (t.id == id) return t;
      }
      return null;
    }

    final metrics = [
      (ProductionMetric.oil, oilFlowTypeId, s('productionOil'), const Color(0xFF2E7D32)),
      (ProductionMetric.gas, gasFlowTypeId, s('productionGas'), const Color(0xFFE53935)),
      (ProductionMetric.water, waterFlowTypeId, s('productionWater'), const Color(0xFF1E88E5)),
    ].where((m) => typeOf(m.$2) != null).toList();

    if (metrics.isEmpty || data.wells.every((w) => !w.active)) return const SizedBox.shrink();

    final selected = metrics.firstWhere((m) => m.$1 == metric, orElse: () => metrics.first);
    final type = typeOf(selected.$2)!;
    final points = controller.aggregateDailyTotals(selected.$2, days: 7);
    final hasData = points.any((p) => p.$2 > 0);
    final latest = points.isEmpty ? 0.0 : points.last.$2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s('dashboardTrendTitle'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final m in metrics)
                  ChoiceChip(
                    label: Text(m.$3),
                    selected: m.$1 == metric,
                    onSelected: (_) => ref.read(dashboardTrendMetricProvider.notifier).state = m.$1,
                    selectedColor: m.$4.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      color: m.$1 == metric ? m.$4 : scheme.onSurfaceVariant,
                      fontWeight: m.$1 == metric ? FontWeight.w700 : FontWeight.w500,
                    ),
                    side: BorderSide(color: m.$1 == metric ? m.$4 : scheme.outlineVariant),
                    backgroundColor: scheme.surface,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (!hasData)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(s('dashboardTrendNoData'), style: TextStyle(color: scheme.onSurfaceVariant)),
              )
            else ...[
              Text(
                '${latest.toStringAsFixed(1)} ${type.unit}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: selected.$4),
              ),
              Text(s('dashboardTrendSubtitle'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 6),
              AggregateTrendChart(points: points, color: selected.$4),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayView extends StatelessWidget {
  final List<Well> wells;
  final WellsState data;
  final WellsController controller;
  final DateTime today;

  const _DayView({required this.wells, required this.data, required this.controller, required this.today});

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final locale = ref.watch(localeProvider);
      String s(String key) => tr(locale, key);
      final dueTypes = data.analysisTypes.where((t) => t.isDueOn(today)).toList();

      var totalDue = 0;
      var totalDone = 0;
      var totalOverdue = 0;
      final overdueByWell = <String, int>{};
      final openByWell = <String, int>{};
      for (final well in wells) {
        for (final type in dueTypes) {
          totalDue++;
          switch (controller.statusFor(well.id, type.id, now: today)) {
            case DailyStatus.done:
              totalDone++;
            case DailyStatus.overdue:
              totalOverdue++;
              overdueByWell[well.id] = (overdueByWell[well.id] ?? 0) + 1;
              openByWell[well.id] = (openByWell[well.id] ?? 0) + 1;
            case DailyStatus.pending:
              openByWell[well.id] = (openByWell[well.id] ?? 0) + 1;
          }
        }
      }
      final totalPending = totalDue - totalDone - totalOverdue;
      // Les puits qui demandent encore du travail d'abord, les retards en tête.
      final sortedWells = [...wells]
        ..sort((a, b) {
          final byOverdue = (overdueByWell[b.id] ?? 0).compareTo(overdueByWell[a.id] ?? 0);
          if (byOverdue != 0) return byOverdue;
          return (openByWell[b.id] ?? 0).compareTo(openByWell[a.id] ?? 0);
        });

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProgressBanner(done: totalDone, total: totalDue, allDoneKey: 'dashboardAllDone'),
          if (totalDue > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (totalOverdue > 0)
                  _CountChip(
                    label: fill(s('dashboardCountOverdue'), {'n': '$totalOverdue'}),
                    color: Theme.of(context).colorScheme.error,
                  ),
                if (totalPending > 0)
                  _CountChip(label: fill(s('dashboardCountPending'), {'n': '$totalPending'}), color: accentColor),
                _CountChip(
                  label: fill(s('dashboardCountDone'), {'n': '$totalDone'}),
                  color: Colors.green.shade600,
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          if (totalDue == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(s('dashboardEmpty'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            )
          else
            ResponsiveWrapGrid(
              spacing: 16,
              runSpacing: 0,
              minItemWidth: 420,
              maxColumns: 2,
              children: [
                for (final well in sortedWells) _WellDashboardSection(well: well, dueTypes: dueTypes, today: today),
              ],
            ),
        ],
      );
    });
  }
}

class _PeriodView extends ConsumerWidget {
  final List<Well> wells;
  final WellsController controller;
  final DateTime start;
  final DateTime end;

  const _PeriodView({required this.wells, required this.controller, required this.start, required this.end});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var totalDone = 0;
    var totalExpected = 0;
    final progresses = <Well, PeriodProgress>{};
    for (final well in wells) {
      final progress = controller.periodProgress(well.id, start, end);
      progresses[well] = progress;
      totalDone += progress.done;
      totalExpected += progress.total;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProgressBanner(done: totalDone, total: totalExpected, allDoneKey: 'dashboardPeriodAllDone'),
        const SizedBox(height: 20),
        ResponsiveWrapGrid(
          spacing: 16,
          runSpacing: 0,
          minItemWidth: 420,
          maxColumns: 2,
          children: [for (final well in wells) _PeriodWellCard(well: well, progress: progresses[well]!)],
        ),
      ],
    );
  }
}

class _PeriodWellCard extends ConsumerWidget {
  final Well well;
  final PeriodProgress progress;

  const _PeriodWellCard({required this.well, required this.progress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final dateFormat = DateFormat('d MMM', locale.languageCode);
    final ratio = progress.total == 0 ? 1.0 : progress.done / progress.total;
    final color = progress.missing.isEmpty ? Colors.green.shade600 : accentColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
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
                      child: Text('${well.name} · ${well.code}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text(
                      '${progress.done}/${progress.total} ${s('dashboardPeriodDone')}',
                      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHigh,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              if (progress.missing.isNotEmpty) ...[
                const Divider(height: 20),
                Text(s('dashboardMissingTitle'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                for (final item in progress.missing)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${item.type.label} — ${s('dashboardMissingExpectedOn')} ${dateFormat.format(item.date)}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  final int done;
  final int total;
  final String allDoneKey;

  const _ProgressBanner({required this.done, required this.total, required this.allDoneKey});

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
                allDone ? s(allDoneKey) : '$done / $total',
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
    final locale = ref.watch(localeProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final overdue = <AnalysisType>[];
    final pending = <AnalysisType>[];
    final done = <AnalysisType>[];
    for (final type in dueTypes) {
      switch (controller.statusFor(well.id, type.id, now: today)) {
        case DailyStatus.overdue:
          overdue.add(type);
        case DailyStatus.pending:
          pending.add(type);
        case DailyStatus.done:
          done.add(type);
      }
    }
    final open = [...overdue, ...pending];
    final allDone = open.isEmpty;
    final green = Colors.green.shade600;

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
                    if (allDone) ...[Icon(Icons.check_circle, color: green, size: 20), const SizedBox(width: 8)],
                    Expanded(
                      child: Text(
                        '${well.name} · ${well.code}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      allDone ? s('dashboardWellAllDone') : '${done.length}/${dueTypes.length}',
                      style: TextStyle(
                        color: allDone ? green : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    Icon(Icons.visibility_outlined, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
              if (open.isNotEmpty) ...[
                const Divider(height: 18),
                for (final type in open) _AnalysisStatusRow(well: well, type: type, today: today),
              ],
              if (done.isNotEmpty)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      fill(s('dashboardShowDone'), {'n': '${done.length}'}),
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    children: [for (final type in done) _AnalysisStatusRow(well: well, type: type, today: today)],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final Color color;

  const _CountChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
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
                Text('${type.label} (${type.unit})', style: const TextStyle(fontWeight: FontWeight.w600)),
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
