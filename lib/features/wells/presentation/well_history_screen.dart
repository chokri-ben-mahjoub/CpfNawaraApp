import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/csv_exporter.dart';
import '../../../core/export/excel_exporter.dart';
import '../../../core/export/export_format_sheet.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/analysis_record.dart';
import '../../../core/models/analysis_type.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/record_edit_sheet.dart';

/// Historique complet et détaillé d'un puits : toutes les analyses, toutes
/// dates confondues, groupées par jour, avec filtre par type — contrairement
/// à l'aperçu (20 dernières) affiché sur la fiche puits.
class WellHistoryScreen extends ConsumerStatefulWidget {
  final String wellId;
  const WellHistoryScreen({super.key, required this.wellId});

  @override
  ConsumerState<WellHistoryScreen> createState() => _WellHistoryScreenState();
}

class _WellHistoryScreenState extends ConsumerState<WellHistoryScreen> {
  String? _typeFilter; // null = tous les types

  Future<void> _export(List<AnalysisRecord> records) async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(wellsControllerProvider.notifier);
    final well = controller.wellById(widget.wellId);

    if (records.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s('exportEmpty'))));
      return;
    }

    final format = await chooseExportFormat(context, locale);
    if (format == null) return;

    messenger.showSnackBar(SnackBar(content: Text(s('exportStarted'))));
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final headers = [
      s('colDate'),
      s('colType'),
      s('colValue'),
      s('colUnit'),
      s('colService'),
      s('colOperator'),
      s('colComment'),
    ];
    final rows = [
      for (final record in records)
        [
          dateFormat.format(record.dateTime),
          controller.typeById(record.typeId).label,
          record.value.toString(),
          controller.typeById(record.typeId).unit,
          s(record.serviceKey),
          record.operatorName,
          record.comment ?? '',
        ],
    ];
    final suffix = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    try {
      if (format == ExportFormat.excel) {
        await ExcelExporter.exportAndShare(
          fileName: '${well.code}_$suffix.xlsx',
          headers: headers,
          rows: rows,
          shareSubject: '${well.name} (${well.code})',
        );
      } else {
        await CsvExporter.exportAndShare(
          fileName: '${well.code}_$suffix.csv',
          headers: headers,
          rows: rows,
          shareSubject: '${well.name} (${well.code})',
        );
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s('exportError'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final well = controller.wellById(widget.wellId);
    final allHistory = controller.recordsForWell(widget.wellId);
    final usedTypeIds = allHistory.map((r) => r.typeId).toSet();
    final filterTypes = data.analysisTypes.where((t) => usedTypeIds.contains(t.id)).toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final history = _typeFilter == null ? allHistory : allHistory.where((r) => r.typeId == _typeFilter).toList();

    final byDay = <DateTime, List<AnalysisRecord>>{};
    for (final record in history) {
      final day = DateTime(record.dateTime.year, record.dateTime.month, record.dateTime.day);
      (byDay[day] ??= []).add(record);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final yesterdayDay = todayDay.subtract(const Duration(days: 1));
    final dayHeaderFormat = DateFormat('EEEE d MMMM yyyy', locale.languageCode);
    final timeFormat = DateFormat('HH:mm');

    String dayLabel(DateTime day) {
      if (day == todayDay) return s('navToday');
      if (day == yesterdayDay) return s('wellHistoryYesterday');
      final label = dayHeaderFormat.format(day);
      return label[0].toUpperCase() + label.substring(1);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${s('wellHistoryTitle')} · ${well.name}'),
        actions: [
          IconButton(
            tooltip: s('exportTooltip'),
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () => _export(history),
          ),
        ],
      ),
      body: Column(
        children: [
          if (filterTypes.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterChip(
                      label: s('wellHistoryAllTypes'),
                      selected: _typeFilter == null,
                      onTap: () => setState(() => _typeFilter = null),
                    ),
                    const SizedBox(width: 8),
                    for (final type in filterTypes) ...[
                      _FilterChip(
                        label: type.label,
                        selected: _typeFilter == type.id,
                        onTap: () => setState(() => _typeFilter = type.id),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          Expanded(
            child: history.isEmpty
                ? Center(
                    child: Text(s('wellHistoryEmpty'), style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      for (final day in days) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                          child: Text(
                            dayLabel(day),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant),
                          ),
                        ),
                        Card(
                          child: Column(
                            children: [
                              for (var i = 0; i < byDay[day]!.length; i++) ...[
                                if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                                _DetailedHistoryTile(
                                  record: byDay[day]![i],
                                  type: controller.typeById(byDay[day]![i].typeId),
                                  timeFormat: timeFormat,
                                ),
                              ],
                            ],
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: accentColor.withValues(alpha: 0.18),
      labelStyle: TextStyle(
        color: selected ? accentColor : scheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(color: selected ? accentColor : scheme.outlineVariant),
      backgroundColor: scheme.surface,
    );
  }
}

class _DetailedHistoryTile extends ConsumerWidget {
  final AnalysisRecord record;
  final AnalysisType type;
  final DateFormat timeFormat;

  const _DetailedHistoryTile({required this.record, required this.type, required this.timeFormat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    String s(String key) => tr(locale, key);
    final outOfRange = type.isOutOfRange(record.value);
    final statusColor = outOfRange ? scheme.error : Colors.green.shade600;

    return InkWell(
      onTap: role.canEnterData ? () => showRecordEditSheet(context, record: record, type: type) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                outOfRange ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: statusColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(type.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                      Text(
                        '${record.value} ${type.unit}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: statusColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${s('colService')} : ${s(record.serviceKey)}  ·  ${timeFormat.format(record.dateTime)}  ·  ${record.operatorName}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                  Text(
                    outOfRange
                        ? '${s('outOfRangeBadge')} (${type.min} – ${type.max} ${type.unit})'
                        : '${s('trendThreshold')} : ${type.min} – ${type.max} ${type.unit}',
                    style: TextStyle(color: statusColor, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  if (record.comment != null && record.comment!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      record.comment!,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
            if (role.canEnterData) ...[
              const SizedBox(width: 4),
              Icon(Icons.edit_outlined, color: scheme.onSurfaceVariant, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
