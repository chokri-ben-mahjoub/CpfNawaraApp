import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/analysis_record.dart';
import '../models/analysis_type.dart';
import '../models/well.dart';
import 'local_database.dart';

/// État courant du périmètre "puits / types d'analyse / analyses", reflet de
/// la base locale (voir `local_database.dart`).
class WellsState {
  final List<Well> wells;
  final List<AnalysisType> analysisTypes;
  final List<AnalysisRecord> records;

  const WellsState({
    required this.wells,
    required this.analysisTypes,
    required this.records,
  });

  static const empty = WellsState(wells: [], analysisTypes: [], records: []);

  WellsState copyWith({
    List<Well>? wells,
    List<AnalysisType>? analysisTypes,
    List<AnalysisRecord>? records,
  }) =>
      WellsState(
        wells: wells ?? this.wells,
        analysisTypes: analysisTypes ?? this.analysisTypes,
        records: records ?? this.records,
      );
}

enum DailyStatus { done, pending, overdue }

/// Une occurrence d'analyse attendue (type + date) non réalisée sur la
/// période consultée (vue semaine/mois du tableau de bord).
class MissingOccurrence {
  final AnalysisType type;
  final DateTime date;
  const MissingOccurrence({required this.type, required this.date});
}

/// Progression d'un puits sur une période (semaine/mois) : combien
/// d'occurrences attendues ont bien été saisies le jour prévu, et lesquelles
/// manquent encore (dates déjà passées sans analyse correspondante).
class PeriodProgress {
  final int done;
  final int total;
  final List<MissingOccurrence> missing;
  const PeriodProgress({required this.done, required this.total, required this.missing});
}

/// Libellé affiché pour les puits sans groupe assigné.
const unassignedGroupLabel = 'Sans groupe';

/// Statistiques d'un puits sur une période : nombre d'analyses saisies,
/// combien sont hors seuil, et taux de conformité (1.0 = tout est dans les
/// seuils, ou aucune analyse saisie).
class WellStats {
  final Well well;
  final int totalRecords;
  final int outOfRangeCount;

  const WellStats({required this.well, required this.totalRecords, required this.outOfRangeCount});

  double get complianceRate => totalRecords == 0 ? 1.0 : (totalRecords - outOfRangeCount) / totalRecords;
}

/// Statistiques agrégées d'un groupe (zone/champ) de puits sur une période.
class GroupStats {
  final String group;
  final List<WellStats> wells;

  const GroupStats({required this.group, required this.wells});

  int get totalRecords => wells.fold(0, (sum, w) => sum + w.totalRecords);
  int get outOfRangeCount => wells.fold(0, (sum, w) => sum + w.outOfRangeCount);
  double get complianceRate => totalRecords == 0 ? 1.0 : (totalRecords - outOfRangeCount) / totalRecords;
}

class WellsController extends StateNotifier<WellsState> {
  WellsController() : super(WellsState.empty) {
    _load();
  }

