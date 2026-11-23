import '../import/analysis_importer.dart';

/// Statut d'un test (standard), d'une feuille ou d'une machine.
enum MachineStatus { ok, warning, incomplete, fault, notTested }

extension MachineStatusX on MachineStatus {
  int get severity => switch (this) {
        MachineStatus.fault => 4,
        MachineStatus.warning => 3,
        MachineStatus.incomplete => 2,
        MachineStatus.ok => 1,
        MachineStatus.notTested => 0,
      };
  String get label => switch (this) {
        MachineStatus.ok => 'Conforme',
        MachineStatus.warning => 'À surveiller',
        MachineStatus.incomplete => 'Incomplet',
        MachineStatus.fault => 'Non conforme',
        MachineStatus.notTested => 'Non testé',
      };
}

/// Tolérance : absolue (même unité que la mesure) ou relative (en %).
class CalTolerance {
  final bool relative;
  final double value;
  const CalTolerance.relative(this.value) : relative = true;
  const CalTolerance.absolute(this.value) : relative = false;

  String get text => relative ? '±$value %' : '±$value';

  /// Écart mesuré (en % ou en unité selon le mode).
  double error(double ref, double measured) {
    if (!relative) return measured - ref;
    return ref == 0 ? (measured == 0 ? 0 : double.infinity) : (measured - ref) / ref * 100;
  }

  bool passes(double ref, double measured) => error(ref, measured).abs() <= value + 1e-9;
}

/// Tolérance par défaut, d'après les critères des classeurs fournis :
/// pH ±0,05 · balance ±0,001 g · conductivité ±2 % · densimètre ±0,1 % ·
/// titrateur amine / Ti-Touch ±1 % · KF, chlorure, GC ±5 %.
CalTolerance defaultTolerance(String sheet) {
  final s = sheet.toLowerCase();
  if (s.startsWith('ph')) return const CalTolerance.absolute(0.05);
  if (s.contains('balance')) return const CalTolerance.absolute(0.001);
  if (s.contains('conductiv')) return const CalTolerance.relative(2);
  if (s.contains('density') || s.contains('densi')) return const CalTolerance.relative(0.1);
  if (s.contains('titrator') || s.contains('calibration_log')) return const CalTolerance.relative(1);
  return const CalTolerance.relative(5);
}

/// Une mesure de calibration : valeur de référence vs valeur mesurée.
class CalPoint {
  final String machine, sheet, standard;
  final double reference;
  final double? measured;
  final DateTime? date;
  final String operator;
  const CalPoint(this.machine, this.sheet, this.standard, this.reference, this.measured, this.date, this.operator);
}

class CalDataset {
  final List<CalPoint> points;
  final List<String> warnings;
  const CalDataset(this.points, this.warnings);
}

/// Résultat d'un standard (ex. « Buffer 7.01 ») sur toutes ses mesures.
class StandardResult {
  final String standard;
  final double reference;
  final int total, measuredCount, passCount, failCount, pendingCount;
  final double? meanError, worstError, stdDev, drift;
  final int suspectCount;
  final CalTolerance tolerance;
  final MachineStatus status;
  final String reason;
  const StandardResult({
    required this.standard,
    required this.reference,
    required this.total,
    required this.measuredCount,
    required this.passCount,
    required this.failCount,
    required this.pendingCount,
    required this.meanError,
    required this.worstError,
    required this.stdDev,
    required this.drift,
    required this.suspectCount,
    required this.tolerance,
    required this.status,
    required this.reason,
  });
}

class SheetResult {
  final String sheet;
  final List<StandardResult> standards;
  const SheetResult(this.sheet, this.standards);
  MachineStatus get status => _combine(standards.map((s) => s.status));
}

class MachineResult {
  final String machine;
  final List<SheetResult> sheets;
  const MachineResult(this.machine, this.sheets);

  Iterable<StandardResult> get _all => sheets.expand((s) => s.standards);
  int get total => _all.fold(0, (a, s) => a + s.total);
  int get measured => _all.fold(0, (a, s) => a + s.measuredCount);
  int get failed => _all.fold(0, (a, s) => a + s.failCount);
  int get pending => _all.fold(0, (a, s) => a + s.pendingCount);
  MachineStatus get status => _combine(_all.map((s) => s.status));
}

