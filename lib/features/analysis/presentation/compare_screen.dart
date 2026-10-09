import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/analysis/metrics.dart';
import '../../../core/analysis/production_metrics.dart';
import '../../../core/analysis/series.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/filters/well_filter.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/intervention.dart';
import '../../../core/models/production_types.dart';
import '../../../core/models/well.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/series_chart.dart';
import '../../../core/widgets/responsive.dart';

enum CompareMode { wells, periods }

const _colorA = Color(0xFF1E88E5);
const _colorB = accentColor;
const _msPerDay = 86400000.0;

/// Sentinelle "dates libres" (pas d'intervention comme point de bascule).
const _freeDates = '__free__';

/// Comparaison d'un paramètre (débit, BSW, GOR...) entre deux puits sur une
/// même période, ou pour un même puits entre deux périodes — en particulier
/// avant/après une intervention.
class CompareScreen extends ConsumerStatefulWidget {
  final CompareMode initialMode;
  final String? initialWellA;
  final String? initialWellB;
  final String? initialMetric;
  final String? initialInterventionId;

  const CompareScreen({
    super.key,
    this.initialMode = CompareMode.wells,
    this.initialWellA,
    this.initialWellB,
    this.initialMetric,
    this.initialInterventionId,
  });

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  late CompareMode _mode = widget.initialMode;
  String? _metricKey;
  String? _wellA;
  String? _wellB;
  PeriodSelection _period = PeriodSelection.days30;