  static const _uuid = Uuid();

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final wells = (await db.query('wells')).map(_wellFromRow).toList();
    final types = (await db.query('analysis_types')).map(_typeFromRow).toList();
    final records = (await db.query('analysis_records')).map(_recordFromRow).toList();
    state = WellsState(wells: wells, analysisTypes: types, records: records);
  }

  Well wellById(String id) => state.wells.firstWhere((w) => w.id == id);

  AnalysisType typeById(String id) => state.analysisTypes.firstWhere((t) => t.id == id);

  List<AnalysisRecord> recordsForWell(String wellId) {
    final list = state.records.where((r) => r.wellId == wellId).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return list;
  }

  /// Dernier enregistrement pour un puits et un type d'analyse donnés
  /// (le plus récent, toutes dates confondues).
  AnalysisRecord? lastRecord(String wellId, String typeId) {
    final matches = state.records.where((r) => r.wellId == wellId && r.typeId == typeId).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return matches.isEmpty ? null : matches.first;
  }

  /// Enregistrement du jour pour un puits et un type, s'il existe déjà.
  AnalysisRecord? todayRecord(String wellId, String typeId, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final last = lastRecord(wellId, typeId);
    if (last != null && last.isSameDay(today)) return last;
    return null;
  }

  DailyStatus statusFor(String wellId, String typeId, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final last = lastRecord(wellId, typeId);
    if (last != null && last.isSameDay(today)) return DailyStatus.done;

    final type = typeById(typeId);
    final daysSinceLast =
        last == null ? 999 : today.difference(DateTime(last.dateTime.year, last.dateTime.month, last.dateTime.day)).inDays;
    return daysSinceLast > type.graceDays ? DailyStatus.overdue : DailyStatus.pending;
  }

  /// Nombre d'analyses attendues aujourd'hui pour un puits, et combien sont
  /// déjà faites.
  (int done, int total) todayProgress(String wellId, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final dueTypes = state.analysisTypes.where((t) => t.isDueOn(today));
    var done = 0;
    var total = 0;
    for (final type in dueTypes) {
      total++;
      if (statusFor(wellId, type.id, now: today) == DailyStatus.done) done++;
    }
    return (done, total);
  }

  /// Dates (minuit) comprises entre [start] et [end] inclus où [type] est
  /// attendu — base de la vue semaine/mois du tableau de bord.
  List<DateTime> dueDatesInRange(AnalysisType type, DateTime start, DateTime end) {
    final dates = <DateTime>[];
    var day = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!day.isAfter(last)) {
      if (type.isDueOn(day)) dates.add(day);
      day = day.add(const Duration(days: 1));
    }
    return dates;
  }

  bool _hasRecordOnDay(String wellId, String typeId, DateTime day) {
    return state.records.any((r) => r.wellId == wellId && r.typeId == typeId && r.isSameDay(day));
  }

  /// Progression d'un puits sur une période (semaine/mois) : une occurrence
  /// compte comme "faite" si une valeur a été saisie le jour même où elle
  /// était attendue. Les occurrences déjà passées sans valeur apparaissent
  /// dans `missing` ; celles encore à venir ne comptent pas comme manquantes.
  PeriodProgress periodProgress(String wellId, DateTime start, DateTime end) {
    final today = DateTime.now();
    var done = 0;
    var total = 0;
    final missing = <MissingOccurrence>[];
    for (final type in state.analysisTypes) {
      for (final day in dueDatesInRange(type, start, end)) {
        total++;
        if (_hasRecordOnDay(wellId, type.id, day)) {
          done++;
        } else if (!day.isAfter(today)) {
          missing.add(MissingOccurrence(type: type, date: day));
        }
      }
    }
    missing.sort((a, b) => a.date.compareTo(b.date));
    return PeriodProgress(done: done, total: total, missing: missing);
  }

  /// Ajoute (ou remplace, si [replaceId] est fourni) un enregistrement.
  Future<void> addRecord({
    required String wellId,
    required String typeId,
    required double value,
    required String serviceKey,
    required String operatorName,
    String? operatorId,
    String? comment,
    String? replaceId,
  }) async {
    final id = replaceId ?? _uuid.v4();
    final db = await LocalDatabase.instance.database;
    await db.insert(
      'analysis_records',
      {
        'id': id,
        'well_id': wellId,
        'type_id': typeId,
        'value': value,
        'service_key': serviceKey,
        'operator_name': operatorName,
        'operator_id': operatorId,
        'comment': comment,
        'recorded_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _load();
  }

  /// Ajoute un nouveau type d'analyse au catalogue (paramétrage Admin).
  Future<void> addAnalysisType(AnalysisType type) async {
    final db = await LocalDatabase.instance.database;
    await db.insert(
      'analysis_types',
      {
        'id': type.id,
        'label': type.label,
        'unit': type.unit,
        'min_value': type.min,
        'max_value': type.max,
        'frequency': type.frequency.storageKey,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _load();
  }

  /// Met à jour un type d'analyse existant (unité, seuils, fréquence).
  Future<void> updateAnalysisType(AnalysisType updated) => addAnalysisType(updated);

  /// Supprime un type d'analyse et tout l'historique associé (sur tous les
  /// puits) : sans ça, les analyses déjà saisies pour ce type deviendraient
  /// orphelines et feraient planter les écrans qui résolvent un type par id.
  Future<void> deleteAnalysisType(String typeId) async {
    final db = await LocalDatabase.instance.database;
    await db.delete('analysis_records', where: 'type_id = ?', whereArgs: [typeId]);
    await db.delete('analysis_types', where: 'id = ?', whereArgs: [typeId]);
    await _load();
  }

  /// Met à jour une analyse déjà enregistrée (valeur, service, commentaire),
  /// y compris pour corriger une saisie d'un jour précédent — la date et
  /// l'opérateur d'origine sont conservés.
  Future<void> updateRecord({
    required String recordId,
    required double value,
    required String serviceKey,
    String? comment,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'analysis_records',
      {'value': value, 'service_key': serviceKey, 'comment': comment},
      where: 'id = ?',
      whereArgs: [recordId],
    );
    await _load();
  }

  /// Supprime une analyse enregistrée (ex: saisie en double ou erronée).
  Future<void> deleteRecord(String recordId) async {
    final db = await LocalDatabase.instance.database;
    await db.delete('analysis_records', where: 'id = ?', whereArgs: [recordId]);
    await _load();
  }

  /// Total journalier (somme sur tous les puits actifs) d'un type d'analyse
  /// sur les [days] derniers jours (aujourd'hui inclus) — base de la courbe
  /// de tendance globale du tableau de bord.
  List<(DateTime day, double total)> aggregateDailyTotals(String typeId, {int days = 7}) {
    final today = DateTime.now();
    final activeWellIds = state.wells.where((w) => w.active).map((w) => w.id).toSet();
    final result = <(DateTime, double)>[];
    for (var i = days - 1; i >= 0; i--) {
      final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
      var total = 0.0;
      for (final record in state.records) {
        if (record.typeId == typeId && activeWellIds.contains(record.wellId) && record.isSameDay(day)) {
          total += record.value;
        }
      }
      result.add((day, total));
    }
    return result;
  }

  /// Noms de groupes déjà utilisés (triés, sans doublons), pour proposer un
  /// menu déroulant tout en permettant d'en saisir un nouveau.
  List<String> get groups {
    final names = state.wells.map((w) => w.group).where((g) => g.trim().isNotEmpty).toSet().toList()..sort();
    return names;
  }

  /// Ajoute un nouveau puits (paramétrage).
  Future<void> addWell({
    required String code,
    required String name,
    required bool active,
    required String group,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.insert(
      'wells',
      {'id': _uuid.v4(), 'code': code, 'name': name, 'active': active ? 1 : 0, 'group_name': group},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _load();
  }

  /// Met à jour un puits existant (nom, code, groupe, statut actif/arrêté).
  Future<void> updateWell(Well updated) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'wells',
      {'code': updated.code, 'name': updated.name, 'active': updated.active ? 1 : 0, 'group_name': updated.group},
      where: 'id = ?',
      whereArgs: [updated.id],
    );
    await _load();
  }

  /// Supprime un puits et tout son historique d'analyses.
  Future<void> deleteWell(String wellId) async {
    final db = await LocalDatabase.instance.database;
    await db.delete('analysis_records', where: 'well_id = ?', whereArgs: [wellId]);
    await db.delete('wells', where: 'id = ?', whereArgs: [wellId]);
    await _load();
  }

  /// Statistiques par puits sur une période, regroupées par zone/champ —
  /// base de l'écran "Statistiques".
  List<GroupStats> statsForPeriod(DateTime start, DateTime end) {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    final byGroup = <String, List<WellStats>>{};

    for (final well in state.wells) {
      final recordsInRange = state.records.where((r) =>
          r.wellId == well.id && !r.dateTime.isBefore(startDay) && !r.dateTime.isAfter(endDay));
      var outOfRange = 0;
      var total = 0;
      for (final record in recordsInRange) {
        total++;
        AnalysisType? type;
        for (final t in state.analysisTypes) {
          if (t.id == record.typeId) {
            type = t;
            break;
          }
        }
        if (type != null && type.isOutOfRange(record.value)) outOfRange++;
      }
      final groupKey = well.group.trim().isEmpty ? unassignedGroupLabel : well.group.trim();
      (byGroup[groupKey] ??= []).add(WellStats(well: well, totalRecords: total, outOfRangeCount: outOfRange));
    }

    final groups = byGroup.entries.map((e) => GroupStats(group: e.key, wells: e.value)).toList()
      ..sort((a, b) => a.group.compareTo(b.group));
    return groups;
  }
}

Well _wellFromRow(Map<String, Object?> row) => Well(
      id: row['id'] as String,
      code: row['code'] as String,
      name: row['name'] as String,
      active: (row['active'] as int) == 1,
      group: row['group_name'] as String? ?? '',
    );

AnalysisType _typeFromRow(Map<String, Object?> row) => AnalysisType(
      id: row['id'] as String,
      label: row['label'] as String,
      unit: row['unit'] as String,
      min: (row['min_value'] as num).toDouble(),
      max: (row['max_value'] as num).toDouble(),
      frequency: AnalysisFrequencyX.fromStorageKey(row['frequency'] as String),
    );

AnalysisRecord _recordFromRow(Map<String, Object?> row) => AnalysisRecord(
      id: row['id'] as String,
      wellId: row['well_id'] as String,
      typeId: row['type_id'] as String,
      value: (row['value'] as num).toDouble(),
      serviceKey: row['service_key'] as String,
      operatorName: row['operator_name'] as String,
      operatorId: row['operator_id'] as String?,
      dateTime: DateTime.parse(row['recorded_at'] as String),
      comment: row['comment'] as String?,
    );

final wellsControllerProvider = StateNotifierProvider<WellsController, WellsState>((ref) => WellsController());
