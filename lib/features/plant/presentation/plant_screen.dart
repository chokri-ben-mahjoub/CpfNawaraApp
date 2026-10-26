import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'report_send_sheet.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/analysis/series.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/config/shared_config.dart';
import '../../../core/export/export_format_sheet.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/export/pdf_export_settings.dart';
import '../report_options.dart';
import '../../../core/models/user_role.dart';
import '../../../core/plant/plant_catalog.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_style.dart';
import '../../../core/widgets/hero_header.dart';
import '../../../core/widgets/responsive.dart';
import '../plant_report.dart';
import 'plant_schema_screens.dart';
import 'widgets/plant_diagram.dart';
import 'widgets/plant_heatmap_view.dart';
import 'widgets/plant_trends_view.dart';
import '../../../core/widgets/app_loader.dart';

enum PlantView { diagram, list, trends, heatmap }

final plantViewProvider = StateProvider<PlantView>((ref) => PlantView.diagram);

String plantDayLabel(DateTime day, Locale locale, String Function(String) s) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return s('navToday');
  if (day == today.subtract(const Duration(days: 1)))
    return s('wellHistoryYesterday');
  return DateFormat('EEE d MMM yyyy', locale.languageCode).format(day);
}

/// Export Excel/CSV de toutes les analyses de l'usine : une feuille par
/// circuit, une colonne par paramètre (action de la barre du haut).
Future<void> exportPlantAnalyses(WidgetRef ref, BuildContext context) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final controller = ref.read(plantControllerProvider.notifier);
  final tables = <ExportTable>[];
  for (final circuit in ref.read(plantControllerProvider).circuits) {
    final points = controller.pointsOf(circuit);
    final params = <String, PlantParam>{
      for (final p in points)
        for (final param in p.params) param.key: param,
    }.values.toList();
    final rows = <List<Object?>>[];
    for (final point in points) {
      for (final a in controller.analysesFor(point.id)) {
        rows.add([
          DateOnly(a.date),
          a.startTime ?? '',
          a.endTime ?? '',
          point.code,
          point.name,
          for (final param in params)
            param.isNumeric
                ? a.number(param.key)
                : (a.values[param.key] == null
                      ? null
                      : s('${a.values[param.key]}')),
          s(a.source),
          a.operatorName,
          a.comment ?? '',
        ]);
      }
    }
    rows.sort(
      (a, b) => (b[0] as DateOnly).date.compareTo((a[0] as DateOnly).date),
    );
    tables.add(
      ExportTable(
        name: s(circuit.labelKey),
        headers: [
          s('colDate'),
          s('colStartTime'),
          s('colEndTime'),
          s('plantColPoint'),
          s('plantColName'),
          for (final param in params)
            param.unit.isEmpty
                ? s(param.labelKey)
                : '${s(param.labelKey)} (${param.unit})',
          s('plantColSource'),
          s('colOperator'),
          s('colComment'),
        ],
        rows: rows,
      ),
    );
  }
  await runExport(
    context: context,
    locale: locale,
    baseName: 'usine_analyses',
    tables: tables,
  );
}

