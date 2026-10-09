import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/analysis/series.dart';
import '../../../core/filters/well_filter.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_catalog.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/series_chart.dart';

/// Courbe de tendance d'un paramètre pour un point, avec la bande de seuil
/// et les valeurs hors seuil.
class PlantTrendScreen extends ConsumerStatefulWidget {
  final String pointId;
  final String paramKey;
  const PlantTrendScreen({super.key, required this.pointId, required this.paramKey});

  @override
  ConsumerState<PlantTrendScreen> createState() => _PlantTrendScreenState();
}

class _PlantTrendScreenState extends ConsumerState<PlantTrendScreen> {
  PeriodSelection _period = PeriodSelection.days90;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final point = controller.point(widget.pointId);
    PlantParam? param;
    for (final p in point?.params ?? const <PlantParam>[]) {
      if (p.key == widget.paramKey) param = p;
    }
    if (point == null || param == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(s('plantPointNotFound'))),
      );
    }
    final range = _period.resolve(DateTime.now());
    final all = [for (final (d, v) in controller.series(point.id, param.key)) SeriesPoint(d, v)];
    final points = clipToRange(all, range.start, range.end);
    final t = controller.threshold(point.id, param.key);
    final stats = SeriesStats.of(points);
    final dateFormat = DateFormat('d MMM', locale.languageCode);
    final longDate = DateFormat('EEE d MMM yyyy', locale.languageCode);
    final unit = param.unit.isEmpty ? '' : ' ${param.unit}';

    return Scaffold(
      appBar: AppBar(title: Text('${s(param.labelKey)} · ${point.code}')),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 32, maxWidth: 900),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${point.name} — ${s(point.circuit.labelKey)}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                ),
              ),
              PeriodPill(value: _period, title: s('filterPeriod'), s: s, onChanged: (p) => setState(() => _period = p)),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: points.isEmpty
                  ? SizedBox(
                      height: 140,
                      child: Center(
                        child: Text(s('compareNoData'), style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SeriesChart(
                          series: [
                            ChartSeries.fromTime(label: s(param.labelKey), color: point.circuit.color, points: points),
                          ],
                          band: t == null || t.isEmpty
                              ? null
                              : (
                                  t.min ?? points.map((p) => p.v).reduce((a, b) => a < b ? a : b),
                                  t.max ?? points.map((p) => p.v).reduce((a, b) => a > b ? a : b),
                                ),
                          xLabel: (x) => dateFormat.format(DateTime.fromMillisecondsSinceEpoch(x.round())),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t == null ? s('plantNoThreshold') : '${s('trendThreshold')} : ${t.label(formatNumber)}$unit',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
            ),
          ),
          if (stats != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (label, value) in [
                  (s('compareStatMean'), stats.mean),
                  (s('compareStatMin'), stats.min),
                  (s('compareStatMax'), stats.max),
                  (s('compareStatLast'), stats.last),
                ])
                  Expanded(
                    child: Column(
                      children: [
                        Text(formatNumber(value), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(label, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (points.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  for (var i = points.length - 1; i >= 0 && i >= points.length - 40; i--) ...[
                    if (i < points.length - 1) Divider(height: 1, color: scheme.outlineVariant),
                    ListTile(
                      dense: true,
                      leading: Icon(
                        controller.isOut(point.id, param, points[i].v) == true
                            ? Icons.warning_amber_rounded
                            : Icons.circle,
                        size: controller.isOut(point.id, param, points[i].v) == true ? 20 : 10,
                        color: controller.isOut(point.id, param, points[i].v) == true
                            ? scheme.error
                            : point.circuit.color,
                      ),
                      title: Text(
                        '${formatNumber(points[i].v)}$unit',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: Text(
                        longDate.format(points[i].t),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
