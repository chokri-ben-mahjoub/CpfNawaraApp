import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/excel_exporter.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/analysis_record.dart';
import '../../../core/models/analysis_type.dart';
import '../../../core/models/user_role.dart';
import '../../../core/models/well.dart';
import '../../../core/theme/app_theme.dart';

/// Exporte en Excel tout l'historique d'analyses d'un puits.
Future<void> _exportWellHistory(WidgetRef ref, BuildContext context, Well well) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(wellsControllerProvider.notifier);
  final history = controller.recordsForWell(well.id);

  if (history.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(s('exportEmpty'))));
    return;
  }

  messenger.showSnackBar(SnackBar(content: Text(s('exportStarted'))));
  final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  try {
    final rows = [
      for (final record in history)
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
    await ExcelExporter.exportAndShare(
      fileName: '${well.code}_$suffix.xlsx',
      headers: [
        s('colDate'),
        s('colType'),
        s('colValue'),
        s('colUnit'),
        s('colService'),
        s('colOperator'),
        s('colComment'),
      ],
      rows: rows,
      shareSubject: '${well.name} (${well.code})',
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(s('exportError'))));
  }
}

class WellDetailScreen extends ConsumerWidget {
  final String wellId;

  const WellDetailScreen({super.key, required this.wellId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    ref.watch(wellsControllerProvider); // reconstruit l'écran après chaque nouvelle saisie
    String s(String key) => tr(locale, key);

    final well = controller.wellById(wellId);
    final types = ref.watch(wellsControllerProvider).analysisTypes;
    final history = controller.recordsForWell(wellId).take(20).toList();
    final dateFormat = DateFormat('d MMM, HH:mm', locale.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(well.name),
        actions: [
          IconButton(
            tooltip: s('exportTooltip'),
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () => _exportWellHistory(ref, context, well),
          ),
        ],
      ),
      floatingActionButton: role.canEnterData
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/entry?wellId=$wellId'),
              icon: const Icon(Icons.add),
              label: Text(s('wellDetailAddAnalysis')),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: (well.active ? accentColor : scheme.outline).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.water_drop_outlined, color: well.active ? accentColor : scheme.outline),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(well.code, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          s(well.active ? 'wellStatusActive' : 'wellStatusStopped'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: well.active ? Colors.green.shade600 : scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            s('wellDetailLastValues'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.5,
            children: [
              for (final type in types) _LastValueCard(type: type, wellId: wellId),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            s('wellDetailHistory'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(s('wellDetailNoHistory'), style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < history.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                    _HistoryTile(
                      record: history[i],
                      type: controller.typeById(history[i].typeId),
                      dateFormat: dateFormat,
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

class _LastValueCard extends ConsumerWidget {
  final AnalysisType type;
  final String wellId;

  const _LastValueCard({required this.type, required this.wellId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final last = controller.lastRecord(wellId, type.id);
    final outOfRange = last != null && type.isOutOfRange(last.value);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/wells/$wellId/trend/${type.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: outOfRange ? Border.all(color: scheme.error, width: 1.2) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    type.label,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (outOfRange) Icon(Icons.warning_amber_rounded, color: scheme.error, size: 18),
              ],
            ),
            const Spacer(),
            Text(
              last == null ? s('wellDetailNoValue') : '${last.value} ${type.unit}',
              style: TextStyle(
                fontSize: last == null ? 12 : 18,
                fontWeight: FontWeight.w800,
                color: outOfRange ? scheme.error : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  final AnalysisRecord record;
  final AnalysisType type;
  final DateFormat dateFormat;

  const _HistoryTile({required this.record, required this.type, required this.dateFormat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final outOfRange = type.isOutOfRange(record.value);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (outOfRange ? scheme.error : accentColor).withValues(alpha: 0.12),
        child: Icon(
          outOfRange ? Icons.warning_amber_rounded : Icons.science_outlined,
          color: outOfRange ? scheme.error : accentColor,
          size: 20,
        ),
      ),
      title: Text('${type.label} — ${record.value} ${type.unit}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${s(record.serviceKey)} · ${record.operatorName} · ${dateFormat.format(record.dateTime)}',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
    );
  }
}
