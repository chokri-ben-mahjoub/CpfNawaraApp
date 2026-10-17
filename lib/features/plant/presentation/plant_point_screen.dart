import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import 'plant_screen.dart';
import 'widgets/plant_diagram.dart';

/// Export Excel/CSV/PDF de l'historique d'un seul point de prélèvement
/// (toutes les analyses, une colonne par paramètre).
Future<void> _exportPoint(WidgetRef ref, BuildContext context, SamplePoint point) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final controller = ref.read(plantControllerProvider.notifier);
  final params = point.params;
  final rows = <List<Object?>>[
    for (final a in controller.analysesFor(point.id))
      [
        DateOnly(a.date),
        for (final param in params)
          param.isNumeric ? a.number(param.key) : (a.values[param.key] == null ? null : s('${a.values[param.key]}')),
        s(a.source),
        a.operatorName,
        a.comment ?? '',
      ],
  ];
  await runExport(
    context: context,
    locale: locale,
    baseName: point.code,
    shareSubject: '${point.name} (${point.code})',
    tables: [
      ExportTable(
        name: point.code,
        headers: [
          s('colDate'),
          for (final param in params) param.unit.isEmpty ? s(param.labelKey) : '${s(param.labelKey)} (${param.unit})',
          s('plantColSource'),
          s('colOperator'),
          s('colComment'),
        ],
        rows: rows,
      ),
    ],
  );
}

/// Fiche d'un point de prélèvement : analyse du jour consulté (ou la plus
/// récente), historique, seuils, accès aux courbes de tendance.
class PlantPointScreen extends ConsumerWidget {
  final String pointId;
  const PlantPointScreen({super.key, required this.pointId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final day = ref.watch(plantDayProvider);
    ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final point = controller.point(pointId);
    if (point == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(s('plantPointNotFound'))),
      );
    }
    final current = controller.analysisOn(point.id, day) ?? controller.latest(point.id);
    final history = controller.analysesFor(point.id);
    final dateFormat = DateFormat('EEE d MMM yyyy', locale.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text('${point.code} · ${point.name}'),
        actions: [
          IconButton(
            tooltip: s('exportTooltip'),
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: history.isEmpty ? null : () => _exportPoint(ref, context, point),
          ),
          if (role.canConfigure)
            IconButton(
              tooltip: s('plantThresholds'),
              icon: const Icon(Icons.tune),
              onPressed: () => showPlantThresholdsSheet(context, point),
            ),
        ],
      ),
      floatingActionButton: role.canEnterData
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/plant/entry/${point.id}?date=${plantDateKey(day)}'),
              icon: const Icon(Icons.edit_note),
              label: Text(s('plantEnter')),
            )
          : null,
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 120, maxWidth: 900),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: point.circuit.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(point.circuit.icon, color: point.circuit.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s(point.circuit.labelKey),
                          style: TextStyle(color: point.circuit.color, fontWeight: FontWeight.w800),
                        ),
                        Text(point.equipment, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  PlantStatusChip(status: controller.status(point, day)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (current == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(s('plantNeverAnalysed'), style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${s('plantAnalysisOf')} ${dateFormat.format(current.date)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (current.date != day)
                  Text(s('plantLatestAvailable'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                s(current.source),
                if (current.operatorName.isNotEmpty) current.operatorName,
                if (current.comment != null && current.comment!.isNotEmpty) current.comment!,
              ].join(' · '),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 10),
            PlantValuesTable(point: point, analysis: current),
            const SizedBox(height: 6),
            Text(s('plantTapForTrend'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
          const SizedBox(height: 22),
          Text(
            s('plantHistory'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (history.isEmpty)
            Text('—', style: TextStyle(color: scheme.onSurfaceVariant))
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < history.length && i < 60; i++) ...[
                    if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                    _HistoryTile(point: point, analysis: history[i], dateFormat: dateFormat),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  final SamplePoint point;
  final PlantAnalysis analysis;
  final DateFormat dateFormat;
  const _HistoryTile({required this.point, required this.analysis, required this.dateFormat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final out = controller.outOfRange(point, analysis);
    final status = out.isEmpty ? PlantStatus.ok : PlantStatus.outOfRange;
    final color = plantStatusColor(status, scheme);

    return ListTile(
      leading: Icon(out.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded, color: color),
      title: Text(dateFormat.format(analysis.date), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        out.isEmpty
            ? '${analysis.values.length} ${s('plantValuesCount')} · ${s(analysis.source)}'
            : '${s('plantStatusOut')} : ${out.map((p) => s(p.labelKey)).join(', ')}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: out.isEmpty ? scheme.onSurfaceVariant : color),
      ),
      trailing: role.canEnterData ? Icon(Icons.edit_outlined, size: 18, color: scheme.onSurfaceVariant) : null,
      onTap: role.canEnterData
          ? () => context.push('/plant/entry/${point.id}?analysisId=${analysis.id}')
          : null,
    );
  }
}

/// Seuils min/max de chaque paramètre numérique d'un point (vide = pas de
/// seuil : la valeur n'est jamais signalée hors seuil).
Future<void> showPlantThresholdsSheet(BuildContext context, SamplePoint point) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => _ThresholdsSheet(point: point),
  );
}

class _ThresholdsSheet extends ConsumerStatefulWidget {
  final SamplePoint point;
  const _ThresholdsSheet({required this.point});

  @override
  ConsumerState<_ThresholdsSheet> createState() => _ThresholdsSheetState();
}

class _ThresholdsSheetState extends ConsumerState<_ThresholdsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _min = <String, TextEditingController>{};
  final _max = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    final controller = ref.read(plantControllerProvider.notifier);
    String fmt(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
    for (final param in widget.point.params.where((p) => p.isNumeric)) {
      final t = controller.threshold(widget.point.id, param.key);
      _min[param.key] = TextEditingController(text: fmt(t?.min));
      _max[param.key] = TextEditingController(text: fmt(t?.max));
    }
  }

  @override
  void dispose() {
    for (final c in [..._min.values, ..._max.values]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parse(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(plantControllerProvider.notifier);
    for (final key in _min.keys) {
      final min = _parse(_min[key]!.text);
      final max = _parse(_max[key]!.text);
      final current = controller.threshold(widget.point.id, key);
      if (current?.min == min && current?.max == max) continue;
      await controller.setThreshold(widget.point.id, key, min, max);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(tr(ref.read(localeProvider), 'plantThresholdsSaved'))));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    String? numberOrEmpty(String? v) =>
        (v ?? '').trim().isEmpty || _parse(v!) != null ? null : s('adminInvalidThreshold');

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${s('plantThresholds')} · ${widget.point.code}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(s('plantThresholdsHint'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final param in widget.point.params.where((p) => p.isNumeric))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(
                                  param.unit.isEmpty ? s(param.labelKey) : '${s(param.labelKey)} (${param.unit})',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _min[param.key],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                decoration: InputDecoration(labelText: 'Min', isDense: true),
                                validator: numberOrEmpty,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _max[param.key],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                decoration: InputDecoration(labelText: 'Max', isDense: true),
                                validator: (v) {
                                  final base = numberOrEmpty(v);
                                  if (base != null) return base;
                                  final min = _parse(_min[param.key]!.text);
                                  final max = _parse(v ?? '');
                                  return min != null && max != null && min > max ? s('adminMinMaxOrder') : null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
                  onPressed: _save,
                  child: Text(s('wellsManageSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
