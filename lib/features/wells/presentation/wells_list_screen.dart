import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/data/wells_repository.dart';
import '../../../core/export/csv_exporter.dart';
import '../../../core/export/excel_exporter.dart';
import '../../../core/export/export_format_sheet.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/well.dart';
import '../../../core/theme/app_theme.dart';

/// Exporte tout l'historique d'analyses des puits d'une zone (toutes dates).
Future<void> _exportZone(WidgetRef ref, BuildContext context, String zoneLabel, List<Well> wells) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(wellsControllerProvider.notifier);

  final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final rows = <List<String>>[];
  for (final well in wells) {
    for (final record in controller.recordsForWell(well.id)) {
      final type = controller.typeById(record.typeId);
      rows.add([
        dateFormat.format(record.dateTime),
        '${well.name} (${well.code})',
        type.label,
        record.value.toString(),
        type.unit,
        s(record.serviceKey),
        record.operatorName,
        record.comment ?? '',
      ]);
    }
  }

  if (rows.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(s('exportEmpty'))));
    return;
  }

  final format = await chooseExportFormat(context, locale);
  if (format == null) return;

  messenger.showSnackBar(SnackBar(content: Text(s('exportStarted'))));
  final headers = [
    s('colDate'),
    s('colWell'),
    s('colType'),
    s('colValue'),
    s('colUnit'),
    s('colService'),
    s('colOperator'),
    s('colComment'),
  ];
  final safeName = zoneLabel.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  final suffix = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
  try {
    if (format == ExportFormat.excel) {
      await ExcelExporter.exportAndShare(fileName: '${safeName}_$suffix.xlsx', headers: headers, rows: rows, shareSubject: zoneLabel);
    } else {
      await CsvExporter.exportAndShare(fileName: '${safeName}_$suffix.csv', headers: headers, rows: rows, shareSubject: zoneLabel);
    }
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(s('exportError'))));
  }
}

class WellsListScreen extends ConsumerStatefulWidget {
  const WellsListScreen({super.key});

  @override
  ConsumerState<WellsListScreen> createState() => _WellsListScreenState();
}

class _WellsListScreenState extends ConsumerState<WellsListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    final wells = ref.watch(wellsControllerProvider).wells;
    String s(String key) => tr(locale, key);

    final filtered = wells.where((w) {
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return true;
      return w.name.toLowerCase().contains(q) || w.code.toLowerCase().contains(q);
    }).toList();

    final byGroup = <String, List<Well>>{};
    for (final well in filtered) {
      final key = well.group.trim().isEmpty ? s('statsUnassignedGroup') : well.group.trim();
      (byGroup[key] ??= []).add(well);
    }
    final groupNames = byGroup.keys.toList()..sort();
    for (final list in byGroup.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: s('wellsSearchHint'),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      s('wellsEmpty'),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView(
                    children: [
                      for (final groupName in groupNames) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  groupName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant),
                                ),
                              ),
                              IconButton(
                                tooltip: s('wellsExportZoneTooltip'),
                                icon: Icon(Icons.ios_share_outlined, size: 18, color: scheme.onSurfaceVariant),
                                onPressed: () => _exportZone(ref, context, groupName, byGroup[groupName]!),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                        for (final well in byGroup[groupName]!) ...[
                          _WellCard(
                            well: well,
                            done: controller.todayProgress(well.id).$1,
                            total: controller.todayProgress(well.id).$2,
                            onTap: () => context.push('/wells/${well.id}'),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _WellCard extends ConsumerWidget {
  final Well well;
  final int done;
  final int total;
  final VoidCallback onTap;

  const _WellCard({
    required this.well,
    required this.done,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final progressColor = total == 0
        ? scheme.onSurfaceVariant
        : done == total
            ? Colors.green.shade600
            : accentColor;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (well.active ? accentColor : scheme.outline).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.water_drop_outlined,
                  color: well.active ? accentColor : scheme.outline,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      well.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      well.code,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _StatusChip(
                          label: s(well.active ? 'wellStatusActive' : 'wellStatusStopped'),
                          color: well.active ? Colors.green.shade600 : scheme.outline,
                        ),
                        if (total > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '$done/$total ${s('wellsTodaySuffix')}',
                            style: TextStyle(fontSize: 12, color: progressColor, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