/// Onglet "Usine" : schéma interactif ou liste par circuit, état du jour de
/// chaque point de prélèvement, rapport journalier PDF.
class PlantScreen extends ConsumerWidget {
  const PlantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final day = ref.watch(plantDayProvider);
    final view = ref.watch(plantViewProvider);
    final state = ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final points = state.points.where((p) => p.active).toList();
    final statuses = {for (final p in points) p.id: controller.status(p, day)};
    final analysed = statuses.values
        .where((st) => st != PlantStatus.missing)
        .length;
    final out = statuses.values
        .where((st) => st == PlantStatus.outOfRange)
        .length;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return ListView(
      padding: pagePadding(context, top: 8, bottom: 32),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: s('plantPreviousDay'),
              onPressed: () => ref.read(plantDayProvider.notifier).state = day
                  .subtract(const Duration(days: 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime(2000),
                    lastDate: today,
                  );
                  if (picked != null)
                    ref.read(plantDayProvider.notifier).state = picked;
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.event_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        plantDayLabel(day, locale, s),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: s('plantNextDay'),
              onPressed: day.isBefore(today)
                  ? () => ref.read(plantDayProvider.notifier).state = day.add(
                      const Duration(days: 1),
                    )
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        HeroHeader(
          icon: Icons.factory_outlined,
          title: s('navPlant'),
          subtitle:
              '${points.length} ${s('plantHeroPoints')} · ${state.circuits.length} ${s('plantHeroCircuits')}',
          pillLabel: out > 0
              ? s('plantStatusOut')
              : (points.isNotEmpty && analysed == points.length
                    ? s('plantHeroAllDone')
                    : s('plantHeroInProgress')),
          pillColor: out > 0
              ? AppStatus.out.color(scheme)
              : (points.isNotEmpty && analysed == points.length
                    ? AppStatus.ok.color(scheme)
                    : AppStatus.todo.color(scheme)),
          stats: [
            HeroStat(
              value: '$analysed/${points.length}',
              label: s('plantSummaryAnalysed'),
            ),
            HeroStat(
              value: '$out',
              label: s('plantSummaryOut'),
              valueColor: out > 0 ? const Color(0xFFFF8A80) : null,
            ),
            HeroStat(
              value: '${points.length - analysed}',
              label: s('plantSummaryMissing'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final viewSelector = SegmentedButton<PlantView>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: PlantView.diagram,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: constraints.maxWidth >= 560
                      ? Text(s('plantViewDiagram'))
                      : null,
                  tooltip: s('plantViewDiagram'),
                ),
                ButtonSegment(
                  value: PlantView.list,
                  icon: const Icon(Icons.view_list_outlined),
                  label: constraints.maxWidth >= 560
                      ? Text(s('plantViewList'))
                      : null,
                  tooltip: s('plantViewList'),
                ),
                ButtonSegment(
                  value: PlantView.trends,
                  icon: const Icon(Icons.show_chart),
                  label: constraints.maxWidth >= 560
                      ? Text(s('plantViewTrends'))
                      : null,
                  tooltip: s('plantViewTrends'),
                ),
                ButtonSegment(
                  value: PlantView.heatmap,
                  icon: const Icon(Icons.grid_view_rounded),
                  label: constraints.maxWidth >= 560
                      ? Text(s('plantViewHeatmap'))
                      : null,
                  tooltip: s('plantViewHeatmap'),
                ),
              ],
              selected: {view},
              onSelectionChanged: (sel) =>
                  ref.read(plantViewProvider.notifier).state = sel.first,
            );
            final report = FilledButton.tonalIcon(
              onPressed: () => _chooseReport(context, ref),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(s('plantReport')),
            );
            if (constraints.maxWidth < 640) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [viewSelector, const SizedBox(height: 8), report],
              );
            }
            return Row(
              children: [
                Expanded(child: viewSelector),
                const SizedBox(width: 8),
                report,
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        if (view == PlantView.diagram)
          _DiagramSection(day: day)
        else if (view == PlantView.trends)
          const PlantTrendsView()
        else if (view == PlantView.heatmap)
          const PlantHeatmapView()
        else
          for (final circuit in state.circuits)
            _CircuitSection(circuit: circuit, day: day),
      ],
    );
  }

