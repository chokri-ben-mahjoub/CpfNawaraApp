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
import '../../../core/theme/status_style.dart';
import '../../../core/widgets/hero_header.dart';
import '../../../core/widgets/modern_widgets.dart';
import '../../../core/widgets/series_chart.dart';
import '../../../core/widgets/sparkline.dart';
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
    final progress = controller.todayProgress(wellId);
    final since30 = DateTime.now().subtract(const Duration(days: 30));
    final last30 = controller.recordsForWell(wellId).where((r) => r.dateTime.isAfter(since30)).toList();
    final recent30 = last30.length;
    final out30 = last30.where((r) {
      final type = controller.findType(r.typeId);
      return type != null && type.isOutOfRange(r.value);
    }).length;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
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
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: s('wellTabOverview')),
              Tab(text: s('wellTabAnalyses')),
              Tab(text: s('wellTabHistory')),
              Tab(text: s('wellTabInterventions')),
            ],
          ),
        ),
        floatingActionButton: role.canEnterData
            ? FloatingActionButton.extended(
                onPressed: () => context.push('/entry?wellId=$wellId'),
                icon: const Icon(Icons.add),
                label: Text(s('wellDetailAddAnalysis')),
              )
            : null,
        body: TabBarView(
          children: [
            // Aperçu : identité du puits, santé, production, ratios, déclin.
            ListView(
              padding: pagePadding(context, top: 12, bottom: 130),
              children: [
                HeroHeader(
                  icon: Icons.water_drop_outlined,
                  title: well.name,
                  subtitle: well.group.trim().isEmpty ? well.code : '${well.code} · ${well.group.trim()}',
                  pillLabel: s(well.active ? 'wellStatusActive' : 'wellStatusStopped'),
                  pillColor: well.active ? AppStatus.ok.color(scheme) : scheme.outline,
                  stats: [
                    HeroStat(value: '${progress.$1}/${progress.$2}', label: s('wellKpiToday')),
                    HeroStat(value: '$recent30', label: s('wellKpi30d')),
                    HeroStat(
                      value: '$out30',
                      label: s('wellKpiOut'),
                      valueColor: out30 > 0 ? const Color(0xFFFF8A80) : null,
                    ),
                    HeroStat(
                      value: history.isEmpty
                          ? '—'
                          : DateFormat('d MMM', locale.languageCode).format(history.first.dateTime),
                      label: s('wellKpiLast'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _HealthBanner(wellId: wellId, types: types),
                const SizedBox(height: 16),
                _ProductionCard(wellId: wellId),
                const SizedBox(height: 16),
                RatiosCard(wellId: wellId),
                const SizedBox(height: 16),
                DeclineCard(wellId: wellId),
              ],
            ),
            // Analyses : dernières valeurs, regroupées par fiche de test.
            ListView(
              padding: pagePadding(context, top: 12, bottom: 130),
              children: [_GroupedLastValues(types: types, wellId: wellId, canEnterData: role.canEnterData)],
            ),
            // Historique : les 20 dernières analyses, avec lien vers
            // l'historique complet (paginé, filtrable par type).
            ListView(
              padding: pagePadding(context, top: 12, bottom: 130),
              children: [
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
            // Interventions : journal des travaux sur ce puits.
            ListView(
              padding: pagePadding(context, top: 12, bottom: 130),
              children: [InterventionsSection(wellId: wellId)],
            ),
          ],
        ),
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

/// Bandeau « santé du puits » : part des paramètres mesurés qui sont dans
/// leurs limites (dernière valeur de chacun), avec les paramètres hors limites
/// listés en pastilles cliquables.
class _HealthBanner extends ConsumerWidget {
  final String wellId;
  final List<AnalysisType> types;
  const _HealthBanner({required this.wellId, required this.types});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    var measured = 0;
    final out = <AnalysisType>[];
    for (final type in types) {
      final last = controller.lastRecord(wellId, type.id);
      if (last == null) continue;
      measured++;
      if (type.isOutOfRange(last.value)) out.add(type);
    }
    if (measured == 0) return const SizedBox.shrink();

    final score = (measured - out.length) / measured;
    final status = out.isEmpty ? AppStatus.ok : (score >= 0.75 ? AppStatus.todo : AppStatus.out);
    final color = status.color(scheme);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.05)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          CircularGauge(
            value: score,
            color: color,
            size: 72,
            strokeWidth: 8,
            center: Text(
              '${(score * 100).round()}%',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s('wellHealthTitle'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  out.isEmpty
                      ? s('wellHealthAllOk')
                      : fill(s('wellHealthSomeOut'), {'n': '${out.length}', 'total': '$measured'}),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color, height: 1.2),
                ),
                if (out.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final type in out)
                        InkWell(
                          borderRadius: BorderRadius.circular(100),
                          onTap: () => context.push('/wells/$wellId/trend/${type.id}'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              type.label,
                              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5),
                            ),
                          ),
                        ),
                    ],
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

/// Dernières valeurs, par section (ex: "Tête de puits", "Séparateur de
/// test") pour les types regroupés par l'Admin — comme sur une fiche de
/// test papier — puis les types restants, sans groupe, comme avant.
class _GroupedLastValues extends ConsumerWidget {
  final List<AnalysisType> types;
  final String wellId;
  final bool canEnterData;

  const _GroupedLastValues({required this.types, required this.wellId, required this.canEnterData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);

    final groupOrder = <String>[];
    final byGroup = <String, List<AnalysisType>>{};
    final ungrouped = <AnalysisType>[];
    for (final type in types) {
      if (type.group.isEmpty) {
        ungrouped.add(type);
      } else {
        (byGroup[type.group] ??= []).add(type);
        if (!groupOrder.contains(type.group)) groupOrder.add(type.group);
      }
    }

    Widget grid(List<AnalysisType> list) => GridView.count(
      crossAxisCount: isWideLayout(context) ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: isWideLayout(context) ? 1.45 : 1.18,
      children: [
        for (var i = 0; i < list.length; i++)
          FadeSlideIn(index: i, child: TapScale(child: _LastValueCard(type: list[i], wellId: wellId))),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ungrouped.isNotEmpty) ...[
          Text(
            s('wellDetailLastValues'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          grid(ungrouped),
        ],
        if (groupOrder.isNotEmpty && canEnterData) ...[
          SizedBox(height: ungrouped.isEmpty ? 0 : 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/entry/batch?wellId=$wellId'),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(s('entryBatchAction')),
            ),
          ),
        ],
        for (final group in groupOrder) ...[
          const SizedBox(height: 20),
          Text(
            group,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: accentColor),
          ),
          const SizedBox(height: 10),
          grid(byGroup[group]!),
        ],
      ],
    );
  }
}

/// Carte d'un paramètre : dernière valeur (rouge si hors limites), mini-courbe
/// des 12 dernières mesures, flèche de tendance et plage attendue.
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
    final color = outOfRange ? scheme.error : (last == null ? scheme.outline : const Color(0xFF2E7D32));

    final recent = controller.recordsForWell(wellId).where((r) => r.typeId == type.id).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final values = [for (final r in recent.skip(recent.length > 12 ? recent.length - 12 : 0)) r.value];
    final delta = values.length >= 2 ? values.last - values[values.length - 2] : null;
    String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/wells/$wellId/trend/${type.id}'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: outOfRange ? scheme.error : scheme.outlineVariant.withValues(alpha: 0.5), width: outOfRange ? 1.3 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    type.label,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (outOfRange) Icon(Icons.warning_amber_rounded, color: scheme.error, size: 17),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              last == null ? s('wellDetailNoValue') : '${last.value} ${type.unit}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: last == null ? 12 : 19,
                fontWeight: FontWeight.w800,
                color: outOfRange ? scheme.error : scheme.onSurface,
              ),
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: delta != null
                        ? TrendBadge(
                            delta: delta,
                            text: '${delta > 0 ? '+' : ''}${fmt(delta)}',
                            goodWhenUp: !outOfRange,
                          )
                        : Text(
                            '${fmt(type.min)} – ${fmt(type.max)}',
                            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                Sparkline(values: values, color: color, width: 52, height: 26),
              ],
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
