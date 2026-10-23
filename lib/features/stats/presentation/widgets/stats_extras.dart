import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/wells_repository.dart';
import '../../../../core/filters/well_filter.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/models/analysis_type.dart';
import '../../../../core/widgets/filter_pills.dart';
import '../../../../core/widgets/modern_widgets.dart';
import '../../../../core/widgets/series_chart.dart';

/// Totaux (analyses, hors-limites) des puits retenus par [filter] sur une
/// plage de jours.
({int total, int out}) _totals(WellsController controller, WellFilter filter, DateTimeRange range) {
  var total = 0;
  var out = 0;
  for (final g in controller.statsForPeriod(range.start, range.end)) {
    for (final w in g.wells.where((w) => filter.matches(w.well))) {
      total += w.totalRecords;
      out += w.outOfRangeCount;
    }
  }
  return (total: total, out: out);
}

/// Comparaison de la période choisie avec la période précédente de même
/// durée : nombre d'analyses, hors-limites et taux de conformité, avec
/// flèches de tendance. Masquée pour « tout l'historique ».
class PeriodComparisonCard extends ConsumerWidget {
  final WellFilter filter;
  const PeriodComparisonCard({super.key, required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (filter.period.preset == PeriodPreset.all) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    ref.watch(wellsControllerProvider);
    String s(String key) => tr(locale, key);

    final range = filter.period.resolve(DateTime.now());
    final days = range.end.difference(range.start).inDays + 1;
    final prevEnd = range.start.subtract(const Duration(days: 1));
    final prev = DateTimeRange(start: prevEnd.subtract(Duration(days: days - 1)), end: prevEnd);
    final cur = _totals(controller, filter, range);
    final old = _totals(controller, filter, prev);
    if (cur.total == 0 && old.total == 0) return const SizedBox.shrink();

    double rate(({int total, int out}) t) => t.total == 0 ? 1 : (t.total - t.out) / t.total;
    final curRate = rate(cur) * 100;
    final oldRate = rate(old) * 100;
    final fmt = DateFormat('d MMM', locale.languageCode);

    String pct(num now, num before) {
      if (before == 0) return now == 0 ? '0 %' : '+${now.round()}';
      final p = (now - before) / before * 100;
      return '${p > 0 ? '+' : ''}${p.round()} %';
    }

    Widget tile({
      required String label,
      required String value,
      required String previous,
      required double delta,
      required String deltaText,
      bool goodWhenUp = true,
    }) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            AnimatedNumberText(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: TrendBadge(delta: delta, text: deltaText, goodWhenUp: goodWhenUp),
            ),
            const SizedBox(height: 2),
            Text(previous, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(s('statsVsPrevious'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${fmt.format(range.start)} – ${fmt.format(range.end)}  ·  ${fmt.format(prev.start)} – ${fmt.format(prev.end)}',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tile(
                  label: s('statsAnalysesCount'),
                  value: '${cur.total}',
                  previous: '${s('statsPrevious')} ${old.total}',
                  delta: (cur.total - old.total).toDouble(),
                  deltaText: pct(cur.total, old.total),
                ),
                const SizedBox(width: 10),
                tile(
                  label: s('statsOutOfRangeCount'),
                  value: '${cur.out}',
                  previous: '${s('statsPrevious')} ${old.out}',
                  delta: (cur.out - old.out).toDouble(),
                  deltaText: pct(cur.out, old.out),
                  goodWhenUp: false,
                ),
                const SizedBox(width: 10),
                tile(
                  label: s('statsCompliance'),
                  value: '${curRate.round()} %',
                  previous: '${s('statsPrevious')} ${oldRate.round()} %',
                  delta: curRate - oldRate,
                  deltaText: '${curRate - oldRate >= 0 ? '+' : ''}${(curRate - oldRate).toStringAsFixed(1)} pt',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _wellColors = [
  Color(0xFF1E88E5),
  Color(0xFFE53935),
  Color(0xFF2E7D32),
  Color(0xFFF9A825),
  Color(0xFF8E24AA),
  Color(0xFF00897B),
];

/// Courbes de plusieurs puits (jusqu'à 6) superposées pour un même
/// paramètre sur la période choisie, avec la plage de seuils en fond.
class WellsOverlayView extends ConsumerStatefulWidget {
  final WellFilter filter;
  const WellsOverlayView({super.key, required this.filter});

  @override
  ConsumerState<WellsOverlayView> createState() => _WellsOverlayViewState();
}

class _WellsOverlayViewState extends ConsumerState<WellsOverlayView> {
  String? _typeId;
  final _wellIds = <String>{};
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final types = data.analysisTypes;
    final wells = data.wells.where((w) => w.active && widget.filter.matches(w)).toList();
    if (types.isEmpty || wells.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(child: Text(s('statsNoData'), style: TextStyle(color: scheme.onSurfaceVariant))),
      );
    }
    final AnalysisType type = types.firstWhere((t) => t.id == _typeId, orElse: () => types.first);
    final range = widget.filter.period.resolve(DateTime.now());
    final startDay = DateTime(range.start.year, range.start.month, range.start.day);
    final endDay = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);

    List<ChartPoint> pointsOf(String wellId) {
      final recs =
          controller
              .recordsForWell(wellId)
              .where((r) => r.typeId == type.id && !r.dateTime.isBefore(startDay) && !r.dateTime.isAfter(endDay))
              .toList()
            ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
      return [for (final r in recs) ChartPoint(r.dateTime.millisecondsSinceEpoch.toDouble(), r.value)];
    }

    if (!_initialized) {
      _initialized = true;
      // Par défaut : les 3 premiers puits qui ont des mesures pour ce paramètre.
      for (final w in wells) {
        if (_wellIds.length >= 3) break;
        if (pointsOf(w.id).isNotEmpty) _wellIds.add(w.id);
      }
    }
    final selected = [for (final w in wells) if (_wellIds.contains(w.id)) w];
    final series = <ChartSeries>[];
    final legend = <(String, Color, bool)>[];
    for (var i = 0; i < selected.length; i++) {
      final color = _wellColors[i % _wellColors.length];
      final pts = pointsOf(selected[i].id);
      if (pts.isEmpty) continue;
      series.add(ChartSeries(label: selected[i].name, color: color, points: pts));
      legend.add((selected[i].name, color, false));
    }
    final dateFmt = DateFormat('d MMM', locale.languageCode);
    String num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterPill<String>(
              icon: Icons.show_chart,
              title: s('compareMetric'),
              options: [for (final t in types) PillOption(t.id, '${t.label} (${t.unit})')],
              selected: type.id,
              active: true,
              onSelected: (v) => setState(() => _typeId = v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(s('statsOverlayPick'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final w in wells)
              FilterChip(
                label: Text(w.name),
                selected: _wellIds.contains(w.id),
                showCheckmark: false,
                avatar: _wellIds.contains(w.id)
                    ? CircleAvatar(
                        radius: 6,
                        backgroundColor: _wellColors[selected.indexWhere((x) => x.id == w.id) % _wellColors.length],
                      )
                    : null,
                onSelected: (v) => setState(() {
                  if (v) {
                    if (_wellIds.length < _wellColors.length) _wellIds.add(w.id);
                  } else {
                    _wellIds.remove(w.id);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('${type.label} (${type.unit})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                const SizedBox(height: 10),
                if (series.isEmpty)
                  SizedBox(
                    height: 140,
                    child: Center(child: Text(s('compareNoData'), style: TextStyle(color: scheme.onSurfaceVariant))),
                  )
                else ...[
                  SeriesChart(
                    series: series,
                    xLabel: (x) => dateFmt.format(DateTime.fromMillisecondsSinceEpoch(x.round())),
                    yLabel: num,
                    band: (type.min, type.max),
                  ),
                  const SizedBox(height: 10),
                  ChartLegend(entries: legend),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