  Future<void> _chooseReport(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    final allCircuits = ref.read(plantControllerProvider).circuits;
    String s(String key) => tr(locale, key);
    final circuits = await showModalBottomSheet<List<PlantCircuit>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                s('plantReportChoose'),
                style: Theme.of(sheetContext).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.select_all),
              title: Text(
                s('plantReportAllCircuits'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onTap: () => Navigator.of(sheetContext).pop(allCircuits),
            ),
            for (final c in allCircuits)
              ListTile(
                leading: Icon(c.icon, color: c.color),
                title: Text(s(c.labelKey)),
                onTap: () => Navigator.of(sheetContext).pop([c]),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (circuits == null || !context.mounted) return;
    final day = ref.read(plantDayProvider);
    final plantController = ref.read(plantControllerProvider.notifier);
    // Format d'abord : Excel / CSV exportent les mêmes données en tableaux ;
    // seul le PDF est le rapport mis en page.
    final fmt = await chooseExport(context, locale);
    if (fmt == null || !context.mounted) return;
    if (fmt.format != ExportFormat.pdf) {
      await exportWithChoice(
        context: context,
        locale: locale,
        choice: fmt,
        baseName: 'rapport_usine_${circuits.length == 1 ? s(circuits.first.labelKey) : s('plantReportAllShort')}_${plantDateKey(day)}',
        tables: plantReportTables(controller: plantController, day: day, circuits: circuits, s: s),
      );
      return;
    }
    final missingCount = [
      for (final c in circuits)
        for (final p in plantController.pointsOf(c))
          if (plantController.analysisOn(p.id, day) == null) p,
    ].length;
    // Des points sans analyse ce jour-là : on demande avant de générer s'il
    // faut les lister ("Non analysé") ou les laisser de côté (par défaut).
    var includeMissing = false;
    if (missingCount > 0) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(s('plantReportMissingTitle')),
          content: Text(
            fill(s('plantReportMissingBody'), {'n': '$missingCount'}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(s('plantReportMissingInclude')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(s('plantReportMissingExclude')),
            ),
          ],
        ),
      );
      if (choice == null || !context.mounted) return;
      includeMissing = choice;
    }
    final allCircuitsReport = circuits.length == ref.read(plantControllerProvider).circuits.length;
    final options = await askPlantReportOptions(
      context,
      s,
      kind: allCircuitsReport ? PdfReportKind.allCircuits : PdfReportKind.samples,
    );
    if (options == null || !context.mounted) return;
    final config = ref.read(sharedConfigProvider.notifier);
    final numberController = TextEditingController(
      text: '${config.peekNextReportNumber()}',
    );
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s('plantReportNumberTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: numberController,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 8),
            Text(s('plantReportNumberHint')),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              final n = int.tryParse(numberController.text);
              if (n != null && n > 0) Navigator.of(dialogContext).pop(n);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    numberController.dispose();
    if (chosen == null || !context.mounted) return;
    final reportNumber = await config.nextReportNumber(number: chosen);
    if (!context.mounted) return;
    final bytes = await runWithLoading(
      context,
      s('loadingReport'),
      () => buildPlantDailyReport(
        controller: ref.read(plantControllerProvider.notifier),
        day: day,
        circuits: circuits,
        s: s,
        languageCode: locale.languageCode,
        operatorName: ref.read(profileProvider)?.fullName ?? '',
        reportNumber: reportNumber,
        includeMissing: includeMissing,
        allCircuits: circuits.length == ref.read(plantControllerProvider).circuits.length,
        options: options,
      ),
    );
    if (!context.mounted) return;
    final scope = circuits.length == 1
        ? s(circuits.first.labelKey)
        : s('plantReportAllShort');
    final dayText = DateFormat('dd/MM/yyyy').format(day);
    await showReportSendSheet(
      context: context,
      locale: locale,
      fileName: 'rapport_usine_${scope}_${plantDateKey(day)}.pdf'.replaceAll(
        RegExp(r'[^A-Za-z0-9_.-]+'),
        '_',
      ),
      bytes: bytes,
      subject: '${await plantReportTitleOf(s, allCircuits: circuits.length == ref.read(plantControllerProvider).circuits.length)} N° $reportNumber — $dayText',
      body: fill(s('reportMailBody'), {
        'n': reportNumber,
        'date': dayText,
        'name': ref.read(profileProvider)?.fullName ?? '',
      }),
    );
  }
}

/// Exporte une seule analyse (une ligne de l'historique d'un point).
Future<void> exportSinglePlantAnalysis(
  WidgetRef ref,
  BuildContext context,
  SamplePoint point,
  PlantAnalysis analysis,
) => exportPlantAnalysesSelection(ref, context, point, [analysis]);

