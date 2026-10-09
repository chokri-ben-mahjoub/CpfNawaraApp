import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/analysis/decline.dart';
import '../../../core/analysis/production_metrics.dart';
import '../../../core/analysis/series.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/production_types.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/series_chart.dart';
import '../../../core/widgets/responsive.dart';
import '../../interventions/presentation/widgets/intervention_ui.dart';

const oilColor = Color(0xFF2E7D32);
const gasColor = Color(0xFFE53935);

/// Débits pour lesquels une courbe de déclin a du sens.
const declineFluids = [oilFlowTypeId, gasFlowTypeId];

Color fluidColor(String typeId) => typeId == gasFlowTypeId ? gasColor : oilColor;

/// Analyse de déclin d'un puits pour un débit : ajustement automatique, avec
/// la fenêtre par défaut "depuis la dernière intervention".
DeclineResult declineFor(WellsState data, String wellId, String fluidTypeId, DeclineWindow window) {
  final records = data.records.where((r) => r.wellId == wellId).toList();
  final rates = ProductionMetrics.fromRecords(records).rateSeries(fluidTypeId);
  DateTime? lastIntervention;
  for (final i in data.interventions) {
    if (i.wellId != wellId) continue;
    if (lastIntervention == null || i.date.isAfter(lastIntervention)) lastIntervention = i.date;
  }
  return analyzeDecline(rates, window: window, lastInterventionDate: lastIntervention);
}

/// Courbe de déclin d'un puits (huile ou gaz) : débits mesurés, courbe
/// exponentielle ajustée, prévision, taux de déclin calculés automatiquement.
class DeclineScreen extends ConsumerStatefulWidget {
  final String wellId;
  final String? initialFluid;

  const DeclineScreen({super.key, required this.wellId, this.initialFluid});

  @override
  ConsumerState<DeclineScreen> createState() => _DeclineScreenState();
}

