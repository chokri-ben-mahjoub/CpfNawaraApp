import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/analysis/series.dart';
import '../../../../core/filters/well_filter.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/plant/plant_catalog.dart';
import '../../../../core/plant/plant_repository.dart';
import '../../../../core/widgets/filter_pills.dart';
import '../../../../core/widgets/series_chart.dart';

/// Couleurs des courbes d'un groupe (la première = couleur du circuit).
const _curveColors = [
  Color(0xFF1E88E5),
  Color(0xFFE53935),
  Color(0xFF43A047),
  Color(0xFFFB8C00),
  Color(0xFF8E24AA),
  Color(0xFF00ACC1),
  Color(0xFF6D4C41),
  Color(0xFFD81B60),
  Color(0xFF3949AB),
  Color(0xFF7CB342),
];

Color variationColor(int direction, ColorScheme scheme) => switch (direction) {
  > 0 => Colors.orange.shade800,
  < 0 => Colors.blue.shade600,
  _ => scheme.onSurfaceVariant,
};

IconData variationIcon(int direction) => switch (direction) {
  > 0 => Icons.trending_up,
  < 0 => Icons.trending_down,
  _ => Icons.trending_flat,
};

/// Pastille "▲ +12,5 %" : hausse (orange), baisse (bleu) ou stable, par
/// rapport à l'analyse précédente.
class PlantVariationBadge extends StatelessWidget {
  final PlantVariation variation;
  const PlantVariationBadge({super.key, required this.variation});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = variationColor(variation.direction, scheme);
    final pct = variation.percent;
    final sign = variation.delta > 0 ? '+' : '';
    final text = pct == null ? '$sign${formatNumber(variation.delta)}' : '$sign${formatNumber(pct)} %';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(variationIcon(variation.direction), size: 14, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

/// Vue "Courbes" de l'onglet Usine : plus fortes hausses / baisses de la
/// dernière analyse, puis, par circuit (groupe de points), les courbes d'un
/// paramètre pour tous les points du groupe.
class PlantTrendsView extends ConsumerStatefulWidget {
  const PlantTrendsView({super.key});

  @override
  ConsumerState<PlantTrendsView> createState() => _PlantTrendsViewState();
}

class _PlantTrendsViewState extends ConsumerState<PlantTrendsView> {
  PeriodSelection _period = PeriodSelection.days90;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final plant = ref.watch(plantControllerProvider);
    String s(String key) => tr(locale, key);
    final range = _period.resolve(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(s('plantTrendsIntro'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ),
            PeriodPill(value: _period, title: s('filterPeriod'), s: s, onChanged: (p) => setState(() => _period = p)),
          ],
        ),
        const SizedBox(height: 12),
        _BiggestChanges(range: range),
        const SizedBox(height: 12),
        for (final circuit in plant.circuits) _CircuitTrends(circuit: circuit, range: range),
      ],
    );
  }
}