  // Mode "deux périodes".
  String _pivot = _freeDates; // id d'intervention, ou _freeDates
  int _windowDays = 30;
  late DateTimeRange _rangeA;
  late DateTimeRange _rangeB;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _rangeB = DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
    _rangeA = DateTimeRange(
      start: today.subtract(const Duration(days: 59)),
      end: today.subtract(const Duration(days: 30)),
    );
    _metricKey = widget.initialMetric;
    _wellA = widget.initialWellA;
    _wellB = widget.initialWellB;
    if (widget.initialInterventionId != null) _pivot = widget.initialInterventionId!;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final wells = [...data.wells]..sort((a, b) => a.name.compareTo(b.name));
    if (wells.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text(s('compareTitle'))), body: Center(child: Text(s('wellsEmpty'))));
    }
    final options = metricOptions(data, s);
    final metric = findMetric(options, _metricKey) ??
        findMetric(options, MetricOption.typeKey(oilFlowTypeId)) ??
        options.first;

    final wellA = controller.findWell(_wellA ?? '') ?? wells.first;
    final wellB = controller.findWell(_wellB ?? '') ??
        wells.firstWhere((w) => w.id != wellA.id, orElse: () => wells.first);

    final interventions = controller.interventionsForWell(wellA.id);
    final pivot = _pivot == _freeDates ? null : controller.findIntervention(_pivot);
    // Une intervention d'un autre puits (puits changé après coup) ne sert pas
    // de bascule.
    final activePivot = pivot != null && pivot.wellId == wellA.id ? pivot : null;

    final comparison = _mode == CompareMode.wells
        ? _compareWells(data, metric, wellA, wellB, s)
        : _comparePeriods(data, metric, wellA, activePivot, s, locale);

    return Scaffold(
      appBar: AppBar(
        title: Text(s('compareTitle')),
        actions: [
          IconButton(
            tooltip: s('exportTooltip'),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _export(comparison, metric, s, locale),
          ),
        ],
      ),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 32),
        children: [
          SegmentedButton<CompareMode>(
            segments: [
              ButtonSegment(
                value: CompareMode.wells,
                icon: const Icon(Icons.water_drop_outlined),
                label: Text(s('compareModeWells')),
              ),
              ButtonSegment(
                value: CompareMode.periods,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(s('compareModePeriods')),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (sel) => setState(() => _mode = sel.first),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterPill<String>(
                icon: Icons.show_chart,
                title: s('compareMetric'),
                options: [for (final o in options) PillOption(o.key, '${o.label} (${o.unit})')],
                selected: metric.key,
                active: true,
                onSelected: (v) => setState(() => _metricKey = v),
              ),
              if (_mode == CompareMode.wells) ...[
                _wellPill(s('compareWellA'), wellA, wells, _colorA, (id) => setState(() => _wellA = id)),
                _wellPill(s('compareWellB'), wellB, wells, _colorB, (id) => setState(() => _wellB = id)),
                PeriodPill(
                  value: _period,
                  title: s('filterPeriod'),
                  s: s,
                  onChanged: (p) => setState(() => _period = p),
                ),
              ] else ...[
                _wellPill(s('filterWell'), wellA, wells, null, (id) {
                  setState(() {
                    _wellA = id;
                    _pivot = _freeDates;
                  });
                }),
                FilterPill<String>(
                  icon: Icons.construction,
                  title: s('comparePivot'),
                  options: [
                    PillOption(_freeDates, s('compareFreeDates')),
                    for (final i in interventions)
                      PillOption(
                        i.id,
                        '${s(i.typeKey)} · ${DateFormat('dd/MM/yy').format(i.date)}',
                      ),
                  ],
                  selected: activePivot?.id ?? _freeDates,
                  active: activePivot != null,
                  onSelected: (v) => setState(() => _pivot = v),
                ),
                if (activePivot != null)
                  FilterPill<int>(
                    icon: Icons.width_normal_outlined,
                    title: s('compareWindow'),
                    options: [
                      for (final d in const [7, 15, 30, 60, 90]) PillOption(d, '± $d ${s('daysShort')}'),
                    ],
                    selected: _windowDays,
                    onSelected: (v) => setState(() => _windowDays = v),
                  ),
              ],
            ],
          ),
          if (_mode == CompareMode.periods && activePivot == null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _rangeButton(s('comparePeriodA'), _rangeA, _colorA, (r) => setState(() => _rangeA = r))),
                const SizedBox(width: 10),
                Expanded(child: _rangeButton(s('comparePeriodB'), _rangeB, _colorB, (r) => setState(() => _rangeB = r))),
              ],
            ),
          ],
          if (_mode == CompareMode.periods && interventions.isEmpty) ...[
            const SizedBox(height: 10),
            Text(s('compareNoInterventionHint'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '${metric.label} (${metric.unit})',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (comparison.a.length + comparison.b.length < 2)
                    SizedBox(
                      height: 140,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            metric.ratio == DerivedRatio.pi ? s('piMissingInputs') : s('compareNoData'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    SeriesChart(
                      series: [
                        ChartSeries(label: comparison.labelA, color: _colorA, points: comparison.chartA),
                        ChartSeries(label: comparison.labelB, color: _colorB, points: comparison.chartB),
                      ],
                      markers: comparison.markers,
                      xLabel: comparison.xLabel,
                    ),
                    const SizedBox(height: 10),
                    ChartLegend(entries: [
                      (comparison.labelA, _colorA, false),
                      (comparison.labelB, _colorB, false),
                      if (comparison.markers.isNotEmpty) (s('interventionsTitle'), interventionMarkerColor, true),
                    ]),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StatsTable(comparison: comparison, unit: metric.unit, s: s),
          if (comparison.verdict != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.insights, color: accentColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(comparison.verdict!, style: const TextStyle(fontSize: 13, height: 1.35))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Sélecteur de puits ; [color] ajoute la pastille de la courbe (A/B).
  Widget _wellPill(String title, Well well, List<Well> wells, Color? color, ValueChanged<String> onSelected) {
    final pill = FilterPill<String>(
      icon: Icons.water_drop_outlined,
      title: title,
      options: [for (final w in wells) PillOption(w.id, '${w.name} (${w.code})')],
      selected: well.id,
      active: true,
      onSelected: onSelected,
    );
    return color == null ? pill : pill.withColorDot(color);
  }

  Widget _rangeButton(String label, DateTimeRange range, Color color, ValueChanged<DateTimeRange> onChanged) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await pickDateRange(context, initial: range);
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(formatRange(range), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  _Comparison _compareWells(WellsState data, MetricOption metric, Well a, Well b, String Function(String) s) {
    final range = _period.resolve(DateTime.now());
    final pointsA = clipToRange(metricSeries(data, a.id, metric), range.start, range.end);
    final pointsB = clipToRange(metricSeries(data, b.id, metric), range.start, range.end);
    final controller = ref.read(wellsControllerProvider.notifier);
    final markers = [
      for (final i in [...controller.interventionsForWell(a.id), ...controller.interventionsForWell(b.id)])
        if (!i.date.isBefore(range.start) && !i.date.isAfter(range.end))
          ChartMarker.at(
            i.date,
            label: '${i.wellId == a.id ? 'A' : 'B'} · ${s(i.typeKey)}',
            color: interventionMarkerColor,
          ),
    ];
    final dateFormat = DateFormat('d MMM', ref.read(localeProvider).languageCode);
    final statsA = SeriesStats.of(pointsA);
    final statsB = SeriesStats.of(pointsB);
    String? verdict;
    if (statsA != null && statsB != null) {
      final diff = percentChange(statsA.mean, statsB.mean);
      if (diff != null) {
        verdict = fill(s('compareVerdictWells'), {
          'period': periodLabel(_period, s),
          'a': a.name,
          'b': b.name,
          'diff': formatPercent(diff.abs()).replaceAll('+', ''),
          'dir': s(diff >= 0 ? 'compareHigher' : 'compareLower'),
        });
      }
    }
    return _Comparison(
      labelA: '${a.name} (A)',
      labelB: '${b.name} (B)',
      a: pointsA,
      b: pointsB,
      chartA: [for (final p in pointsA) ChartPoint(p.t.millisecondsSinceEpoch.toDouble(), p.v)],
      chartB: [for (final p in pointsB) ChartPoint(p.t.millisecondsSinceEpoch.toDouble(), p.v)],
      markers: markers,
      xLabel: (x) => dateFormat.format(DateTime.fromMillisecondsSinceEpoch(x.round())),
      statsA: statsA,
      statsB: statsB,
      verdict: verdict,
      exportName: '${a.code}_vs_${b.code}',
      descriptionA: '${a.name} (${a.code}) · ${formatRange(range)}',
      descriptionB: '${b.name} (${b.code}) · ${formatRange(range)}',
    );
  }

  _Comparison _comparePeriods(
    WellsState data,
    MetricOption metric,
    Well well,
    Intervention? pivot,
    String Function(String) s,
    Locale locale,
  ) {
    final all = metricSeries(data, well.id, metric);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    late DateTimeRange rangeA;
    late DateTimeRange rangeB;
    late DateTime originA;
    late DateTime originB;
    if (pivot != null) {
      final d = dayOf(pivot.date);
      rangeA = DateTimeRange(start: d.subtract(Duration(days: _windowDays)), end: d.subtract(const Duration(days: 1)));
      var afterEnd = d.add(Duration(days: _windowDays));
      if (afterEnd.isAfter(today)) afterEnd = today;
      final afterStart = d.add(const Duration(days: 1));
      rangeB = DateTimeRange(start: afterStart, end: afterEnd.isBefore(afterStart) ? afterStart : afterEnd);
      // Axe commun "jours par rapport à l'intervention" (J−n … J+n).
      originA = d;
      originB = d;
    } else {
      rangeA = _rangeA;
      rangeB = _rangeB;
      // Périodes libres : superposées, chacune à partir de son premier jour.
      originA = rangeA.start;
      originB = rangeB.start;
    }

    final pointsA = clipToRange(all, rangeA.start, rangeA.end);
    final pointsB = clipToRange(all, rangeB.start, rangeB.end);
    double offset(DateTime t, DateTime origin) => t.difference(origin).inMilliseconds / _msPerDay;

    final statsA = SeriesStats.of(pointsA);
    final statsB = SeriesStats.of(pointsB);
    String? verdict;
    if (statsA != null && statsB != null) {
      final diff = percentChange(statsA.mean, statsB.mean);
      final abs = statsB.mean - statsA.mean;
      if (diff != null) {
        final change = '${formatPercent(diff)} (${abs >= 0 ? '+' : ''}${formatNumber(abs)} ${metric.unit})';
        verdict = pivot != null
            ? fill(s('compareVerdictIntervention'), {
                'type': s(pivot.typeKey).toLowerCase(),
                'date': DateFormat('d MMM yyyy', locale.languageCode).format(pivot.date),
                'metric': metric.label,
                'change': change,
              })
            : fill(s('compareVerdictPeriods'), {'metric': metric.label, 'change': change});
      }
    }

    return _Comparison(
      labelA: pivot != null ? s('compareBefore') : '${s('comparePeriodA')} · ${formatRange(rangeA)}',
      labelB: pivot != null ? s('compareAfter') : '${s('comparePeriodB')} · ${formatRange(rangeB)}',
      a: pointsA,
      b: pointsB,
      chartA: [for (final p in pointsA) ChartPoint(offset(p.t, originA), p.v)],
      chartB: [for (final p in pointsB) ChartPoint(offset(p.t, originB), p.v)],
      markers: pivot != null ? [ChartMarker(x: 0, label: s(pivot.typeKey), color: interventionMarkerColor)] : const [],
      xLabel: (x) {
        final d = x.round();
        if (pivot == null) return '${s('dayPrefix')}+$d';
        return d == 0 ? s('dayPrefix') : '${s('dayPrefix')}${d > 0 ? '+' : ''}$d';
      },
      statsA: statsA,
      statsB: statsB,
      verdict: verdict,
      exportName: '${well.code}_${pivot != null ? 'avant_apres' : 'periodes'}',
      descriptionA: '${well.name} · ${formatRange(rangeA)}',
      descriptionB: '${well.name} · ${formatRange(rangeB)}',
    );
  }

  void _export(_Comparison c, MetricOption metric, String Function(String) s, Locale locale) {
    final rows = <List<Object?>>[
      [s('compareStatPeriod'), c.descriptionA, c.descriptionB, ''],
      for (final (label, f) in _statRows(s))
        [
          label,
          c.statsA == null ? null : (label == s('compareStatCount') ? c.statsA!.count : roundTo(f(c.statsA!), 4)),
          c.statsB == null ? null : (label == s('compareStatCount') ? c.statsB!.count : roundTo(f(c.statsB!), 4)),
          (c.statsA != null && c.statsB != null && label != s('compareStatCount'))
              ? () {
                  final d = percentChange(f(c.statsA!), f(c.statsB!));
                  return d == null ? null : roundTo(d, 2);
                }()
              : null,
        ],
    ];
    runExport(
      context: context,
      locale: locale,
      baseName: 'comparaison_${c.exportName}',
      shareSubject: '${s('compareTitle')} · ${metric.label}',
      tables: [
        ExportTable(
          name: s('exportSheetSummary'),
          headers: [
            '${metric.label} (${metric.unit})',
            c.labelA,
            c.labelB,
            s('compareDeltaPct'),
          ],
          rows: [
            ...rows,
            if (c.verdict != null) [c.verdict, null, null, null],
          ],
        ),
        ExportTable(
          name: s('exportSheetData'),
          headers: [s('compareSeries'), s('colDate'), '${metric.label} (${metric.unit})'],
          rows: [
            for (final p in c.a) [c.labelA, p.t, p.v],
            for (final p in c.b) [c.labelB, p.t, p.v],
          ],
        ),
      ],
    );
  }
}

List<(String, double Function(SeriesStats))> _statRows(String Function(String) s) => [
      (s('compareStatCount'), (st) => st.count.toDouble()),
      (s('compareStatMean'), (st) => st.mean),
      (s('compareStatMin'), (st) => st.min),
      (s('compareStatMax'), (st) => st.max),
      (s('compareStatFirst'), (st) => st.first),
      (s('compareStatLast'), (st) => st.last),
    ];

class _Comparison {
  final String labelA;
  final String labelB;
  final List<SeriesPoint> a;
  final List<SeriesPoint> b;
  final List<ChartPoint> chartA;
  final List<ChartPoint> chartB;
  final List<ChartMarker> markers;
  final String Function(double) xLabel;
  final SeriesStats? statsA;
  final SeriesStats? statsB;
  final String? verdict;
  final String exportName;
  final String descriptionA;
  final String descriptionB;

  const _Comparison({
    required this.labelA,
    required this.labelB,
    required this.a,
    required this.b,
    required this.chartA,
    required this.chartB,
    required this.markers,
    required this.xLabel,
    required this.statsA,
    required this.statsB,
    required this.verdict,
    required this.exportName,
    required this.descriptionA,
    required this.descriptionB,
  });
}

class _StatsTable extends StatelessWidget {
  final _Comparison comparison;
  final String unit;
  final String Function(String) s;

  const _StatsTable({required this.comparison, required this.unit, required this.s});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = comparison.statsA;
    final b = comparison.statsB;
    const headerStyle = TextStyle(fontWeight: FontWeight.w800, fontSize: 12);

    Widget cell(String text, {Color? color, FontWeight weight = FontWeight.w600, TextAlign align = TextAlign.right}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text(text, textAlign: align, style: TextStyle(fontSize: 12.5, fontWeight: weight, color: color)),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Table(
          columnWidths: const {0: FlexColumnWidth(1.3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(0.9)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
              children: [
                cell(unit, align: TextAlign.left, color: scheme.onSurfaceVariant),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(comparison.labelA, textAlign: TextAlign.right, style: headerStyle.copyWith(color: _colorA), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(comparison.labelB, textAlign: TextAlign.right, style: headerStyle.copyWith(color: _colorB), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(s('compareDeltaPct'), textAlign: TextAlign.right, style: headerStyle),
                ),
              ],
            ),
            for (final (label, f) in _statRows(s))
              TableRow(
                children: [
                  cell(label, align: TextAlign.left, weight: FontWeight.w500, color: scheme.onSurfaceVariant),
                  cell(a == null ? '—' : (label == s('compareStatCount') ? '${a.count}' : formatNumber(f(a)))),
                  cell(b == null ? '—' : (label == s('compareStatCount') ? '${b.count}' : formatNumber(f(b)))),
                  () {
                    if (a == null || b == null || label == s('compareStatCount')) return cell('');
                    final d = percentChange(f(a), f(b));
                    if (d == null) return cell('—');
                    final color = d > 0.5
                        ? Colors.green.shade700
                        : d < -0.5
                            ? scheme.error
                            : scheme.onSurfaceVariant;
                    return cell(formatPercent(d), color: color, weight: FontWeight.w800);
                  }(),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

extension on FilterPill<String> {
  /// Ajoute une pastille de couleur devant le filtre (identifie la courbe A/B).
  Widget withColorDot(Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          this,
        ],
      );
}
