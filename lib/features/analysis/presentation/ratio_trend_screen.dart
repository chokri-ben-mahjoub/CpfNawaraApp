import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/analysis/metrics.dart';
import '../../../core/analysis/production_metrics.dart';
import '../../../core/analysis/series.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/filters/well_filter.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/units/unit_system.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/series_chart.dart';
import '../../../core/widgets/responsive.dart';
import '../../interventions/presentation/widgets/intervention_ui.dart';

/// Demande la pression de gisement (Pr) d'un puits, nécessaire au PI.
Future<void> editReservoirPressure(BuildContext context, WidgetRef ref, String wellId) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final controller = ref.read(wellsControllerProvider.notifier);
  final current = controller.findWell(wellId)?.reservoirPressure;
  final textController = TextEditingController(text: current == null ? '' : formatNumber(current));
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<(bool, double?)>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(s('reservoirPressureTitle')),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s('reservoirPressureHint'), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextFormField(
              controller: textController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: s('reservoirPressureLabel'), suffixText: Units.unit('bar')),
              validator: (v) {
                final text = (v ?? '').trim().replaceAll(',', '.');
                if (text.isEmpty) return null;
                final value = double.tryParse(text);
                return value == null || value <= 0 ? s('adminInvalidThreshold') : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(s('cancel'))),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            final text = textController.text.trim().replaceAll(',', '.');
            Navigator.of(dialogContext).pop((true, text.isEmpty ? null : double.parse(text)));
          },
          child: Text(s('wellsManageSave')),
        ),
      ],
    ),
  );
  textController.dispose();
  if (result == null || !result.$1) return;
  await controller.setReservoirPressure(wellId, result.$2);
}

/// Évolution d'un ratio calculé (GOR, WOR, GLR, PI) pour un puits.
class RatioTrendScreen extends ConsumerStatefulWidget {
  final String wellId;
  final DerivedRatio ratio;

  const RatioTrendScreen({super.key, required this.wellId, required this.ratio});

  @override
  ConsumerState<RatioTrendScreen> createState() => _RatioTrendScreenState();
}

class _RatioTrendScreenState extends ConsumerState<RatioTrendScreen> {
  PeriodSelection _period = PeriodSelection.days90;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final well = controller.findWell(widget.wellId);
    if (well == null) return Scaffold(appBar: AppBar(), body: Center(child: Text(s('wellsEmpty'))));
    final metric = findMetric(metricOptions(data, s), MetricOption.ratioKey(widget.ratio));
    final unit = metric?.unit ?? '';
    final range = _period.resolve(DateTime.now());
    final all = metric == null ? <SeriesPoint>[] : metricSeries(data, well.id, metric);
    final points = clipToRange(all, range.start, range.end);
    final latest = all.isEmpty ? null : all.last;
    final previous = all.length < 2 ? null : all[all.length - 2];
    final delta = latest == null || previous == null ? null : percentChange(previous.v, latest.v);
    final dateFormat = DateFormat('d MMM', locale.languageCode);
    final longDate = DateFormat('d MMM yyyy', locale.languageCode);
    final isPi = widget.ratio == DerivedRatio.pi;

    return Scaffold(
      appBar: AppBar(title: Text('${s(widget.ratio.labelKey)} · ${well.name}')),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s(widget.ratio.descriptionKey), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          latest == null ? '—' : '${formatNumber(latest.v)} $unit',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (delta != null)
                        Text(
                          '${formatPercent(delta)} ${s('trendVsPrevious')}',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                    ],
                  ),
                  if (latest != null)
                    Text(longDate.format(latest.t), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  if (isPi) ...[
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${s('reservoirPressureLabel')} : ${well.reservoirPressure == null ? s('notSet') : '${formatNumber(well.reservoirPressure!)} bar'}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        if (role.canConfigure)
                          TextButton(
                            onPressed: () => editReservoirPressure(context, ref, well.id),
                            child: Text(s('edit')),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: PeriodPill(
              value: _period,
              title: s('filterPeriod'),
              s: s,
              onChanged: (p) => setState(() => _period = p),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: points.isEmpty
                  ? SizedBox(
                      height: 140,
                      child: Center(
                        child: Text(
                          isPi ? s('piMissingInputs') : s('ratioMissingInputs'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SeriesChart(
                          series: [ChartSeries.fromTime(label: s(widget.ratio.labelKey), color: accentColor, points: points)],
                          markers: interventionMarkers(
                            controller.interventionsForWell(well.id),
                            s,
                            from: range.start,
                            to: range.end,
                          ),
                          xLabel: (x) => dateFormat.format(DateTime.fromMillisecondsSinceEpoch(x.round())),
                        ),
                        const SizedBox(height: 8),
                        ChartLegend(entries: [
                          ('${s(widget.ratio.labelKey)} ($unit)', accentColor, false),
                          if (controller.interventionsForWell(well.id).isNotEmpty)
                            (s('interventionsTitle'), interventionMarkerColor, true),
                        ]),
                      ],
                    ),
            ),
          ),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(s('trendRecentValues'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (var i = points.length - 1; i >= 0 && i >= points.length - 30; i--) ...[
                    if (i < points.length - 1) Divider(height: 1, color: scheme.outlineVariant),
                    ListTile(
                      dense: true,
                      title: Text('${formatNumber(points[i].v)} $unit', style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: Text(longDate.format(points[i].t), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
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