class _DeclineScreenState extends ConsumerState<DeclineScreen> {
  late String _fluid = declineFluids.contains(widget.initialFluid) ? widget.initialFluid! : oilFlowTypeId;
  DeclineWindow _window = DeclineWindow.auto;
  bool _log = false;
  int _horizon = 90;
  final _limitController = TextEditingController();

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final well = controller.findWell(widget.wellId);
    final fluidType = controller.findType(_fluid);
    if (well == null || fluidType == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(s('declineNoData'))));
    }
    final result = declineFor(data, well.id, _fluid, _window);
    final fit = result.fit;
    final color = fluidColor(_fluid);
    final unit = fluidType.unit;
    final volumeUnit = unit.endsWith('/j') ? unit.substring(0, unit.length - 2) : unit;
    final dateFormat = DateFormat('d MMM yy', locale.languageCode);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final usedSet = result.used.map((p) => p.t).toSet();
    final outside = result.all.where((p) => !usedSet.contains(p.t)).toList();
    final fitted = <SeriesPoint>[];
    final forecast = <SeriesPoint>[];
    if (fit != null) {
      final span = fit.end.difference(fit.start).inDays;
      final steps = span.clamp(2, 60);
      for (var i = 0; i <= steps; i++) {
        final t = fit.start.add(Duration(milliseconds: (fit.end.difference(fit.start).inMilliseconds * i / steps).round()));
        fitted.add(SeriesPoint(t, fit.rateAt(t)));
      }
      final forecastEnd = today.add(Duration(days: _horizon));
      final from = fit.end;
      for (var i = 0; i <= 30; i++) {
        final t = from.add(Duration(milliseconds: (forecastEnd.difference(from).inMilliseconds * i / 30).round()));
        forecast.add(SeriesPoint(t, fit.rateAt(t)));
      }
    }

    final limit = double.tryParse(_limitController.text.trim().replaceAll(',', '.'));
    final daysToLimit = fit == null || limit == null ? null : fit.daysUntilRate(limit, today);

    return Scaffold(
      appBar: AppBar(
        title: Text('${s('declineTitle')} · ${well.name}'),
        actions: [
          IconButton(
            tooltip: s('exportTooltip'),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _export(well.code, well.name, fluidType.label, unit, result, s, locale),
          ),
        ],
      ),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterPill<String>(
                icon: Icons.opacity,
                title: s('declineFluid'),
                options: [
                  for (final id in declineFluids)
                    if (controller.findType(id) != null) PillOption(id, controller.findType(id)!.label),
                ],
                selected: _fluid,
                active: true,
                onSelected: (v) => setState(() => _fluid = v),
              ),
              FilterPill<DeclineWindow>(
                icon: Icons.date_range_outlined,
                title: s('declineWindow'),
                options: [for (final w in DeclineWindow.values) PillOption(w, s(w.labelKey))],
                selected: _window,
                active: _window != DeclineWindow.auto,
                onSelected: (v) => setState(() => _window = v),
              ),
              FilterPill<int>(
                icon: Icons.trending_flat,
                title: s('declineHorizon'),
                options: [for (final d in const [30, 90, 180, 365]) PillOption(d, '${s('declineForecast')} +$d ${s('daysShort')}')],
                selected: _horizon,
                onSelected: (v) => setState(() => _horizon = v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${fluidType.label} ($unit)',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      Text(s('declineLogScale'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      Switch(
                        value: _log,
                        activeTrackColor: accentColor,
                        onChanged: (v) => setState(() => _log = v),
                      ),
                    ],
                  ),
                  if (result.all.length < 2)
                    SizedBox(
                      height: 140,
                      child: Center(
                        child: Text(s('declineNoData'), textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    )
                  else ...[
                    SeriesChart(
                      height: 240,
                      logScale: _log,
                      series: [
                        if (outside.isNotEmpty)
                          ChartSeries.fromTime(
                            label: s('declineOutsideWindow'),
                            color: scheme.outline,
                            points: outside,
                            strokeWidth: 1.5,
                          ),
                        ChartSeries.fromTime(label: s('declineMeasured'), color: color, points: result.used),
                        if (fitted.isNotEmpty)
                          ChartSeries.fromTime(
                            label: s('declineFitted'),
                            color: scheme.onSurface,
                            points: fitted,
                            dashed: true,
                            showDots: false,
                            strokeWidth: 2,
                          ),
                        if (forecast.isNotEmpty)
                          ChartSeries.fromTime(
                            label: s('declineForecast'),
                            color: accentColor,
                            points: forecast,
                            dashed: true,
                            showDots: false,
                            strokeWidth: 2,
                          ),
                      ],
                      markers: interventionMarkers(controller.interventionsForWell(well.id), s),
                      xLabel: (x) => dateFormat.format(DateTime.fromMillisecondsSinceEpoch(x.round())),
                    ),
                    const SizedBox(height: 10),
                    ChartLegend(entries: [
                      (s('declineMeasured'), color, false),
                      if (fitted.isNotEmpty) (s('declineFitted'), scheme.onSurface, true),
                      if (forecast.isNotEmpty) (s('declineForecast'), accentColor, true),
                      if (outside.isNotEmpty) (s('declineOutsideWindow'), scheme.outline, false),
                      if (controller.interventionsForWell(well.id).isNotEmpty)
                        (s('interventionsTitle'), interventionMarkerColor, true),
                    ]),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (fit == null)
            _InfoBox(
              icon: Icons.info_outline,
              text: s('declineNotEnoughPoints'),
            )
          else ...[
            _DeclineSummary(fit: fit, unit: unit, s: s, sinceIntervention: result.sinceIntervention),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s('declineForecastTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 10),
                    for (final d in const [30, 90, 180])
                      _KeyValue(
                        '${s('declineRateIn')} $d ${s('daysShort')}',
                        '${formatNumber(fit.rateAt(today.add(Duration(days: d))))} $unit',
                      ),
                    _KeyValue(
                      '${s('declineCumulative')} $_horizon ${s('daysShort')}',
                      '${formatNumber(fit.cumulativeBetween(today, today.add(Duration(days: _horizon))))} $volumeUnit',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _limitController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: s('declineLimitLabel'),
                        suffixText: unit,
                        isDense: true,
                      ),
                    ),
                    if (limit != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        daysToLimit == null
                            ? s('declineLimitNever')
                            : fill(s('declineLimitReached'), {
                                'days': daysToLimit.round().toString(),
                                'date': DateFormat('d MMM yyyy', locale.languageCode)
                                    .format(today.add(Duration(days: daysToLimit.round()))),
                              }),
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _InfoBox(icon: Icons.functions, text: s('declineMethodNote')),
        ],
      ),
    );
  }

  void _export(String code, String wellName, String fluidLabel, String unit, DeclineResult result, String Function(String) s,
      Locale locale) {
    final fit = result.fit;
    runExport(
      context: context,
      locale: locale,
      baseName: '${code}_declin',
      shareSubject: '${s('declineTitle')} · $wellName',
      tables: [
        ExportTable(
          name: s('exportSheetSummary'),
          headers: [s('declineIndicator'), s('colValue')],
          rows: fit == null
              ? [
                  [s('declineNotEnoughPoints'), null],
                ]
              : [
                  [s('colWell'), wellName],
                  [s('declineFluid'), '$fluidLabel ($unit)'],
                  [s('declineFrom'), DateOnly(fit.start)],
                  [s('declineTo'), DateOnly(fit.end)],
                  [s('declinePoints'), fit.pointCount],
                  ['${s('declineEffectiveAnnual')} (%)', roundTo(fit.effectiveAnnualPct, 2)],
                  ['${s('declineEffectiveMonthly')} (%)', roundTo(fit.effectiveMonthlyPct, 2)],
                  ['${s('declineNominalAnnual')} (%)', roundTo(fit.nominalAnnualPct, 2)],
                  ['D (1/${s('daysShort')})', roundTo(fit.dailyRate, 6)],
                  ['qi ($unit)', roundTo(fit.qi, 3)],
                  ['R²', roundTo(fit.r2, 4)],
                ],
        ),
        ExportTable(
          name: s('exportSheetData'),
          headers: [s('colDate'), '${s('declineMeasured')} ($unit)', '${s('declineFitted')} ($unit)', s('declineUsed')],
          rows: [
            for (final p in result.all)
              [
                DateOnly(p.t),
                p.v,
                fit == null ? null : roundTo(fit.rateAt(p.t), 3),
                result.used.any((u) => u.t == p.t) ? s('yes') : s('no'),
              ],
          ],
        ),
      ],
    );
  }
}

