import '../analysis/drift_detector.dart';
import '../analysis/series.dart';
import '../data/wells_repository.dart';
import '../l10n/app_strings.dart';
import '../plant/plant_repository.dart';
import '../theme/status_style.dart';

/// Une ligne du résumé du jour : gravité + texte déjà traduit.
class SummaryLine {
  final AppStatus status;
  final String text;
  const SummaryLine(this.status, this.text);
}

/// Résumé du jour calculé localement (aucun réseau, aucune IA) : ce qui
/// demande l'attention d'abord.
class DaySummary {
  final int done;
  final int total;
  final List<SummaryLine> lines;
  const DaySummary({required this.done, required this.total, required this.lines});

  bool get allClear => lines.isEmpty;
}

DaySummary buildDaySummary({
  required WellsState data,
  required WellsController wells,
  required PlantState plantState,
  required PlantController plant,
  required DateTime today,
  required String Function(String) s,
}) {
  var done = 0;
  var total = 0;
  var overdue = 0;
  final out = <String>[];
  final drifts = <String>[];
  for (final well in data.wells.where((w) => w.active)) {
    for (final type in data.analysisTypes.where((t) => t.isDueOn(today))) {
      total++;
      switch (wells.statusFor(well.id, type.id, now: today)) {
        case DailyStatus.done:
          done++;
        case DailyStatus.overdue:
          overdue++;
        case DailyStatus.pending:
          break;
      }
    }
    for (final type in data.analysisTypes) {
      final last = wells.lastRecord(well.id, type.id);
      if (last == null || !last.isSameDay(today)) continue;
      if (type.isOutOfRange(last.value)) {
        out.add('${well.name} · ${type.label} ${formatNumber(last.value)} ${type.unit}');
      } else {
        final drift = detectDrift(wells.recentValues(well.id, type.id, n: driftWindow + 1));
        if (drift != null) {
          final pct = drift.percent == null ? '' : ' (${formatPercent(drift.percent!, decimals: 0)})';
          drifts.add('${well.name} · ${type.label}$pct');
        }
      }
    }
  }

  final plantOut = <String>[];
  for (final point in plantState.points.where((p) => p.active)) {
    final analysis = plant.analysisOn(point.id, today);
    if (analysis == null) continue;
    final params = plant.outOfRange(point, analysis);
    if (params.isNotEmpty) plantOut.add('${point.code} · ${params.map((p) => s(p.labelKey)).join(', ')}');
  }

  String joined(List<String> items) => items.length <= 3 ? items.join(' ; ') : '${items.take(3).join(' ; ')} …';

  return DaySummary(
    done: done,
    total: total,
    lines: [
      if (overdue > 0) SummaryLine(AppStatus.late, fill(s('summaryOverdue'), {'n': '$overdue'})),
      if (out.isNotEmpty) SummaryLine(AppStatus.out, '${s('summaryOutOfRange')} : ${joined(out)}'),
      if (plantOut.isNotEmpty) SummaryLine(AppStatus.out, '${s('summaryPlantOut')} : ${joined(plantOut)}'),
      if (drifts.isNotEmpty) SummaryLine(AppStatus.todo, '${s('summaryDrift')} : ${joined(drifts)}'),
    ],
  );
}
