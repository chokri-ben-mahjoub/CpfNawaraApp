import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/report_tables.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/analysis_record.dart';
import '../../../core/models/analysis_type.dart';
import '../../../core/models/production_types.dart';
import '../../../core/models/user_role.dart';
import '../../../core/models/well.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/series_chart.dart';
import '../../../core/widgets/responsive.dart';
import 'widgets/production_chart.dart';
import 'widgets/record_edit_sheet.dart';
import 'widgets/well_analysis_cards.dart';

/// Exporte tout ce qui concerne un puits : analyses, production + ratios
/// calculés (GOR, WOR, GLR, PI) et journal des interventions — une feuille
/// Excel par thème (ou un fichier CSV par thème).
Future<void> _exportWell(WidgetRef ref, BuildContext context, Well well) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final data = ref.read(wellsControllerProvider);
  final controller = ref.read(wellsControllerProvider.notifier);
  await runExport(
    context: context,
    locale: locale,
    baseName: well.code,
    shareSubject: '${well.name} (${well.code})',
    tables: [
      analysesTable(data, controller.recordsForWell(well.id), s),
      productionTable(data, [well], s),
      interventionsTable(data, controller.interventionsForWell(well.id), s),
    ],
  );
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
    // Les 3 débits de production ont déjà leur propre carte dédiée
    // ("Production", avec courbe) : pas besoin de les répéter ici.
    const productionTypeIds = {oilFlowTypeId, gasFlowTypeId, waterFlowTypeId};
    final types = ref
        .watch(wellsControllerProvider)
        .analysisTypes
        .where((t) => !productionTypeIds.contains(t.id))
        .toList();
    final history = controller.recordsForWell(wellId).take(20).toList();
    final dateFormat = DateFormat('d MMM, HH:mm', locale.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(well.name),
        actions: [
          IconButton(
            tooltip: s('compareTitle'),
            icon: const Icon(Icons.compare_arrows),
            onPressed: () => context.push('/compare?mode=wells&wellA=$wellId'),
          ),
          IconButton(
            tooltip: s('exportTooltip'),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _exportWell(ref, context, well),
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
        padding: pagePadding(context, top: 8, bottom: 130),
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
          _ProductionCard(wellId: wellId),
          const SizedBox(height: 16),
          RatiosCard(wellId: wellId),
          const SizedBox(height: 16),
          DeclineCard(wellId: wellId),
          const SizedBox(height: 20),
          InterventionsSection(wellId: wellId),
          const SizedBox(height: 20),
          Text(
            s('wellDetailLastValues'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: isWideLayout(context) ? 4 : 2,
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
          Row(
            children: [
              Expanded(
                child: Text(
                  s('wellDetailHistory'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (history.isNotEmpty)
                TextButton(
                  onPressed: () => context.push('/wells/$wellId/history'),
                  child: Text(s('wellDetailViewAllHistory')),
                ),
            ],
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

/// Suivi du débit huile / gaz / eau pour ce puits : dernières valeurs +
/// courbes des 30 derniers jours superposées. S'efface proprement si aucun
/// de ces 3 types d'analyse n'existe (ex: catalogue personnalisé).
class _ProductionCard extends ConsumerWidget {
  final String wellId;
  const _ProductionCard({required this.wellId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    final data = ref.watch(wellsControllerProvider);
    String s(String key) => tr(locale, key);

    AnalysisType? typeOf(String id) {
      for (final t in data.analysisTypes) {
        if (t.id == id) return t;
      }
      return null;
    }

    final fluids = [
      (typeOf(oilFlowTypeId), s('productionOil'), const Color(0xFF2E7D32)),
      (typeOf(gasFlowTypeId), s('productionGas'), const Color(0xFFE53935)),
      (typeOf(waterFlowTypeId), s('productionWater'), const Color(0xFF1E88E5)),
    ].where((f) => f.$1 != null).toList();

    if (fluids.isEmpty) return const SizedBox.shrink();

    final since = DateTime.now().subtract(const Duration(days: 30));
    final series = [
      for (final (type, label, color) in fluids)
        ProductionSeries(
          label: label,
          unit: type!.unit,
          color: color,
          records: controller
              .recordsForWell(wellId)
              .where((r) => r.typeId == type.id && r.dateTime.isAfter(since))
              .toList()
            ..sort((a, b) => a.dateTime.compareTo(b.dateTime)),
        ),
    ];
    final hasData = series.any((s) => s.records.isNotEmpty);
    final markers = [
      for (final i in controller.interventionsForWell(wellId))
        if (!i.date.isBefore(DateTime(since.year, since.month, since.day))) (i.date, s(i.typeKey)),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s('productionTitle'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(s('productionSubtitle'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final ser in series) ...[
                  Expanded(child: _FlowStatTile(series: ser)),
                  if (ser != series.last) const SizedBox(width: 10),
                ],
              ],
            ),
            if (hasData) ...[
              const SizedBox(height: 16),
              ProductionChart(series: series, markers: markers),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  for (final ser in series)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: ser.color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('${ser.label} (${ser.unit})', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  if (markers.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 3,
                          height: 12,
                          color: interventionMarkerColor,
                        ),
                        const SizedBox(width: 6),
                        Text(s('interventionsTitle'), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FlowStatTile extends StatelessWidget {
  final ProductionSeries series;
  const _FlowStatTile({required this.series});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = series.records.isEmpty ? null : series.records.last;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: series.color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(series.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            last == null ? '—' : '${last.value} ${series.unit}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
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
    final role = ref.watch(currentRoleProvider);
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
      trailing: role.canEnterData ? Icon(Icons.edit_outlined, color: scheme.onSurfaceVariant, size: 20) : null,
      onTap: role.canEnterData ? () => showRecordEditSheet(context, record: record, type: type) : null,
    );
  }
}