/// Choix des paramètres à exporter (ex: seulement TPH) : `null` = annulé,
/// ensemble vide = tous les paramètres.
Future<Set<String>?> askPlantParams(
  BuildContext context,
  SamplePoint point,
  List<PlantAnalysis> analyses,
  String Function(String) s,
) {
  final chosen = <String>{};
  // Seulement les paramètres réellement mesurés dans les analyses choisies.
  final available = [
    for (final param in point.params)
      if (analyses.any((a) => a.values[param.key] != null)) param,
  ];
  return showDialog<Set<String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => AlertDialog(
        title: Text(s('plantParamsTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s('plantParamsHint'),
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              for (final param in available)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(s(param.labelKey)),
                  value: chosen.contains(param.key),
                  onChanged: (v) => setState(
                    () => v == true
                        ? chosen.add(param.key)
                        : chosen.remove(param.key),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop({...chosen}),
            child: Text(s('ok')),
          ),
        ],
      ),
    ),
  );
}

/// Exporte les analyses choisies d'un point (une, plusieurs ou toutes) en
/// rapport PDF — même mise en page et mêmes options que le rapport
/// journalier, avec en plus le choix des paramètres (ex: seulement TPH).
Future<void> exportPlantAnalysesSelection(
  WidgetRef ref,
  BuildContext context,
  SamplePoint point,
  List<PlantAnalysis> analyses,
) async {
  if (analyses.isEmpty) return;
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final fmt = await chooseExport(context, locale);
  if (fmt == null || !context.mounted) return;
  final params = await askPlantParams(context, point, analyses, s);
  if (params == null || !context.mounted) return;
  if (fmt.format != ExportFormat.pdf) {
    final lastDay = analyses.map((a) => a.date).reduce((a, b) => a.isAfter(b) ? a : b);
    await exportWithChoice(
      context: context,
      locale: locale,
      choice: fmt,
      baseName: 'analyse_${point.code}_${plantDateKey(lastDay)}',
      tables: plantReportTables(
        controller: ref.read(plantControllerProvider.notifier),
        day: lastDay,
        circuits: [point.circuit],
        s: s,
        onlyPointId: point.id,
        analysisIds: {for (final a in analyses) a.id},
        paramKeys: params.isEmpty ? null : params,
      ),
    );
    return;
  }
  final options = await askPlantReportOptions(context, s);
  if (options == null || !context.mounted) return;
  final reportNumber = await ref
      .read(sharedConfigProvider.notifier)
      .nextReportNumber();
  if (!context.mounted) return;
  final latest = analyses
      .map((a) => a.date)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final bytes = await runWithLoading(
    context,
    s('loadingReport'),
    () => buildPlantDailyReport(
      controller: ref.read(plantControllerProvider.notifier),
      day: latest,
      circuits: [point.circuit],
      s: s,
      languageCode: locale.languageCode,
      operatorName: ref.read(profileProvider)?.fullName ?? '',
      reportNumber: reportNumber,
      options: options,
      onlyPointId: point.id,
      analysisIds: {for (final a in analyses) a.id},
      paramKeys: params.isEmpty ? null : params,
    ),
  );
  if (!context.mounted) return;
  final dayText = DateFormat('dd/MM/yyyy').format(latest);
  final suffix = analyses.length == 1
      ? analyses.first.samplingTime
      : '${analyses.length}x';
  await showReportSendSheet(
    context: context,
    locale: locale,
    fileName: 'analyse_${point.code}_${plantDateKey(latest)}_$suffix.pdf'
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_'),
    bytes: bytes,
    subject:
        '${await plantReportTitleOf(s)} N° $reportNumber - ${point.code} - $dayText',
    body: fill(s('reportMailBody'), {
      'n': reportNumber,
      'date': dayText,
      'name': ref.read(profileProvider)?.fullName ?? '',
    }),
  );
}

