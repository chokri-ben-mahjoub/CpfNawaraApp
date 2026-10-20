import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/config/shared_config.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/analysis_type.dart';
import '../../../core/models/user_role.dart';
import '../../../core/models/well.dart';
import '../../../core/plant/plant_catalog.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';

/// Exporte les analyses en retard et les dernières valeurs hors seuil, tous
/// puits actifs confondus (utile pour un rapport HSE).
Future<void> exportAlerts(WidgetRef ref, BuildContext context) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);

  final data = ref.read(wellsControllerProvider);
  final controller = ref.read(wellsControllerProvider.notifier);
  final today = DateTime.now();
  final activeWells = data.wells.where((w) => w.active).toList();

  final rows = <List<Object?>>[];
  for (final well in activeWells) {
    for (final type in data.analysisTypes) {
      final last = controller.lastRecord(well.id, type.id);
      if (type.isDueOn(today) && controller.statusFor(well.id, type.id, now: today) == DailyStatus.overdue) {
        rows.add([
          s('alertsOverdueSection'),
          '${well.name} (${well.code})',
          type.label,
          last?.dateTime,
          last?.value,
          type.unit,
          '${type.min} – ${type.max}',
        ]);
      }
      if (last != null && type.isOutOfRange(last.value) && last.isSameDay(today)) {
        rows.add([
          s('alertsOutOfRangeSection'),
          '${well.name} (${well.code})',
          type.label,
          last.dateTime,
          last.value,
          type.unit,
          '${type.min} – ${type.max}',
        ]);
      }
    }
  }

  final plant = ref.read(plantControllerProvider.notifier);
  final pastDeadline = ref.read(sharedConfigProvider).isPastDeadline(today);
  for (final point in ref.read(plantControllerProvider).points.where((p) => p.active)) {
    final analysis = plant.analysisOn(point.id, today);
    if (analysis == null) {
      if (pastDeadline) {
        rows.add([
          s('alertsPlantMissingSection'),
          '${point.code} — ${point.name}',
          s(point.circuit.labelKey),
          null,
          null,
          '',
          '',
        ]);
      }
      continue;
    }
    for (final param in plant.outOfRange(point, analysis)) {
      final value = analysis.values[param.key];
      rows.add([
        s('alertsPlantOutSection'),
        '${point.code} — ${point.name}',
        s(param.labelKey),
        analysis.date,
        value is num ? value.toDouble() : s('$value'),
        param.unit,
        () {
          final t = plant.threshold(point.id, param.key);
          return t == null ? '' : '${t.min ?? ''} – ${t.max ?? ''}';
        }(),
      ]);
    }
  }

  await runExport(
    context: context,
    locale: locale,
    baseName: 'alertes',
    tables: [
      ExportTable(
        name: s('navAlerts'),
        headers: [
          s('colStatus'),
          s('colWell'),
          s('colType'),
          s('colLastEntry'),
          s('colValue'),
          s('colUnit'),
          s('trendThreshold'),
        ],
        rows: rows,
      ),
    ],
  );
}

class _OverdueItem {
  final Well well;
  final AnalysisType type;

  /// Attendue aujourd'hui, pas encore reçue après l'heure limite (sinon : en
  /// retard depuis plusieurs jours).
  final bool today;
  const _OverdueItem(this.well, this.type, {this.today = false});
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
    final shared = ref.watch(sharedConfigProvider);
    final pastDeadline = shared.isPastDeadline(today);
    final deadline = formatDeadline(shared.missingDeadline);

    final overdue = <_OverdueItem>[];
    final outOfRange = <_OutOfRangeItem>[];
    for (final well in activeWells) {
      for (final type in data.analysisTypes) {
        final status = type.isDueOn(today) ? controller.statusFor(well.id, type.id, now: today) : null;
        if (status == DailyStatus.overdue) {
          overdue.add(_OverdueItem(well, type));
        } else if (status == DailyStatus.pending && pastDeadline) {
          overdue.add(_OverdueItem(well, type, today: true));
        }
        final last = controller.lastRecord(well.id, type.id);
        if (last != null && type.isOutOfRange(last.value) && last.isSameDay(today)) {
          outOfRange.add(_OutOfRangeItem(well, type, last.value));
        }
      }
    }

