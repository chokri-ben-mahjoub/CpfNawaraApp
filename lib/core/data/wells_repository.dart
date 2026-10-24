import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/analysis_record.dart';
import '../models/analysis_type.dart';
import '../models/intervention.dart';
import '../models/well.dart';
import '../units/unit_system.dart';
import 'local_database.dart';

/// État courant du périmètre "puits / types d'analyse / analyses", reflet de
/// la base locale (voir `local_database.dart`).
class WellsState {
  final List<Well> wells;
  final List<AnalysisType> analysisTypes;
  final List<AnalysisRecord> records;
  final List<Intervention> interventions;

  /// Faux tant que la base locale n'a pas encore été lue (écrans en
  /// squelette pendant le chargement).
  final bool ready;

  const WellsState({
    required this.wells,
    required this.analysisTypes,
    required this.records,
    this.interventions = const [],
    this.ready = true,
  });

  static const empty = WellsState(wells: [], analysisTypes: [], records: [], ready: false);

  WellsState copyWith({
    List<Well>? wells,
    List<AnalysisType>? analysisTypes,
    List<AnalysisRecord>? records,
    List<Intervention>? interventions,
  }) => WellsState(
    wells: wells ?? this.wells,
    analysisTypes: analysisTypes ?? this.analysisTypes,
    records: records ?? this.records,
    interventions: interventions ?? this.interventions,
    ready: ready,
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

  /// Contrôleur pré-rempli, sans lecture de la base locale (tests de rendu
  /// des écrans).
  @visibleForTesting
  WellsController.seeded(super.initial) {
    _loaded.complete();
  }

  static const _uuid = Uuid();

  final _loaded = Completer<void>();

  /// Terminé après la première lecture de la base (utile aux tâches de
  /// démarrage : rappels, sauvegarde automatique).
  Future<void> get loaded => _loaded.future;

  /// Relit toute la base (ex: après la restauration d'une sauvegarde).
  Future<void> reload() => _load();

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final wells = (await db.query('wells')).map(_wellFromRow).toList();
    final types = (await db.query('analysis_types')).map(_typeFromRow).toList();
    // Valeurs affichées dans le système d'unités choisi (base toujours en SI).
    final storedUnits = {for (final t in types) t.id: t.storedUnit};
    final records = (await db.query('analysis_records'))
        .map((row) => _recordFromRow(row, storedUnits[row['type_id']]))
        .toList();
    final interventions = (await db.query('interventions')).map(_interventionFromRow).toList();
    state = WellsState(wells: wells, analysisTypes: types, records: records, interventions: interventions);
    if (!_loaded.isCompleted) _loaded.complete();
  }

  Well wellById(String id) => state.wells.firstWhere((w) => w.id == id);

  /// Variante tolérante de [wellById] (puits supprimé entre-temps, lien
  /// obsolète...).
  Well? findWell(String id) {
    for (final w in state.wells) {
      if (w.id == id) return w;
    }
    return null;
  }

