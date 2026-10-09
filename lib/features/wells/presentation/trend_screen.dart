import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import 'widgets/production_chart.dart';
import 'widgets/trend_chart.dart';

const _compareColor = Color(0xFF1E88E5);

class TrendScreen extends ConsumerStatefulWidget {
  final String wellId;
  final String typeId;

  const TrendScreen({super.key, required this.wellId, required this.typeId});

  @override
  ConsumerState<TrendScreen> createState() => _TrendScreenState();
}

class _TrendScreenState extends ConsumerState<TrendScreen> {
  String? _compareTypeId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final well = controller.wellById(widget.wellId);
    final type = controller.typeById(widget.typeId);
    final records = controller.recordsForWell(widget.wellId).where((r) => r.typeId == widget.typeId).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final dateFormat = DateFormat('d MMM', locale.languageCode);
    final dateTimeFormat = DateFormat('d MMM, HH:mm', locale.languageCode);

    final latest = records.isEmpty ? null : records.last;
    final previous = records.length < 2 ? null : records[records.length - 2];
    double? deltaPct;
    if (latest != null && previous != null && previous.value != 0) {
      deltaPct = (latest.value - previous.value) / previous.value * 100;
    }

    final otherTypes = data.analysisTypes.where((t) => t.id != widget.typeId).toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final compareType = _compareTypeId == null ? null : controller.typeById(_compareTypeId!);

    final since = DateTime.now().subtract(const Duration(days: 30));
    final combinedSeries = compareType == null
        ? null
        : [
            ProductionSeries(
              label: type.label,
              unit: type.unit,
              color: accentColor,
              records: records.where((r) => r.dateTime.isAfter(since)).toList(),
            ),
            ProductionSeries(
              label: compareType.label,
              unit: compareType.unit,
              color: _compareColor,
              records: controller
                  .recordsForWell(widget.wellId)
                  .where((r) => r.typeId == compareType.id && r.dateTime.isAfter(since))
                  .toList()
                ..sort((a, b) => a.dateTime.compareTo(b.dateTime)),
            ),
          ];

    return Scaffold(
      appBar: AppBar(title: Text('${type.label} · ${well.name}')),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 24),
        children: [
          if (latest != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s('trendLatest'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            '${latest.value} ${type.unit}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: type.isOutOfRange(latest.value) ? scheme.error : scheme.onSurface,
                            ),
                          ),
                          Text(
                            dateTimeFormat.format(latest.dateTime),
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (deltaPct != null) _DeltaBadge(deltaPct: deltaPct, s: s),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            '${s('trendThreshold')} : ${type.min} – ${type.max} ${type.unit}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          if (otherTypes.isNotEmpty)
            DropdownButtonFormField<String?>(
              initialValue: _compareTypeId,
              decoration: InputDecoration(
                labelText: s('trendCompareWith'),
                prefixIcon: const Icon(Icons.compare_arrows_outlined),
              ),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(s('trendCompareNone'))),
                for (final t in otherTypes) DropdownMenuItem<String?>(value: t.id, child: Text(t.label)),
              ],
              onChanged: (value) => setState(() => _compareTypeId = value),
            ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: combinedSeries != null
                  ? (combinedSeries.every((series) => series.records.length < 2)
                      ? SizedBox(
                          height: 120,
                          child: Center(child: Text(s('trendNoData'), style: TextStyle(color: scheme.onSurfaceVariant))),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ProductionChart(
                              series: combinedSeries,
                              markers: [
                                for (final i in controller.interventionsForWell(widget.wellId))
                                  if (i.date.isAfter(since)) (i.date, s(i.typeKey)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 14,
                              runSpacing: 6,
                              children: [
                                for (final series in combinedSeries)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(color: series.color, shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${series.label} (${series.unit})',
                                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ))
                  : (records.length < 2
                      ? SizedBox(
                          height: 120,
                          child: Center(child: Text(s('trendNoData'), style: TextStyle(color: scheme.onSurfaceVariant))),
                        )
                      : TrendChart(
                          records: records,
                          min: type.min,
                          max: type.max,
                          lineColor: accentColor,
                          markers: [
                            for (final i in controller.interventionsForWell(widget.wellId))
                              if (!i.date.isBefore(DateTime(records.first.dateTime.year, records.first.dateTime.month,
                                  records.first.dateTime.day)))
                                (i.date, s(i.typeKey)),
                          ],
                        )),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            s('trendRecentValues'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                for (var i = records.length - 1; i >= 0; i--) ...[
                  if (i < records.length - 1) Divider(height: 1, color: scheme.outlineVariant),
                  ListTile(
                    leading: Icon(
                      type.isOutOfRange(records[i].value) ? Icons.warning_amber_rounded : Icons.circle,
                      size: type.isOutOfRange(records[i].value) ? 22 : 10,
                      color: type.isOutOfRange(records[i].value) ? scheme.error : accentColor,
                    ),
                    title: Text('${records[i].value} ${type.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${s(records[i].serviceKey)} · ${records[i].operatorName} · ${dateFormat.format(records[i].dateTime)}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  final double deltaPct;
  final String Function(String) s;

  const _DeltaBadge({required this.deltaPct, required this.s});

  @override
  Widget build(BuildContext context) {
    final rising = deltaPct > 0.5;
    final falling = deltaPct < -0.5;
    final color = rising ? Colors.orange.shade700 : (falling ? Colors.blue.shade700 : Colors.grey.shade600);
    final icon = rising ? Icons.trending_up : (falling ? Icons.trending_down : Icons.trending_flat);
    final label = rising ? s('trendUp') : (falling ? s('trendDown') : s('trendStable'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(
          '${deltaPct.toStringAsFixed(1)}%',
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
        ),
        Text(s('trendVsPrevious'), style: TextStyle(color: color, fontSize: 11)),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}