    ref.watch(plantControllerProvider);
    final plant = ref.read(plantControllerProvider.notifier);
    final plantPoints = ref.read(plantControllerProvider).points.where((p) => p.active).toList();
    final plantOut = <(SamplePoint, List<PlantParam>)>[];
    final plantMissing = <SamplePoint>[];
    for (final point in plantPoints) {
      final analysis = plant.analysisOn(point.id, today);
      if (analysis == null) {
        // Non reçue : seulement après l'heure limite du jour.
        if (pastDeadline) plantMissing.add(point);
      } else {
        final out = plant.outOfRange(point, analysis);
        if (out.isNotEmpty) plantOut.add((point, out));
      }
    }

    final hasAlerts = overdue.isNotEmpty || outOfRange.isNotEmpty || plantOut.isNotEmpty || plantMissing.isNotEmpty;

    return ListView(
      padding: pagePadding(context, top: 8, bottom: 24),
      children: [
        if (!hasAlerts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text(
                s('alertsEmpty'),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        if (plantOut.isNotEmpty) ...[
          _SectionTitle(s('alertsPlantOutSection')),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < plantOut.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.error.withValues(alpha: 0.12),
                      child: Text(
                        plantOut[i].$1.code,
                        style: TextStyle(color: scheme.error, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                    title: Text(
                      '${plantOut[i].$1.name} · ${s(plantOut[i].$1.circuit.labelKey)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      plantOut[i].$2.map((p) => s(p.labelKey)).join(', '),
                      style: TextStyle(color: scheme.error),
                    ),
                    trailing: const Icon(Icons.visibility_outlined),
                    onTap: () => context.push('/plant/point/${plantOut[i].$1.id}'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
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
                    trailing: const Icon(Icons.visibility_outlined),
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
          // Regroupé par puits : une ligne par puits, le détail se déplie.
          Builder(
            builder: (context) {
              final byWell = <Well, List<_OverdueItem>>{};
              for (final item in overdue) {
                byWell.putIfAbsent(item.well, () => []).add(item);
              }
              final groups = byWell.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
              return Card(
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: Column(
                    children: [
                      for (var g = 0; g < groups.length; g++) ...[
                        if (g > 0) Divider(height: 1, color: scheme.outlineVariant),
                        ExpansionTile(
                          initiallyExpanded: groups.length == 1,
                          leading: CircleAvatar(
                            backgroundColor: accentColor.withValues(alpha: 0.12),
                            child: const Icon(Icons.hourglass_empty_rounded, color: accentColor),
                          ),
                          title: Text(
                            '${groups[g].key.name} · ${groups[g].key.code}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            fill(s('alertsOverdueCount'), {'n': '${groups[g].value.length}'}),
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          children: [
                            for (final item in groups[g].value)
                              ListTile(
                                dense: true,
                                title: Text(item.type.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  item.today ? fill(s('alertsNotReceived'), {'time': deadline}) : s('alertsOverdueSince'),
                                ),
                                trailing: role.canEnterData
                                    ? FilledButton(
                                        onPressed: () => context.push('/entry?wellId=${item.well.id}&typeId=${item.type.id}'),
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
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
        if (plantMissing.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionTitle('${s('alertsPlantMissingSection')} (> $deadline)'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final point in plantMissing)
                ActionChip(
                  avatar: Icon(point.circuit.icon, size: 16, color: point.circuit.color),
                  label: Text('${point.code} · ${point.name}'),
                  onPressed: role.canEnterData
                      ? () => context.push('/plant/entry/${point.id}?date=${plantDateKey(today)}')
                      : () => context.push('/plant/point/${point.id}'),
                ),
            ],
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