/// Plus fortes variations (en %) entre les deux dernières analyses de
/// chaque point, dans la période.
class _BiggestChanges extends ConsumerWidget {
  final DateTimeRange range;
  const _BiggestChanges({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final plant = ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final dateFormat = DateFormat('d MMM', locale.languageCode);
    final end = range.end.add(const Duration(days: 1));

    final changes = <(SamplePoint, PlantParam, PlantVariation)>[];
    for (final point in plant.points.where((p) => p.active)) {
      for (final param in point.params.where((p) => p.isNumeric)) {
        final v = controller.variation(point.id, param.key);
        if (v == null || v.direction == 0 || v.date.isBefore(range.start) || !v.date.isBefore(end)) continue;
        changes.add((point, param, v));
      }
    }
    double weight(PlantVariation v) => (v.percent ?? 100).abs();
    changes.sort((a, b) => weight(b.$3).compareTo(weight(a.$3)));
    final top = changes.take(8).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.swap_vert, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s('plantTrendsChanges'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (top.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(s('plantTrendsNoChange'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
              )
            else
              for (final (point, param, v) in top)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => context.push('/plant/point/${point.id}/trend/${param.key}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                    child: Row(
                      children: [
                        Icon(variationIcon(v.direction), color: variationColor(v.direction, scheme)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${point.code} · ${s(param.labelKey)}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              Text(
                                '${formatNumber(v.previous)} → ${formatNumber(v.value)}'
                                '${param.unit.isEmpty ? '' : ' ${param.unit}'}'
                                '  (${dateFormat.format(v.previousDate)} → ${dateFormat.format(v.date)})',
                                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        PlantVariationBadge(variation: v),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Courbes d'un paramètre pour tous les points d'un circuit.
class _CircuitTrends extends ConsumerStatefulWidget {
  final PlantCircuit circuit;
  final DateTimeRange range;
  const _CircuitTrends({required this.circuit, required this.range});

  @override
  ConsumerState<_CircuitTrends> createState() => _CircuitTrendsState();
}

class _CircuitTrendsState extends ConsumerState<_CircuitTrends> {
  String? _param;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final circuit = widget.circuit;
    final points = controller.pointsOf(circuit);
    if (points.isEmpty) return const SizedBox.shrink();

    // Paramètres numériques du groupe qui ont au moins une valeur.
    final params = <String, PlantParam>{};
    for (final p in points) {
      for (final param in p.params.where((x) => x.isNumeric)) {
        if (!params.containsKey(param.key) && controller.series(p.id, param.key).isNotEmpty) {
          params[param.key] = param;
        }
      }
    }
    final selected = params[_param] ?? (params.isEmpty ? null : params.values.first);
    final dateFormat = DateFormat('d MMM', locale.languageCode);

    final curves = <(SamplePoint, Color, List<SeriesPoint>)>[];
    if (selected != null) {
      for (final p in points) {
        if (!p.params.any((x) => x.key == selected.key)) continue;
        final all = [for (final (d, v) in controller.series(p.id, selected.key)) SeriesPoint(d, v)];
        final data = clipToRange(all, widget.range.start, widget.range.end);
        final color = curves.isEmpty ? circuit.color : _curveColors[curves.length % _curveColors.length];
        curves.add((p, color, data));
      }
    }
    final withData = curves.where((c) => c.$3.isNotEmpty).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(circuit.icon, color: circuit.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s(circuit.labelKey), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  Text(
                    fill(s('plantTrendsPointCount'), {'n': '${points.length}'}),
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (selected == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(s('plantTrendsNoData'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                )
              else ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final param in params.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            showCheckmark: false,
                            selected: param.key == selected.key,
                            label: Text(s(param.labelKey)),
                            onSelected: (_) => setState(() => _param = param.key),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (withData.isEmpty)
                  SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(s('plantTrendsNoData'), style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  )
                else
                  SeriesChart(
                    height: 230,
                    series: [
                      for (final (p, color, data) in withData)
                        ChartSeries.fromTime(
                          label: p.code,
                          color: color,
                          points: data,
                          smooth: true,
                          area: withData.length == 1,
                          showDots: data.length <= 40,
                        ),
                    ],
                    xLabel: (x) => dateFormat.format(DateTime.fromMillisecondsSinceEpoch(x.round())),
                  ),
                const SizedBox(height: 8),
                for (final (p, color, data) in curves)
                  _CurveRow(point: p, param: selected, color: color, hasData: data.isNotEmpty),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CurveRow extends ConsumerWidget {
  final SamplePoint point;
  final PlantParam param;
  final Color color;
  final bool hasData;
  const _CurveRow({required this.point, required this.param, required this.color, required this.hasData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(plantControllerProvider.notifier);
    final series = controller.series(point.id, param.key);
    final last = series.isEmpty ? null : series.last.$2;
    final variation = controller.variation(point.id, param.key);
    final out = last == null ? null : controller.isOut(point.id, param, last);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/plant/point/${point.id}/trend/${param.key}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 4,
              decoration: BoxDecoration(
                color: hasData ? color : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${point.code} — ${point.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: Text(
                last == null ? '—' : '${formatNumber(last)}${param.unit.isEmpty ? '' : ' ${param.unit}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: out == true ? scheme.error : (last == null ? scheme.onSurfaceVariant : scheme.onSurface),
                ),
              ),
            ),
            if (variation != null) ...[const SizedBox(width: 6), PlantVariationBadge(variation: variation)],
          ],
        ),
      ),
    );
  }
}