/// Pire statut mesuré gagne ; si rien n'est mesuré : non testé ; si une partie
/// seulement est mesurée et conforme : incomplet.
MachineStatus _combine(Iterable<MachineStatus> list) {
  final l = list.toList();
  if (l.isEmpty || l.every((s) => s == MachineStatus.notTested)) return MachineStatus.notTested;
  if (l.contains(MachineStatus.fault)) return MachineStatus.fault;
  if (l.contains(MachineStatus.warning)) return MachineStatus.warning;
  if (l.contains(MachineStatus.incomplete) || l.contains(MachineStatus.notTested)) return MachineStatus.incomplete;
  return MachineStatus.ok;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[éèêë]'), 'e')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Premier nombre d'un texte : « 500 mg/L as Cl » → 500.
double? _leadingNumber(String s) {
  final m = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(s.trim());
  return m == null ? null : double.tryParse(m.group(0)!.replaceAll(',', '.'));
}

String _machineFromFile(String fileName) => fileName
    .replaceAll(RegExp(r'\.(xlsx|xlsm|csv)$', caseSensitive: false), '')
    .replaceAll(RegExp(r'_?(Calibration|Verification)\w*$', caseSensitive: false), '')
    .replaceAll('_', ' ')
    .trim();

/// Lit un classeur de calibration : chaque feuille ayant une colonne de
/// référence/certifié et une colonne mesurée est un journal de tests.
/// Les autres feuilles (tendance, certificat) sont ignorées.
CalDataset parseCalibrationFile(String fileName, List<int> bytes) {
  final points = <CalPoint>[];
  final warnings = <String>[];
  var found = false;
  for (final t in readTables(fileName, bytes)) {
    final h = t.headers.map(_norm).toList();
    int firstWhere(bool Function(String) f, [int? not]) {
      for (var i = 0; i < h.length; i++) {
        if (i != not && f(h[i])) return i;
      }
      return -1;
    }

    var iRef = firstWhere((x) => x.contains('reference') || x.contains('certified'));
    if (iRef < 0) iRef = firstWhere((x) => x.contains('standard') && t.headers[h.indexOf(x)].contains('('));
    final iMeas = firstWhere((x) => x.contains('measured') || x.contains('result'));
    if (iRef < 0 || iMeas < 0) continue; // trend / certificate
    found = true;
    final iLabel = firstWhere((x) => const {'standard', 'bufferstandard', 'conductivitystandard', 'component'}.contains(x), iRef);
    final iInst = firstWhere((x) => x == 'instrument');
    final iSerial = firstWhere((x) => x.startsWith('serial'));
    final iDate = firstWhere((x) => x == 'date');
    final iOp = firstWhere((x) => x == 'operator');
    final fallback = _machineFromFile(fileName);
    for (final r in t.rows) {
      String c(int i) => (i >= 0 && i < r.length) ? r[i].trim() : '';
      final ref = _leadingNumber(c(iRef));
      if (ref == null) continue;
      final inst = c(iInst).isNotEmpty ? c(iInst) : fallback;
      final serial = c(iSerial);
      final machine = serial.isNotEmpty ? '$inst ($serial)' : inst;
      final label = c(iLabel).isNotEmpty ? c(iLabel) : _fmt(ref);
      points.add(CalPoint(machine, t.name, label, ref, parseImportNumber(c(iMeas)), iDate >= 0 ? parseImportDate(c(iDate)) : null, c(iOp)));
    }
  }
  if (!found) warnings.add('« $fileName » : aucune feuille de calibration reconnue (colonnes référence + mesuré).');
  return CalDataset(points, warnings);
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Teste chaque machine séparément. Pour chaque standard :
///  - mesure vide → en attente (jamais comptée comme échec) ;
///  - mesure hors tolérance → échec ;
///  - aucun test mesuré → « Non testé » ; au moins un échec → « Non conforme » ;
///    des mesures conformes mais d'autres en attente → « Incomplet » ;
///    tout conforme → « Conforme ».
/// `overrides` : tolérance saisie à l'écran, clé « machine|feuille ».
List<MachineResult> evaluateCalibration(List<CalPoint> points, {Map<String, CalTolerance> overrides = const {}}) {
  final tree = <String, Map<String, Map<String, List<CalPoint>>>>{};
  for (final p in points) {
    tree.putIfAbsent(p.machine, () => {}).putIfAbsent(p.sheet, () => {}).putIfAbsent(p.standard, () => []).add(p);
  }
  final out = <MachineResult>[];
  for (final m in (tree.keys.toList()..sort())) {
    final sheets = <SheetResult>[];
    for (final sh in tree[m]!.keys) {
      final tol = overrides[toleranceKey(m, sh)] ?? defaultTolerance(sh);
      final stds = <StandardResult>[];
      for (final entry in tree[m]![sh]!.entries) {
        final list = entry.value;
        final ref = list.first.reference;
        final done = list.where((p) => p.measured != null).toList();
        final errors = done.map((p) => tol.error(p.reference, p.measured!)).toList();
        final fails = done.where((p) => !tol.passes(p.reference, p.measured!)).length;
        final pending = list.length - done.length;
        // Mesure « 0 » alors que la référence ne l'est pas : saisie vide
        // probable (les feuilles de tendance remplissent 0) → suspecte, comptée en échec.
        final suspect = done.where((p) => p.measured == 0 && p.reference != 0).length;
        // Zone de vigilance : écart entre 80 % et 100 % de la tolérance.
        final warn = done.where((p) {
          final e = tol.error(p.reference, p.measured!).abs();
          return e <= tol.value + 1e-9 && e > tol.value * 0.8;
        }).length;
        // Dérive : pente de l'écart au fil des mesures (ordre du fichier, ou des dates).
        final ordered = [...done];
        if (ordered.every((p) => p.date != null)) ordered.sort((a, b) => a.date!.compareTo(b.date!));
        final errSeq = ordered.map((p) => tol.error(p.reference, p.measured!)).toList();
        final drift = _slope(errSeq);
        final drifting = errSeq.length >= 5 && drift != null && (drift * (errSeq.length - 1)).abs() > tol.value * 0.5 &&
            errSeq.last.abs() > errSeq.first.abs();
        final mean = errors.isEmpty ? null : errors.reduce((a, b) => a + b) / errors.length;
        double? sd;
        if (errors.length >= 2) {
          final mu = mean!;
          sd = _sqrt(errors.fold<double>(0, (a, e) => a + (e - mu) * (e - mu)) / (errors.length - 1));
        }
        MachineStatus st;
        String reason;
        if (done.isEmpty) {
          st = MachineStatus.notTested;
          reason = 'Aucune mesure saisie';
        } else if (fails > 0) {
          st = MachineStatus.fault;
          reason = suspect > 0
              ? '$fails mesure(s) hors tolérance ${tol.text} (dont $suspect valeur 0 suspecte)'
              : '$fails mesure(s) hors tolérance ${tol.text}';
        } else if (drifting) {
          st = MachineStatus.warning;
          reason = "Dérive de l'écart au fil des mesures (tolérance ${tol.text})";
        } else if (warn > 0) {
          st = MachineStatus.warning;
          reason = '$warn mesure(s) proche(s) de la limite ${tol.text}';
        } else if (pending > 0) {
          st = MachineStatus.incomplete;
          reason = '${done.length} mesure(s) conforme(s), $pending en attente';
        } else {
          st = MachineStatus.ok;
          reason = 'Toutes les mesures dans ${tol.text}';
        }
        stds.add(StandardResult(
          standard: entry.key,
          reference: ref,
          total: list.length,
          measuredCount: done.length,
          passCount: done.length - fails,
          failCount: fails,
          pendingCount: pending,
          meanError: mean,
          worstError: errors.isEmpty ? null : errors.reduce((a, b) => a.abs() >= b.abs() ? a : b),
          stdDev: sd,
          drift: drift,
          suspectCount: suspect,
          tolerance: tol,
          status: st,
          reason: reason,
        ));
      }
      sheets.add(SheetResult(sh, stds));
    }
    out.add(MachineResult(m, sheets));
  }
  return out;
}

String toleranceKey(String machine, String sheet) => '$machine|$sheet';

double _sqrt(double v) => v <= 0 ? 0 : _newton(v);
double _newton(double v) {
  var x = v;
  for (var i = 0; i < 30; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}

/// Pente (régression linéaire) de la série ; null si moins de 3 points.
double? _slope(List<double> y) {
  final n = y.length;
  if (n < 3) return null;
  final mx = (n - 1) / 2;
  final my = y.reduce((a, b) => a + b) / n;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (i - mx) * (y[i] - my);
    den += (i - mx) * (i - mx);
  }
  return den == 0 ? null : num / den;
}
