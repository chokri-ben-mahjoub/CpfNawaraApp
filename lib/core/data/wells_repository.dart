import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_providers.dart';
import '../models/analysis_record.dart';
import '../models/analysis_type.dart';
import '../models/well.dart';

const _wellsCollection = 'wells';
const _analysisTypesCollection = 'analysisTypes';
const _analysisRecordsCollection = 'analysisRecords';

/// État courant du périmètre "puits / types d'analyse / analyses", reflet
/// direct des collections Firestore (dont le cache hors-ligne intégré garde
/// l'app utilisable sans réseau).
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

class WellsController extends StateNotifier<WellsState> {
  WellsController(this._firestore) : super(WellsState.empty) {
    _wellsSub = _firestore.collection(_wellsCollection).snapshots().listen((snap) {
      state = state.copyWith(wells: snap.docs.map(_wellFromDoc).toList());
    });
    _typesSub = _firestore.collection(_analysisTypesCollection).snapshots().listen((snap) {
      state = state.copyWith(analysisTypes: snap.docs.map(_typeFromDoc).toList());
    });
    _recordsSub = _firestore.collection(_analysisRecordsCollection).snapshots().listen((snap) {
      state = state.copyWith(records: snap.docs.map(_recordFromDoc).toList());
    });
  }

  final FirebaseFirestore _firestore;
  static const _uuid = Uuid();

  late final StreamSubscription _wellsSub;
  late final StreamSubscription _typesSub;
  late final StreamSubscription _recordsSub;

  @override
  void dispose() {
    _wellsSub.cancel();
    _typesSub.cancel();
    _recordsSub.cancel();
    super.dispose();
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
  /// L'écriture Firestore est envoyée sans attendre sa confirmation réseau :
  /// le cache hors-ligne de Firestore applique le changement localement tout
  /// de suite (l'UI réagit immédiatement, même hors-ligne) et le synchronise
  /// tout seul au retour du réseau.
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
    unawaited(
      _firestore.collection(_analysisRecordsCollection).doc(id).set({
        'wellId': wellId,
        'typeId': typeId,
        'value': value,
        'serviceKey': serviceKey,
        'operatorName': operatorName,
        'operatorId': operatorId,
        'comment': comment,
        'recordedAt': Timestamp.fromDate(DateTime.now()),
      }).catchError((_) {}),
    );
  }

  /// Ajoute un nouveau type d'analyse au catalogue (paramétrage Admin).
  Future<void> addAnalysisType(AnalysisType type) async {
    unawaited(
      _firestore.collection(_analysisTypesCollection).doc(type.id).set({
        'label': type.label,
        'unit': type.unit,
        'min': type.min,
        'max': type.max,
        'frequency': type.frequency.storageKey,
      }).catchError((_) {}),
    );
  }

  /// Met à jour un type d'analyse existant (unité, seuils, fréquence).
  Future<void> updateAnalysisType(AnalysisType updated) => addAnalysisType(updated);
}

Well _wellFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  return Well(
    id: doc.id,
    code: data['code'] as String? ?? '',
    name: data['name'] as String? ?? '',
    active: data['active'] as bool? ?? true,
  );
}

AnalysisType _typeFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  return AnalysisType(
    id: doc.id,
    label: data['label'] as String? ?? '',
    unit: data['unit'] as String? ?? '',
    min: (data['min'] as num?)?.toDouble() ?? 0,
    max: (data['max'] as num?)?.toDouble() ?? 0,
    frequency: AnalysisFrequencyX.fromStorageKey(data['frequency'] as String? ?? 'daily'),
  );
}

AnalysisRecord _recordFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  final recordedAt = data['recordedAt'];
  return AnalysisRecord(
    id: doc.id,
    wellId: data['wellId'] as String? ?? '',
    typeId: data['typeId'] as String? ?? '',
    value: (data['value'] as num?)?.toDouble() ?? 0,
    serviceKey: data['serviceKey'] as String? ?? '',
    operatorName: data['operatorName'] as String? ?? '',
    operatorId: data['operatorId'] as String?,
    dateTime: recordedAt is Timestamp ? recordedAt.toDate() : DateTime.now(),
    comment: data['comment'] as String?,
  );
}

final wellsControllerProvider = StateNotifierProvider<WellsController, WellsState>((ref) {
  return WellsController(ref.watch(firestoreProvider));
});
