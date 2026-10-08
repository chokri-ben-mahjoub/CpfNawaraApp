import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analysis_record.dart';
import '../models/analysis_type.dart';
import '../models/well.dart';
import '../utils/id_generator.dart';

/// État en mémoire du périmètre "puits / analyses", avec un jeu de données
/// de démonstration. À remplacer par la base locale (SQLite) + synchronisation
/// cloud prévues dans le cahier des charges complet.
class WellsState {
  final List<Well> wells;
  final List<AnalysisType> analysisTypes;
  final List<AnalysisRecord> records;

  const WellsState({
    required this.wells,
    required this.analysisTypes,
    required this.records,
  });

  WellsState copyWith({
    List<AnalysisRecord>? records,
    List<AnalysisType>? analysisTypes,
  }) =>
      WellsState(
        wells: wells,
        analysisTypes: analysisTypes ?? this.analysisTypes,
        records: records ?? this.records,
      );
}

enum DailyStatus { done, pending, overdue }

class WellsController extends StateNotifier<WellsState> {
  WellsController() : super(_seed());

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

  /// Ajoute (ou remplace, si [replaceId] est fourni) un enregistrement.
  void addRecord({
    required String wellId,
    required String typeId,
    required double value,
    required String serviceKey,
    required String operatorName,
    String? comment,
    String? replaceId,
  }) {
    final record = AnalysisRecord(
      id: replaceId ?? newLocalId(),
      wellId: wellId,
      typeId: typeId,
      value: value,
      serviceKey: serviceKey,
      operatorName: operatorName,
      dateTime: DateTime.now(),
      comment: comment,
    );
    final updated = [
      for (final r in state.records)
        if (r.id != replaceId) r,
      record,
    ];
    state = state.copyWith(records: updated);
  }

  /// Ajoute un nouveau type d'analyse au catalogue (paramétrage Admin).
  void addAnalysisType(AnalysisType type) {
    state = state.copyWith(analysisTypes: [...state.analysisTypes, type]);
  }

  /// Met à jour un type d'analyse existant (unité, seuils, fréquence).
  void updateAnalysisType(AnalysisType updated) {
    state = state.copyWith(
      analysisTypes: [
        for (final t in state.analysisTypes)
          if (t.id == updated.id) updated else t,
      ],
    );
  }
}

final wellsControllerProvider =
    StateNotifierProvider<WellsController, WellsState>((ref) => WellsController());

