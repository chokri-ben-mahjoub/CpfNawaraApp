import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/trend_chart.dart';

class TrendScreen extends ConsumerWidget {
  final String wellId;
  final String typeId;

  const TrendScreen({super.key, required this.wellId, required this.typeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final well = controller.wellById(wellId);
    final type = controller.typeById(typeId);
    final records = controller.recordsForWell(wellId).where((r) => r.typeId == typeId).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final dateFormat = DateFormat('d MMM', locale.languageCode);
    final dateTimeFormat = DateFormat('d MMM, HH:mm', locale.languageCode);

    final latest = records.isEmpty ? null : records.last;
    final previous = records.length < 2 ? null : records[records.length - 2];
    double? deltaPct;
    if (latest != null && previous != null && previous.value != 0) {
      deltaPct = (latest.value - previous.value) / previous.value * 100;
    }

    return Scaffold(
      appBar: AppBar(title: Text('${s(type.labelKey)} · ${well.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: records.length < 2
                  ? SizedBox(
                      height: 120,
                      child: Center(
                        child: Text(s('trendNoData'), style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    )
                  : TrendChart(records: records, min: type.min, max: type.max, lineColor: accentColor),
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
