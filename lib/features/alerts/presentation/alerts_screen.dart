import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/csv_exporter.dart';
import '../../../core/export/excel_exporter.dart';
import '../../../core/export/export_format_sheet.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/analysis_type.dart';
import '../../../core/models/user_role.dart';
import '../../../core/models/well.dart';
import '../../../core/theme/app_theme.dart';

/// Exporte en Excel les analyses en retard et les dernières valeurs hors
/// seuil, tous puits actifs confondus (utile pour un rapport HSE).
Future<void> exportAlerts(WidgetRef ref, BuildContext context) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final messenger = ScaffoldMessenger.of(context);

  final data = ref.read(wellsControllerProvider);
  final controller = ref.read(wellsControllerProvider.notifier);
  final today = DateTime.now();
  final activeWells = data.wells.where((w) => w.active).toList();
  final dateFormat = DateFormat('dd/MM/yyyy');

  final rows = <List<String>>[];
  for (final well in activeWells) {
    for (final type in data.analysisTypes) {
      final last = controller.lastRecord(well.id, type.id);
      if (type.isDueOn(today) && controller.statusFor(well.id, type.id, now: today) == DailyStatus.overdue) {
        final lastInfo = last == null ? s('wellDetailNoValue') : dateFormat.format(last.dateTime);
        rows.add([s('alertsOverdueSection'), '${well.name} (${well.code})', type.label, lastInfo]);
      }
      if (last != null && type.isOutOfRange(last.value) && last.isSameDay(today)) {
        rows.add([
          s('alertsOutOfRangeSection'),
          '${well.name} (${well.code})',
          type.label,
          '${last.value} ${type.unit} (${type.min}–${type.max} ${type.unit})',
        ]);
      }
    }
  }

  if (rows.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(s('exportEmpty'))));
    return;
  }

  final format = await chooseExportFormat(context, locale);
  if (format == null) return;

  messenger.showSnackBar(SnackBar(content: Text(s('exportStarted'))));
  final headers = [s('colStatus'), s('colWell'), s('colType'), s('colDate')];
  final suffix = DateFormat('yyyyMMdd_HHmm').format(today);
  try {
    if (format == ExportFormat.excel) {
      await ExcelExporter.exportAndShare(fileName: 'alertes_$suffix.xlsx', headers: headers, rows: rows);
    } else {
      await CsvExporter.exportAndShare(fileName: 'alertes_$suffix.csv', headers: headers, rows: rows);
    }
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(s('exportError'))));
  }
}

class _OverdueItem {
  final Well well;
  final AnalysisType type;
  const _OverdueItem(this.well, this.type);
}

class _OutOfRangeItem {
  final Well well;
  final AnalysisType type;
  final double value;
  const _OutOfRangeItem(this.well, this.type, this.value);
}

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final today = DateTime.now();
    final activeWells = data.wells.where((w) => w.active).toList();

    final overdue = <_OverdueItem>[];
    final outOfRange = <_OutOfRangeItem>[];
    for (final well in activeWells) {
      for (final type in data.analysisTypes) {
        if (type.isDueOn(today) && controller.statusFor(well.id, type.id, now: today) == DailyStatus.overdue) {
          overdue.add(_OverdueItem(well, type));
        }
        final last = controller.lastRecord(well.id, type.id);
        if (last != null && type.isOutOfRange(last.value) && last.isSameDay(today)) {
          outOfRange.add(_OutOfRangeItem(well, type, last.value));
        }
      }
    }

    final hasAlerts = overdue.isNotEmpty || outOfRange.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (!hasAlerts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text(s('alertsEmpty'), textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ),
        if (outOfRange.isNotEmpty) ...[
          _SectionTitle(s('alertsOutOfRangeSection')),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < outOfRange.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.error.withValues(alpha: 0.12),
                      child: Icon(Icons.warning_amber_rounded, color: scheme.error),
                    ),
                    title: Text(
                      '${outOfRange[i].well.name} · ${outOfRange[i].type.label}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${outOfRange[i].value} ${outOfRange[i].type.unit} '
                      '(${outOfRange[i].type.min}–${outOfRange[i].type.max} ${outOfRange[i].type.unit})',
                      style: TextStyle(color: scheme.error),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/wells/${outOfRange[i].well.id}/trend/${outOfRange[i].type.id}'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (overdue.isNotEmpty) ...[
          _SectionTitle(s('alertsOverdueSection')),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < overdue.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: accentColor.withValues(alpha: 0.12),
                      child: const Icon(Icons.hourglass_empty_rounded, color: accentColor),
                    ),
                    title: Text(
                      '${overdue[i].well.name} · ${overdue[i].type.label}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(s('alertsOverdueSince'), style: TextStyle(color: scheme.onSurfaceVariant)),
                    trailing: role.canEnterData
                        ? FilledButton(
                            onPressed: () =>
                                context.push('/entry?wellId=${overdue[i].well.id}&typeId=${overdue[i].type.id}'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            child: Text(s('wellDetailAddAnalysis')),
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700));
  }
}
