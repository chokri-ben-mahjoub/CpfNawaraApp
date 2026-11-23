import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../notifications/machine_notification_service.dart';
import 'machine_schedule.dart';
import 'machine_test.dart';

/// Création des tables (appelée à l'ouverture de la base). Tables locales :
/// non synchronisées ni sauvegardées avec les données du laboratoire.
Future<void> createMachineTables(DatabaseExecutor db) async {
  await db.execute('''
    create table if not exists machine_snapshots (
      id text primary key,
      machine text not null,
      imported_at integer not null,
      last_cal_ms integer,
      hash text not null,
      payload text not null
    )
  ''');
  await db.execute('create index if not exists idx_machine_snapshots_m on machine_snapshots(machine, imported_at)');
  await db.execute('''
    create table if not exists machine_settings (
      machine text primary key,
      interval_days integer not null default $defaultCalibrationIntervalDays,
      tolerances text not null default '{}'
    )
  ''');
}

/// Un import enregistré pour une machine.
class MachineSnapshot {
  final String id, machine, hash;
  final DateTime importedAt;
  final DateTime? lastCalibration;
  final List<CalPoint> points;
  const MachineSnapshot(this.id, this.machine, this.hash, this.importedAt, this.lastCalibration, this.points);
}

class MachineSettings {
  final int intervalDays;
  final Map<String, CalTolerance> tolerances; // clé = feuille
  const MachineSettings({this.intervalDays = defaultCalibrationIntervalDays, this.tolerances = const {}});

  Map<String, CalTolerance> toleranceOverrides(String machine) => {
        for (final e in tolerances.entries) toleranceKey(machine, e.key): e.value,
      };
}

/// État courant d'une machine : dernier import évalué + échéance + historique.
class MachineEntry {
  final MachineSnapshot latest;
  final MachineResult result;
  final MachineSettings settings;
  final DueInfo due;
  final List<MachineSnapshot> history; // du plus ancien au plus récent

  /// Résultat de chaque import de [history], calculé une fois au chargement
  /// (vide = à calculer à la demande, voir [historyResults]).
  final List<MachineResult> _historyCache;
  const MachineEntry(this.latest, this.result, this.settings, this.due, this.history, [this._historyCache = const []]);

  /// Résultats évalués de chaque import (avec les tolérances de la machine),
  /// sans recalcul à chaque affichage.
  List<MachineResult> get historyResults => _historyCache.length == history.length
      ? _historyCache
      : [for (final h in history) evaluateCalibration(h.points, overrides: settings.toleranceOverrides(machine)).first];
  String get machine => latest.machine;
}

class ImportReport {
  final int added, unchanged;
  final List<String> warnings;
  const ImportReport(this.added, this.unchanged, this.warnings);
}

/// Dernière date de calibration : date la plus récente d'une mesure saisie ;
/// à défaut de date dans le fichier, la date de l'import qui a apporté des
/// mesures. Aucune mesure saisie : jamais calibrée.
DateTime? lastCalibrationOf(List<CalPoint> points, DateTime importedAt) {
  final done = points.where((p) => p.measured != null).toList();
  if (done.isEmpty) return null;
  final dates = done.map((p) => p.date).whereType<DateTime>().toList();
  if (dates.isEmpty) return importedAt;
  return dates.reduce((a, b) => a.isAfter(b) ? a : b);
}

String _encodePoints(List<CalPoint> pts) => jsonEncode([
      for (final p in pts) [p.sheet, p.standard, p.reference, p.measured, p.date?.millisecondsSinceEpoch, p.operator],
    ]);

List<CalPoint> _decodePoints(String machine, String payload) => [
      for (final r in jsonDecode(payload) as List)
        CalPoint(machine, r[0] as String, r[1] as String, (r[2] as num).toDouble(), (r[3] as num?)?.toDouble(),
            r[4] == null ? null : DateTime.fromMillisecondsSinceEpoch((r[4] as num).toInt()), (r[5] as String?) ?? ''),
    ];

/// Empreinte stable du contenu (FNV-1a) pour ignorer un fichier réimporté à l'identique.
String contentHash(String s) {
  // Deux FNV-1a 32 bits (graines différentes) : valeurs sûres aussi en JavaScript (web).
  var h1 = 0x811c9dc5, h2 = 0x01000193;
  for (final c in s.codeUnits) {
    h1 = ((h1 ^ c) * 0x01000193) & 0xffffffff;
    h2 = ((h2 ^ c) * 0x85ebca6b) & 0xffffffff;
  }
  return '${h1.toRadixString(16)}-${h2.toRadixString(16)}-${s.length}';
}

final machineHistoryProvider = StateNotifierProvider<MachineHistoryController, AsyncValue<List<MachineEntry>>>(
  (ref) => MachineHistoryController(),
);

class MachineHistoryController extends StateNotifier<AsyncValue<List<MachineEntry>>> {
  MachineHistoryController() : super(const AsyncValue.loading()) {
    load();
  }

  final _uuid = const Uuid();

  Future<Database> get _db => LocalDatabase.instance.database;