/// Résumé du déclin (taux effectifs, nominal, qualité de l'ajustement),
/// partagé avec la carte "Déclin" de la fiche puits.
class _DeclineSummary extends StatelessWidget {
  final DeclineFit fit;
  final String unit;
  final String Function(String) s;
  final bool sinceIntervention;

  const _DeclineSummary({required this.fit, required this.unit, required this.s, required this.sinceIntervention});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final declining = fit.isDeclining;
    final mainColor = declining ? scheme.error : Colors.green.shade700;
    final quality = fit.r2 >= 0.8
        ? s('declineFitGood')
        : fit.r2 >= 0.5
            ? s('declineFitMedium')
            : s('declineFitPoor');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              declining ? s('declineEffectiveAnnual') : s('declineGrowthAnnual'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(declining ? Icons.trending_down : Icons.trending_up, color: mainColor, size: 28),
                const SizedBox(width: 8),
                Text(
                  '${fit.effectiveAnnualPct.abs().toStringAsFixed(1)} % / ${s('yearShort')}',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: mainColor),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              sinceIntervention ? s('declineSinceIntervention') : s('declineOnWindow'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const Divider(height: 24),
            _KeyValue(s('declineEffectiveMonthly'), '${fit.effectiveMonthlyPct.toStringAsFixed(2)} %'),
            _KeyValue(s('declineNominalAnnual'), '${fit.nominalAnnualPct.toStringAsFixed(1)} %'),
            _KeyValue('D', '${fit.dailyRate.toStringAsExponential(3)} / ${s('daysShort')}'),
            _KeyValue('${s('declineQi')} (${DateFormat('dd/MM/yy').format(fit.start)})', '${formatNumber(fit.qi)} $unit'),
            _KeyValue(s('declinePoints'), '${fit.pointCount}'),
            _KeyValue('R²', '${fit.r2.toStringAsFixed(3)} · $quality'),
          ],
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;
  const _KeyValue(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.35))),
        ],
      ),
    );
  }
}