  AnalysisType? findType(String id) {
    for (final t in state.analysisTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

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

  /// Les [n] dernières valeurs (ordre chronologique) d'un puits pour un type
  /// d'analyse — tendances en mini-courbe et détection de dérive.
  List<double> recentValues(String wellId, String typeId, {int n = 12}) {
    final list = state.records.where((r) => r.wellId == wellId && r.typeId == typeId).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final tail = list.length > n ? list.sublist(list.length - n) : list;
    return [for (final r in tail) r.value];
  }

  /// Enregistrement du jour pour un puits et un type, s'il existe déjà.
  AnalysisRecord? todayRecord(String wellId, String typeId, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final last = lastRecord(wellId, typeId);
    if (last != null && last.isSameDay(today)) return last;
    return null;
  }

  /// Enregistrement existant pour un puits, un type et un jour donnés (saisie
  /// groupée datée) — remplacé plutôt que dupliqué si la date choisie est
  /// déjà renseignée.
  AnalysisRecord? recordOnDay(String wellId, String typeId, DateTime day) {
    final matches = state.records.where((r) => r.wellId == wellId && r.typeId == typeId && r.isSameDay(day)).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return matches.isEmpty ? null : matches.first;
  }

  DailyStatus statusFor(String wellId, String typeId, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final last = lastRecord(wellId, typeId);
    if (last != null && last.isSameDay(today)) return DailyStatus.done;

    final type = typeById(typeId);
    final daysSinceLast = last == null
        ? 999
        : today.difference(DateTime(last.dateTime.year, last.dateTime.month, last.dateTime.day)).inDays;
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

  /// Après une écriture locale : relit la base et prévient la
  /// synchronisation qu'il y a des changements à envoyer.
  Future<void> _afterWrite() async {
    await _load();
    LocalDatabase.instance.notifyChange();
  }

  /// Supprime des lignes en notant chaque suppression (propagée ensuite aux
  /// autres appareils par la synchronisation). [describe], si fourni,
  /// construit la description lisible d'une ligne pour le journal d'audit
  /// (sinon, seul son identifiant y apparaît).
  Future<void> _deleteTracked(
    DatabaseExecutor db,
    String table,
    String where,
    List<Object?> args, {
    String Function(Map<String, Object?> row)? describe,
  }) async {
    final rows = await db.query(table, where: where, whereArgs: args);
    for (final row in rows) {
      await LocalDatabase.recordDeletion(db, table, row['id'] as String, label: describe?.call(row));
    }
    await db.delete(table, where: where, whereArgs: args);
  }

  /// Ajoute (ou remplace, si [replaceId] est fourni) un enregistrement.
  /// [recordedAt], si fourni (ex: saisie groupée datée), remplace l'horodatage
  /// par défaut (maintenant). [startTime] / [endTime] (format "HH:mm") sont
  /// l'heure de début / fin du test, facultatives.
  Future<void> addRecord({
    required String wellId,
    required String typeId,
    required double value,
    required String serviceKey,
    required String operatorName,
    String? operatorId,
    String? comment,
    String? replaceId,
    DateTime? recordedAt,
    String? startTime,
    String? endTime,
  }) async {
    final id = replaceId ?? _uuid.v4();
    final db = await LocalDatabase.instance.database;
    await db.insert(
      'analysis_records',
      LocalDatabase.stamp({
        'id': id,
        'well_id': wellId,
        'type_id': typeId,
        'value': _toSi(typeId, value),
        'service_key': serviceKey,
        'operator_name': operatorName,
        'operator_id': operatorId,
        'comment': comment,
        'recorded_at': (recordedAt ?? DateTime.now()).toIso8601String(),
        'start_time': startTime,
        'end_time': endTime,
      }),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _afterWrite();
  }

  /// Valeur saisie (unité affichée) ramenée en SI pour la base.
  double _toSi(String typeId, double value) {
    final type = findType(typeId);
    return type == null ? value : Units.toSi(value, type.storedUnit);
  }

  /// Ajoute un nouveau type d'analyse au catalogue (paramétrage Admin). Les
  /// seuils sont donnés dans l'unité affichée ; l'unité et les seuils sont
  /// enregistrés en SI.
  Future<void> addAnalysisType(AnalysisType type) async {
    final db = await LocalDatabase.instance.database;
    final existing = findType(type.id);
    final storedUnit = existing != null && existing.unit == type.unit
        ? existing.storedUnit
        : Units.siUnitFor(type.unit);
    final (min, max) = Units.rangeToSi(type.min, type.max, storedUnit);
    await db.insert(
      'analysis_types',
      LocalDatabase.stamp({
        'id': type.id,
        'label': type.label,
        'unit': storedUnit,
        'min_value': min,
        'max_value': max,
        'frequency': type.frequency.storageKey,
        'group_label': type.group,
      }),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _afterWrite();
  }

  /// Met à jour un type d'analyse existant (unité, seuils, fréquence).
  Future<void> updateAnalysisType(AnalysisType updated) => addAnalysisType(updated);

  /// Supprime un type d'analyse et tout l'historique associé (sur tous les
  /// puits) : sans ça, les analyses déjà saisies pour ce type deviendraient
  /// orphelines et feraient planter les écrans qui résolvent un type par id.
  Future<void> deleteAnalysisType(String typeId) async {
    final db = await LocalDatabase.instance.database;
    await _deleteTracked(db, 'analysis_records', 'type_id = ?', [typeId]);
    await _deleteTracked(
      db,
      'analysis_types',
      'id = ?',
      [typeId],
      describe: (row) => '${row['label']} (${row['unit']})',
    );
    await _afterWrite();
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
    String? typeId;
    for (final r in state.records) {
      if (r.id == recordId) typeId = r.typeId;
    }
    await db.update(
      'analysis_records',
      LocalDatabase.stamp({
        'value': typeId == null ? value : _toSi(typeId, value),
        'service_key': serviceKey,
        'comment': comment,
      }),
      where: 'id = ?',
      whereArgs: [recordId],
    );
    await _afterWrite();
  }

  /// Supprime une analyse enregistrée (ex: saisie en double ou erronée).
  Future<void> deleteRecord(String recordId) async {
    final db = await LocalDatabase.instance.database;
    await _deleteTracked(
      db,
      'analysis_records',
      'id = ?',
      [recordId],
      describe: (row) {
        final well = findWell(row['well_id'] as String? ?? '');
        final type = findType(row['type_id'] as String? ?? '');
        return '${well?.code ?? row['well_id']} · ${type?.label ?? row['type_id']} = ${row['value']} ${type?.unit ?? ''}'
            .trim();
      },
    );
    await _afterWrite();
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
    double? reservoirPressure,
    String type = '',
    WellStatus? status,
    double? latitude,
    double? longitude,
  }) async {
    final db = await LocalDatabase.instance.database;
    final st = status ?? (active ? WellStatus.producing : WellStatus.shutIn);
    await db.insert(
      'wells',
      LocalDatabase.stamp({
        'id': _uuid.v4(),
        'code': code,
        'name': name,
        'active': st.isActive ? 1 : 0,
        'group_name': group,
        'reservoir_pressure': Units.toSiOrNull(reservoirPressure, 'bar'),
        'well_type': type,
        'status': st.storageKey,
        'latitude': latitude,
        'longitude': longitude,
      }),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _afterWrite();
  }

  /// Met à jour un puits existant (nom, code, champ, type, statut,
  /// coordonnées). Le statut décide de l'indicateur actif/arrêté.
  Future<void> updateWell(Well updated) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'wells',
      LocalDatabase.stamp({
        'code': updated.code,
        'name': updated.name,
        'active': updated.status.isActive ? 1 : 0,
        'group_name': updated.group,
        'reservoir_pressure': Units.toSiOrNull(updated.reservoirPressure, 'bar'),
        'well_type': updated.type,
        'status': updated.status.storageKey,
        'latitude': updated.latitude,
        'longitude': updated.longitude,
      }),
      where: 'id = ?',
      whereArgs: [updated.id],
    );
    await _afterWrite();
  }

  /// Supprime un puits, tout son historique d'analyses et ses interventions.
  Future<void> deleteWell(String wellId) async {
    final db = await LocalDatabase.instance.database;
    await _deleteTracked(db, 'analysis_records', 'well_id = ?', [wellId]);
    await _deleteTracked(db, 'interventions', 'well_id = ?', [wellId]);
    await _deleteTracked(
      db,
      'wells',
      'id = ?',
      [wellId],
      describe: (row) => '${row['code']} — ${row['name']}',
    );
    await _afterWrite();
  }

  /// Met à jour uniquement la pression de gisement (Pr) d'un puits.
  Future<void> setReservoirPressure(String wellId, double? value) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'wells',
      LocalDatabase.stamp({'reservoir_pressure': Units.toSiOrNull(value, 'bar')}),
      where: 'id = ?',
      whereArgs: [wellId],
    );
    await _afterWrite();
  }

  /// Interventions d'un puits, de la plus récente à la plus ancienne.
  List<Intervention> interventionsForWell(String wellId) {
    final list = state.interventions.where((i) => i.wellId == wellId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Intervention? findIntervention(String id) {
    for (final i in state.interventions) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Ajoute une intervention, ou la remplace si [Intervention.id] existe déjà
  /// (un id vide = nouvelle intervention).
  Future<void> saveIntervention(Intervention intervention) async {
    final db = await LocalDatabase.instance.database;
    final id = intervention.id.isEmpty ? _uuid.v4() : intervention.id;
    final day = DateTime(intervention.date.year, intervention.date.month, intervention.date.day);
    await db.insert(
      'interventions',
      LocalDatabase.stamp({
        'id': id,
        'well_id': intervention.wellId,
        'intervention_date': day.toIso8601String(),
        'type_key': intervention.typeKey,
        'cost': intervention.cost,
        'currency': intervention.currency,
        'result_key': intervention.resultKey,
        'description': intervention.description,
        'operator_name': intervention.operatorName,
        'created_at': DateTime.now().toIso8601String(),
      }),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _afterWrite();
  }

  Future<void> deleteIntervention(String id) async {
    final db = await LocalDatabase.instance.database;
    await _deleteTracked(
      db,
      'interventions',
      'id = ?',
      [id],
      describe: (row) {
        final well = findWell(row['well_id'] as String? ?? '');
        final date = row['intervention_date'] as String? ?? '';
        return '${well?.code ?? row['well_id']} · ${row['type_key']} · ${date.length >= 10 ? date.substring(0, 10) : date}';
      },
    );
    await _afterWrite();
  }

  /// Statistiques par puits sur une période, regroupées par zone/champ —
  /// base de l'écran "Statistiques".
  List<GroupStats> statsForPeriod(DateTime start, DateTime end) {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    final byGroup = <String, List<WellStats>>{};

    for (final well in state.wells) {
      final recordsInRange = state.records.where(
        (r) => r.wellId == well.id && !r.dateTime.isBefore(startDay) && !r.dateTime.isAfter(endDay),
      );
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

Well _wellFromRow(Map<String, Object?> row) {
  final active = (row['active'] as num?) != 0;
  return Well(
    id: row['id'] as String,
    code: row['code'] as String,
    name: row['name'] as String,
    active: active,
    group: row['group_name'] as String? ?? '',
    reservoirPressure: Units.displayOrNull((row['reservoir_pressure'] as num?)?.toDouble(), 'bar'),
    type: row['well_type'] as String? ?? '',
    status: WellStatusX.fromStorage(row['status'] as String?, active: active),
    latitude: (row['latitude'] as num?)?.toDouble(),
    longitude: (row['longitude'] as num?)?.toDouble(),
  );
}

AnalysisType _typeFromRow(Map<String, Object?> row) {
  final storedUnit = row['unit'] as String;
  final (min, max) = Units.range(
    (row['min_value'] as num).toDouble(),
    (row['max_value'] as num).toDouble(),
    storedUnit,
  );
  return AnalysisType(
    id: row['id'] as String,
    label: row['label'] as String,
    unit: Units.unit(storedUnit),
    min: min,
    max: max,
    frequency: AnalysisFrequencyX.fromStorageKey(row['frequency'] as String),
    storedUnit: storedUnit,
    group: row['group_label'] as String? ?? '',
  );
}

AnalysisRecord _recordFromRow(Map<String, Object?> row, String? storedUnit) => AnalysisRecord(
  id: row['id'] as String,
  wellId: row['well_id'] as String,
  typeId: row['type_id'] as String,
  value: storedUnit == null
      ? (row['value'] as num).toDouble()
      : Units.display((row['value'] as num).toDouble(), storedUnit),
  serviceKey: row['service_key'] as String,
  operatorName: row['operator_name'] as String,
  operatorId: row['operator_id'] as String?,
  dateTime: DateTime.parse(row['recorded_at'] as String),
  comment: row['comment'] as String?,
  startTime: row['start_time'] as String?,
  endTime: row['end_time'] as String?,
);

Intervention _interventionFromRow(Map<String, Object?> row) => Intervention(
  id: row['id'] as String,
  wellId: row['well_id'] as String,
  date: DateTime.parse(row['intervention_date'] as String),
  typeKey: row['type_key'] as String,
  cost: (row['cost'] as num?)?.toDouble(),
  currency: row['currency'] as String? ?? 'TND',
  resultKey: row['result_key'] as String,
  description: row['description'] as String?,
  operatorName: row['operator_name'] as String,
);

final wellsControllerProvider = StateNotifierProvider<WellsController, WellsState>((ref) => WellsController());