  Future<void> load() async {
    try {
      final db = await _db;
      await createMachineTables(db);
      final rows = await db.query('machine_snapshots', orderBy: 'imported_at asc');
      final settingsRows = await db.query('machine_settings');
      final settings = <String, MachineSettings>{
        for (final r in settingsRows) r['machine'] as String: _settingsFromRow(r),
      };
      final byMachine = <String, List<MachineSnapshot>>{};
      for (final r in rows) {
        final m = r['machine'] as String;
        byMachine.putIfAbsent(m, () => []).add(MachineSnapshot(
              r['id'] as String,
              m,
              r['hash'] as String,
              DateTime.fromMillisecondsSinceEpoch((r['imported_at'] as num).toInt()),
              r['last_cal_ms'] == null ? null : DateTime.fromMillisecondsSinceEpoch((r['last_cal_ms'] as num).toInt()),
              _decodePoints(m, r['payload'] as String),
            ));
      }
      final now = DateTime.now();
      final entries = <MachineEntry>[];
      for (final m in (byMachine.keys.toList()..sort())) {
        final hist = byMachine[m]!;
        final latest = hist.last;
        final st = settings[m] ?? const MachineSettings();
        final overrides = st.toleranceOverrides(m);
        final histResults = [for (final h in hist) evaluateCalibration(h.points, overrides: overrides).first];
        final result = histResults.last;
        // Dernière calibration = la plus récente de tout l'historique.
        final last = hist.map((s) => s.lastCalibration).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
        entries.add(MachineEntry(latest, result, st, computeDue(last, st.intervalDays, now), hist, histResults));
      }
      state = AsyncValue.data(entries);
      // Alertes : notifiées une fois par alerte, ici et non à chaque affichage.
      unawaited(MachineNotificationService.notify(buildMachineAlerts(entries)));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  MachineSettings _settingsFromRow(Map<String, Object?> r) {
    final tol = <String, CalTolerance>{};
    try {
      (jsonDecode(r['tolerances'] as String? ?? '{}') as Map).forEach((k, v) {
        final rel = v['rel'] == true;
        final val = (v['v'] as num).toDouble();
        tol[k as String] = rel ? CalTolerance.relative(val) : CalTolerance.absolute(val);
      });
    } catch (_) {}
    return MachineSettings(intervalDays: (r['interval_days'] as num?)?.toInt() ?? defaultCalibrationIntervalDays, tolerances: tol);
  }

  /// Enregistre les points importés : un nouvel instantané par machine, sauf si
  /// son contenu est identique au dernier (réimport du même fichier).
  Future<ImportReport> saveImport(List<CalPoint> points, List<String> warnings) async {
    final db = await _db;
    final byMachine = <String, List<CalPoint>>{};
    for (final p in points) {
      byMachine.putIfAbsent(p.machine, () => []).add(p);
    }
    var added = 0, unchanged = 0;
    final now = DateTime.now();
    for (final e in byMachine.entries) {
      final payload = _encodePoints(e.value);
      final hash = contentHash(payload);
      final last = await db.query('machine_snapshots', where: 'machine = ?', whereArgs: [e.key], orderBy: 'imported_at desc', limit: 1);
      if (last.isNotEmpty && last.first['hash'] == hash) {
        unchanged++;
        continue;
      }
      final cal = lastCalibrationOf(e.value, now);
      await db.insert('machine_snapshots', {
        'id': 'ms_${_uuid.v4()}',
        'machine': e.key,
        'imported_at': now.millisecondsSinceEpoch,
        'last_cal_ms': cal?.millisecondsSinceEpoch,
        'hash': hash,
        'payload': payload,
      });
      added++;
    }
    await load();
    return ImportReport(added, unchanged, warnings);
  }

  Future<void> _ensureSettings(String machine) async {
    final db = await _db;
    await db.insert('machine_settings', {'machine': machine}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> setInterval(String machine, int days) async {
    final db = await _db;
    await _ensureSettings(machine);
    await db.update('machine_settings', {'interval_days': days.clamp(1, 3650)}, where: 'machine = ?', whereArgs: [machine]);
    await load();
  }

  Future<void> setTolerance(String machine, String sheet, CalTolerance tol) async {
    final db = await _db;
    await _ensureSettings(machine);
    final cur = state.valueOrNull?.where((e) => e.machine == machine).firstOrNull?.settings.tolerances ?? const {};
    final all = {...cur, sheet: tol};
    await db.update(
      'machine_settings',
      {'tolerances': jsonEncode({for (final e in all.entries) e.key: {'rel': e.value.relative, 'v': e.value.value}})},
      where: 'machine = ?',
      whereArgs: [machine],
    );
    await load();
  }

  Future<void> deleteMachine(String machine) async {
    final db = await _db;
    await db.delete('machine_snapshots', where: 'machine = ?', whereArgs: [machine]);
    await db.delete('machine_settings', where: 'machine = ?', whereArgs: [machine]);
    await load();
  }
}

/// Alertes à partir de l'état courant : non conformité, surveillance, échéance.
List<MachineAlert> buildMachineAlerts(List<MachineEntry> entries) {
  final out = <MachineAlert>[];
  for (final e in entries) {
    final r = e.result;
    switch (r.status) {
      case MachineStatus.fault:
        out.add(MachineAlert(e.machine, AlertLevel.critical, 'Machine non conforme', '${r.failed} mesure(s) hors tolérance — ${r.recommendation}'));
      case MachineStatus.warning:
        out.add(MachineAlert(e.machine, AlertLevel.warning, 'Machine à surveiller', r.verdict));
      case MachineStatus.incomplete:
        out.add(MachineAlert(e.machine, AlertLevel.info, 'Test incomplet', '${r.pending} mesure(s) en attente'));
      default:
        break;
    }
    switch (e.due.state) {
      case DueState.overdue:
        out.add(MachineAlert(e.machine, AlertLevel.critical, 'Recalibration en retard', e.due.label));
      case DueState.soon:
        out.add(MachineAlert(e.machine, AlertLevel.warning, 'Recalibration bientôt due', e.due.label));
      case DueState.unknown:
        out.add(MachineAlert(e.machine, AlertLevel.info, 'Jamais calibrée', 'Aucune mesure saisie pour cette machine'));
      case DueState.ok:
        break;
    }
  }
  out.sort((a, b) => a.level.index.compareTo(b.level.index));
  return out;
}