/// Feuille « Contenu du rapport » : le client coche ce qui doit apparaître ;
/// le choix est mémorisé pour les prochains exports.
Future<ReportOptions?> askPlantReportOptions(
  BuildContext context,
  String Function(String) s, {
  PdfReportKind kind = PdfReportKind.samples,
}) async {
  final settings = await PdfExportSettings.load(kind);
  final initial = ReportOptions.of(settings);
  if (!context.mounted) return null;
  final values = {for (final k in ReportOptions.keys) k: initial[k]};
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => AlertDialog(
        title: Text(s('reportOptTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final k in ReportOptions.keys)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(s('reportOpt_$k')),
                  value: values[k]!,
                  onChanged: (v) => setState(() => values[k] = v),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s('ok')),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  final chosen = ReportOptions.fromMap(values);
  await chosen.applyTo(settings).save();
  return chosen;
}

/// Vue "Schéma" : choix du schéma (s'il y en a plusieurs), configuration et
/// ajout pour l'administrateur, schéma interactif et légende.
class _DiagramSection extends ConsumerWidget {
  final DateTime day;
  const _DiagramSection({required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final plant = ref.watch(plantControllerProvider);
    final selectedId = ref.watch(plantSchemaIdProvider);
    String s(String key) => tr(locale, key);
    final schemas = plant.visibleSchemas;
    final schema = schemas.firstWhere(
      (sc) => sc.id == selectedId,
      orElse: () => schemas.first,
    );
    final unplaced = plant.points
        .where((p) => p.active && schema.positionOf(p) == null)
        .length;
    final admin = role.canConfigure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (schemas.length > 1 || admin)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final sc in schemas)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              showCheckmark: false,
                              avatar: Icon(plantSchemaIcon(sc.kind), size: 16),
                              selected: sc.id == schema.id,
                              label: Text(s(sc.name)),
                              onSelected: (_) =>
                                  ref
                                          .read(plantSchemaIdProvider.notifier)
                                          .state =
                                      sc.id,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (admin) ...[
                  IconButton(
                    tooltip: s('schemaConfigure'),
                    onPressed: () => context.push('/plant/schema/${schema.id}'),
                    icon: const Icon(Icons.tune),
                  ),
                  IconButton(
                    tooltip: s('schemaAdd'),
                    onPressed: () => addPlantSchema(context, ref),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                ],
              ],
            ),
          ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: PlantDiagram(
              schema: schema,
              day: day,
              onPointTap: (p) => showPlantPointSheet(context, p),
            ),
          ),
        ),
        const SizedBox(height: 10),
        PlantDiagramLegend(schema: schema),
        const SizedBox(height: 6),
        Text(
          s('plantDiagramHint'),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        if (unplaced > 0 && admin) ...[
          const SizedBox(height: 4),
          InkWell(
            onTap: () => context.push('/plant/schema/${schema.id}'),
            child: Text(
              fill(s('schemaUnplacedHint'), {'n': '$unplaced'}),
              style: TextStyle(
                fontSize: 12,
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CircuitSection extends ConsumerWidget {
  final PlantCircuit circuit;
  final DateTime day;
  const _CircuitSection({required this.circuit, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final points = controller.pointsOf(circuit);
    if (points.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(circuit.icon, color: circuit.color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s(circuit.labelKey),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                width: 26,
                height: 4,
                decoration: BoxDecoration(
                  color: circuit.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ResponsiveWrapGrid(
            minItemWidth: 340,
            spacing: 10,
            children: [for (final p in points) _PointTile(point: p, day: day)],
          ),
        ],
      ),
    );
  }
}

class _PointTile extends ConsumerWidget {
  final SamplePoint point;
  final DateTime day;
  const _PointTile({required this.point, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final status = controller.status(point, day);
    final color = plantStatusColor(status, scheme);
    final analysis = controller.analysisOn(point.id, day);
    final outParams = analysis == null
        ? const <PlantParam>[]
        : controller.outOfRange(point, analysis);
    final latest = controller.latest(point.id);

    final detail = switch (status) {
      PlantStatus.ok => s('plantStatusOk'),
      PlantStatus.outOfRange =>
        '${s('plantStatusOut')} : ${outParams.map((p) => s(p.labelKey)).join(', ')}',
      PlantStatus.missing =>
        latest == null
            ? s('plantNeverAnalysed')
            : '${s('plantLastAnalysis')} : ${DateFormat('d MMM', locale.languageCode).format(latest.date)}',
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/plant/point/${point.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: point.circuit.color, width: 3),
                ),
                child: Center(
                  child: Text(
                    point.code,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: status == PlantStatus.missing
                          ? scheme.surface
                          : Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      point.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      point.equipment,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: status == PlantStatus.missing
                            ? scheme.onSurfaceVariant
                            : color,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.visibility_outlined, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fiche rapide d'un point (depuis le schéma) : dernière analyse et accès à
/// la saisie, aux détails et tendances.
Future<void> showPlantPointSheet(BuildContext context, SamplePoint point) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _PointSheet(point: point),
  );
}

class _PointSheet extends ConsumerWidget {
  final SamplePoint point;
  const _PointSheet({required this.point});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final day = ref.watch(plantDayProvider);
    ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final analysis =
        controller.analysisOn(point.id, day) ?? controller.latest(point.id);
    final status = controller.status(point, day);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: point.circuit.color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      point.code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          point.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${s(point.circuit.labelKey)} · ${point.equipment}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PlantStatusChip(status: status),
                ],
              ),
              const SizedBox(height: 14),
              if (analysis == null)
                Text(
                  s('plantNeverAnalysed'),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              else ...[
                for (final a
                    in controller.analysesOnDay(point.id, day).isEmpty
                        ? [analysis]
                        : (controller.analysesOnDay(point.id, day).toList()
                            ..sort(
                              (x, y) =>
                                  x.samplingTime.compareTo(y.samplingTime),
                            ))) ...[
                  Text(
                    '${s('plantAnalysisOf')} ${DateFormat('EEEE d MMMM yyyy', locale.languageCode).format(a.date)} · ${a.samplingTime}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  PlantValuesTable(point: point, analysis: a),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (role.canEnterData)
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          context.push(
                            '/plant/entry/${point.id}?date=${plantDateKey(day)}',
                          );
                        },
                        icon: const Icon(Icons.edit_note),
                        label: Text(s('plantEnter')),
                      ),
                    ),
                  if (role.canEnterData) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push('/plant/point/${point.id}');
                      },
                      icon: const Icon(Icons.show_chart),
                      label: Text(s('plantDetailsTrends')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlantStatusChip extends ConsumerWidget {
  final PlantStatus status;
  const PlantStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final color = plantStatusColor(status, scheme);
    final key = switch (status) {
      PlantStatus.ok => 'plantStatusOk',
      PlantStatus.outOfRange => 'plantStatusOut',
      PlantStatus.missing => 'plantStatusMissing',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        tr(locale, key),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Tableau des valeurs d'une analyse : paramètre, valeur, unité, seuil,
/// valeur hors seuil en rouge. Toucher un paramètre numérique ouvre sa
/// courbe de tendance.
class PlantValuesTable extends ConsumerWidget {
  final SamplePoint point;
  final PlantAnalysis analysis;
  const PlantValuesTable({
    super.key,
    required this.point,
    required this.analysis,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final rows = <Widget>[];
    for (final param in point.params) {
      final value = analysis.values[param.key];
      final out = controller.isOut(point.id, param, value);
      final t = controller.threshold(point.id, param.key);
      final variation = param.isNumeric
          ? controller.variation(point.id, param.key, at: analysis.date)
          : null;
      final color = out == true
          ? scheme.error
          : (out == false ? Colors.green.shade700 : scheme.onSurface);
      final text = value == null
          ? '—'
          : param.isNumeric
          ? '${formatNumber((value as num).toDouble())}${param.unit.isEmpty ? '' : ' ${param.unit}'}'
          : s('$value');
      rows.add(
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: param.isNumeric
              ? () =>
                    context.push('/plant/point/${point.id}/trend/${param.key}')
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Row(
              children: [
                if (out == true)
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: scheme.error,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s(param.labelKey),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (t != null && param.isNumeric)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      t.label(formatNumber),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      text,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: color,
                      ),
                    ),
                    if (variation != null) ...[
                      const SizedBox(height: 2),
                      PlantVariationBadge(variation: variation),
                    ],
                  ],
                ),
                if (param.isNumeric)
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: rows),
    );
  }
}