WellsState _seed() {
  const wells = [
    Well(id: 'w1', code: 'NWR-12', name: 'Nawara 12', active: true),
    Well(id: 'w2', code: 'NWR-07', name: 'Nawara 07', active: true),
    Well(id: 'w3', code: 'NWR-21', name: 'Nawara 21', active: true),
    Well(id: 'w4', code: 'NWR-04', name: 'Nawara 04', active: false),
    Well(id: 'w5', code: 'NWR-15', name: 'Nawara 15', active: true),
  ];

  const types = [
    AnalysisType(
      id: 't_bsw',
      labelKey: 'analysisBsw',
      unit: '%',
      min: 0,
      max: 2,
      frequency: AnalysisFrequency.daily,
    ),
    AnalysisType(
      id: 't_salinity',
      labelKey: 'analysisSalinity',
      unit: 'mg/L',
      min: 0,
      max: 5000,
      frequency: AnalysisFrequency.daily,
    ),
    AnalysisType(
      id: 't_density',
      labelKey: 'analysisDensity',
      unit: 'kg/m³',
      min: 780,
      max: 860,
      frequency: AnalysisFrequency.weekly,
    ),
    AnalysisType(
      id: 't_h2s',
      labelKey: 'analysisH2s',
      unit: 'ppm',
      min: 0,
      max: 10,
      frequency: AnalysisFrequency.daily,
    ),
    AnalysisType(
      id: 't_pressure',
      labelKey: 'analysisPressure',
      unit: 'bar',
      min: 20,
      max: 120,
      frequency: AnalysisFrequency.daily,
    ),
    AnalysisType(
      id: 't_temperature',
      labelKey: 'analysisTemperature',
      unit: '°C',
      min: 15,
      max: 90,
      frequency: AnalysisFrequency.daily,
    ),
    AnalysisType(
      id: 't_flow',
      labelKey: 'analysisFlow',
      unit: 'm³/h',
      min: 0,
      max: 500,
      frequency: AnalysisFrequency.monthly,
    ),
  ];

  final now = DateTime.now();
  DateTime daysAgo(int d) => DateTime(now.year, now.month, now.day - d, 8, 30);

  final records = <AnalysisRecord>[
    // NWR-12 : tout fait aujourd'hui.
    AnalysisRecord(
      id: 'r1', wellId: 'w1', typeId: 't_bsw', value: 0.8,
      serviceKey: 'serviceLaboratoire', operatorName: 'Amine T.', dateTime: daysAgo(0),
    ),
    AnalysisRecord(
      id: 'r2', wellId: 'w1', typeId: 't_h2s', value: 3.2,
      serviceKey: 'serviceHse', operatorName: 'Sana K.', dateTime: daysAgo(0),
    ),
    AnalysisRecord(
      id: 'r3', wellId: 'w1', typeId: 't_pressure', value: 64,
      serviceKey: 'serviceExploitation', operatorName: 'Walid B.', dateTime: daysAgo(0),
    ),
    AnalysisRecord(
      id: 'r4', wellId: 'w1', typeId: 't_temperature', value: 52,
      serviceKey: 'serviceExploitation', operatorName: 'Walid B.', dateTime: daysAgo(0),
    ),
    AnalysisRecord(
      id: 'r5', wellId: 'w1', typeId: 't_salinity', value: 1200,
      serviceKey: 'serviceLaboratoire', operatorName: 'Amine T.', dateTime: daysAgo(0),
    ),

    // NWR-07 : fait hier, donc "à faire" aujourd'hui (pas encore en retard).
    AnalysisRecord(
      id: 'r6', wellId: 'w2', typeId: 't_bsw', value: 1.4,
      serviceKey: 'serviceLaboratoire', operatorName: 'Nour H.', dateTime: daysAgo(1),
    ),
    AnalysisRecord(
      id: 'r7', wellId: 'w2', typeId: 't_h2s', value: 6.5,
      serviceKey: 'serviceHse', operatorName: 'Sana K.', dateTime: daysAgo(0),
    ),
    AnalysisRecord(
      id: 'r8', wellId: 'w2', typeId: 't_pressure', value: 58,
      serviceKey: 'serviceExploitation', operatorName: 'Walid B.', dateTime: daysAgo(1),
    ),

    // NWR-21 : rien depuis plusieurs jours -> "en retard".
    AnalysisRecord(
      id: 'r9', wellId: 'w3', typeId: 't_bsw', value: 1.1,
      serviceKey: 'serviceLaboratoire', operatorName: 'Nour H.', dateTime: daysAgo(4),
    ),
    AnalysisRecord(
      id: 'r10', wellId: 'w3', typeId: 't_pressure', value: 112,
      serviceKey: 'serviceExploitation', operatorName: 'Walid B.', dateTime: daysAgo(5),
    ),

    // NWR-15 : une valeur hors seuil pour illustrer l'alerte.
    AnalysisRecord(
      id: 'r11', wellId: 'w5', typeId: 't_h2s', value: 14.8,
      serviceKey: 'serviceHse', operatorName: 'Sana K.', dateTime: daysAgo(0),
      comment: 'Capteur réétalonné ce matin.',
    ),
    AnalysisRecord(
      id: 'r12', wellId: 'w5', typeId: 't_bsw', value: 0.6,
      serviceKey: 'serviceLaboratoire', operatorName: 'Amine T.', dateTime: daysAgo(0),
    ),
  ];

  return WellsState(wells: wells, analysisTypes: types, records: records);
}
