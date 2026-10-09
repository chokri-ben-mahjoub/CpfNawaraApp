import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import 'plant_catalog.dart';

/// Point de prélèvement (table `sample_points`).
class SamplePoint {
  final String id;
  final String code;
  final PlantCircuit circuit;
  final String name;
  final String equipment;
  final String profile;
  final int sortOrder;
  final bool active;

  /// Paramètres choisis pour ce point (clés), ou `null` : ceux du profil.
  final List<String>? paramKeys;

  const SamplePoint({
    required this.id,
    required this.code,
    required this.circuit,
    required this.name,
    required this.equipment,
    required this.profile,
    this.sortOrder = 0,
    this.active = true,
    this.paramKeys,
  });

  /// Paramètres analysés, avec les unités choisies dans les Réglages.
  List<PlantParam> get params => [for (final p in storedParams) p.displayed()];

  /// Paramètres analysés, unités enregistrées (SI).
  List<PlantParam> get storedParams {
    final keys = paramKeys;
    if (keys == null) return paramsForProfile(profile);
    return [for (final key in keys) ?plantParamByKey(key, profile: profile)];
  }

  String get title => '$code — $name';
}

/// Analyse de laboratoire d'un point pour un jour (table `plant_analyses`).
class PlantAnalysis {
  final String id;
  final String pointId;

  /// Jour de prélèvement (minuit, heure locale).
  final DateTime date;

  /// Valeurs mesurées : nombre (paramètre numérique) ou clé de choix.
  final Map<String, Object?> values;
  final String source;
  final String operatorName;
  final String? comment;
  final DateTime recordedAt;

  const PlantAnalysis({
    required this.id,
    required this.pointId,
    required this.date,
    required this.values,
    required this.source,
    required this.operatorName,
    this.comment,
    required this.recordedAt,
  });

  double? number(String key) => (values[key] as num?)?.toDouble();
}

/// Seuil min/max d'un paramètre pour un point (table `plant_thresholds`).
class PlantThreshold {
  final double? min;
  final double? max;

  /// Alerte activée (valeur hors seuil signalée en rouge et dans les
  /// alertes) ; désactivée, le seuil reste affiché à titre indicatif.
  final bool alertEnabled;
  const PlantThreshold({this.min, this.max, this.alertEnabled = true});

  bool get isEmpty => min == null && max == null;

  /// "a – b", "≥ a" ou "≤ b" selon les bornes définies.
  String label(String Function(double) format) {
    if (min != null && max != null) return '${format(min!)} – ${format(max!)}';
    if (min != null) return '≥ ${format(min!)}';
    if (max != null) return '≤ ${format(max!)}';
    return '';
  }
}

enum PlantStatus { ok, outOfRange, missing }

class PlantState {
  final List<SamplePoint> points;
  final List<PlantAnalysis> analyses;

  /// pointId -> paramètre -> seuil.
  final Map<String, Map<String, PlantThreshold>> thresholds;

  /// Faux tant que la base locale n'a pas encore été lue.
  final bool ready;

  const PlantState({required this.points, required this.analyses, required this.thresholds, this.ready = true});

  static const empty = PlantState(points: [], analyses: [], thresholds: {}, ready: false);
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

String plantDateKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// Identifiant d'une analyse : une seule par point et par jour, identique sur
/// tous les appareils (deux saisies du même jour se fusionnent à la
/// synchronisation : la plus récente l'emporte).
String plantAnalysisId(String pointId, DateTime day) => '${pointId}_${plantDateKey(day)}';

class PlantController extends StateNotifier<PlantState> {
  PlantController() : super(PlantState.empty) {
    _load();
  }

  /// Contrôleur pré-rempli, sans base locale (tests de rendu).
  @visibleForTesting
  PlantController.seeded(super.initial);

  Future<void> reload() => _load();

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final points = (await db.query('sample_points', orderBy: 'sort_order, code')).map(_pointFromRow).toList();
    final byId = {for (final p in points) p.id: p};
    // Valeurs et seuils convertis dans le système d'unités choisi (base en SI).
    PlantParam? paramOf(String pointId, String key) {
      final point = byId[pointId];
      return plantParamByKey(key, profile: point?.profile);
    }

    final analyses = <PlantAnalysis>[];
    for (final row in await db.query('plant_analyses')) {
      final a = _analysisFromRow(row);
      if (a == null) continue;
      analyses.add(
        PlantAnalysis(
          id: a.id,
          pointId: a.pointId,
          date: a.date,
          values: {
            for (final e in a.values.entries)
              e.key: e.value is num
                  ? (paramOf(a.pointId, e.key)?.toDisplay((e.value as num).toDouble()) ?? e.value)
                  : e.value,
          },
          source: a.source,
          operatorName: a.operatorName,
          comment: a.comment,
          recordedAt: a.recordedAt,
        ),
      );
    }
    analyses.sort((a, b) => b.date.compareTo(a.date));
    final thresholds = <String, Map<String, PlantThreshold>>{};
    for (final row in await db.query('plant_thresholds')) {
      final pointId = row['point_id'] as String;
      final key = row['param_key'] as String;
      final param = paramOf(pointId, key);
      final rawMin = (row['min_value'] as num?)?.toDouble();
      final rawMax = (row['max_value'] as num?)?.toDouble();
      final (min, max) = param == null ? (rawMin, rawMax) : param.rangeToDisplay(rawMin, rawMax);
      final t = PlantThreshold(min: min, max: max, alertEnabled: (row['alert_enabled'] as num?) != 0);
      if (!t.isEmpty || !t.alertEnabled) (thresholds[pointId] ??= {})[key] = t;
    }
    state = PlantState(points: points, analyses: analyses, thresholds: thresholds);
  }

  // ------------------------------------------------------------- Lecture

  SamplePoint? point(String id) {
    for (final p in state.points) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<SamplePoint> pointsOf(PlantCircuit circuit) =>
      state.points.where((p) => p.circuit == circuit && p.active).toList();

  /// Analyses d'un point, de la plus récente à la plus ancienne.
  List<PlantAnalysis> analysesFor(String pointId) => state.analyses.where((a) => a.pointId == pointId).toList();

  PlantAnalysis? analysisOn(String pointId, DateTime day) {
    final id = plantAnalysisId(pointId, _day(day));
    for (final a in state.analyses) {
      if (a.id == id) return a;
    }
    return null;
  }

  PlantAnalysis? latest(String pointId) {
    for (final a in state.analyses) {
      if (a.pointId == pointId) return a;
    }
    return null;
  }

  PlantThreshold? threshold(String pointId, String param) => state.thresholds[pointId]?[param];

  /// `true` si la valeur sort du seuil défini (`null` : pas de seuil, alerte
  /// désactivée ou pas de valeur, donc rien à signaler).
  bool? isOut(String pointId, PlantParam param, Object? value) {
    if (value == null) return null;
    final t = threshold(pointId, param.key);
    if (t != null && !t.alertEnabled) return null;
    if (!param.isNumeric) {
      if (param.okChoices.isEmpty) return null;
      return !param.okChoices.contains(value);
    }
    if (t == null || t.isEmpty) return null;
    final v = (value as num).toDouble();
    return (t.min != null && v < t.min!) || (t.max != null && v > t.max!);
  }

  /// Paramètres hors seuil d'une analyse.
  List<PlantParam> outOfRange(SamplePoint point, PlantAnalysis analysis) => [
    for (final param in point.params)
      if (isOut(point.id, param, analysis.values[param.key]) == true) param,
  ];

  /// Vert (dans les seuils), rouge (hors seuil), gris (pas d'analyse ce jour).
  PlantStatus status(SamplePoint point, DateTime day) {
    final analysis = analysisOn(point.id, day);
    if (analysis == null) return PlantStatus.missing;
    return outOfRange(point, analysis).isEmpty ? PlantStatus.ok : PlantStatus.outOfRange;
  }

  /// Série chronologique d'un paramètre numérique pour un point.
  List<(DateTime, double)> series(String pointId, String param) {
    final list = <(DateTime, double)>[
      for (final a in analysesFor(pointId))
        if (a.number(param) != null) (a.date, a.number(param)!),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return list;
  }

  // ------------------------------------------------------------- Écriture

  /// Enregistre (ou remplace) l'analyse d'un point pour un jour.
  Future<void> saveAnalysis({
    required String pointId,
    required DateTime day,
    required Map<String, Object?> values,
    required String source,
    required String operatorName,
    String? comment,
  }) async {
    final db = await LocalDatabase.instance.database;
    final date = _day(day);
    final p = point(pointId);
    await db.insert(
      'plant_analyses',
      LocalDatabase.stamp({
        'id': plantAnalysisId(pointId, date),
        'point_id': pointId,
        'analysis_date': plantDateKey(date),
        'values_json': jsonEncode({
          for (final e in values.entries)
            if (e.value != null)
              e.key: e.value is num
                  ? (plantParamByKey(e.key, profile: p?.profile)?.toSi((e.value as num).toDouble()) ?? e.value)
                  : e.value,
        }),
        'source': source,
        'operator_name': operatorName,
        'comment': comment,
        'recorded_at': DateTime.now().toIso8601String(),
      }),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _afterWrite();
  }

  Future<void> deleteAnalysis(String id) async {
    final db = await LocalDatabase.instance.database;
    await LocalDatabase.recordDeletion(db, 'plant_analyses', id);
    await db.delete('plant_analyses', where: 'id = ?', whereArgs: [id]);
    await _afterWrite();
  }

  /// Définit (ou efface, si min et max sont vides et l'alerte active) le
  /// seuil d'un paramètre. [min] et [max] sont dans l'unité affichée.
  Future<void> setThreshold(
    String pointId,
    String param,
    double? displayMin,
    double? displayMax, {
    bool alertEnabled = true,
  }) async {
    final db = await LocalDatabase.instance.database;
    final id = '${pointId}_$param';
    final def = plantParamByKey(param, profile: point(pointId)?.profile);
    final (min, max) = def == null ? (displayMin, displayMax) : def.rangeToSi(displayMin, displayMax);
    if (min == null && max == null && alertEnabled) {
      final exists = (await db.query('plant_thresholds', where: 'id = ?', whereArgs: [id])).isNotEmpty;
      if (exists) {
        await LocalDatabase.recordDeletion(db, 'plant_thresholds', id);
        await db.delete('plant_thresholds', where: 'id = ?', whereArgs: [id]);
      }
    } else {
      await db.insert(
        'plant_thresholds',
        LocalDatabase.stamp({
          'id': id,
          'point_id': pointId,
          'param_key': param,
          'min_value': min,
          'max_value': max,
          'alert_enabled': alertEnabled ? 1 : 0,
        }),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await _afterWrite();
  }

  static const _uuid = Uuid();

  /// Crée ou modifie un point de prélèvement (id vide = nouveau point).
  Future<String> savePoint(SamplePoint point) async {
    final db = await LocalDatabase.instance.database;
    final id = point.id.isEmpty ? 'pp_${_uuid.v4().substring(0, 8)}' : point.id;
    await db.insert(
      'sample_points',
      LocalDatabase.stamp({
        'id': id,
        'code': point.code,
        'circuit': point.circuit.storageKey,
        'name': point.name,
        'equipment': point.equipment,
        'profile': point.profile,
        'sort_order': point.sortOrder,
        'active': point.active ? 1 : 0,
        'params_json': point.paramKeys == null ? null : jsonEncode(point.paramKeys),
      }),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _afterWrite();
    return id;
  }

  /// Supprime un point avec ses analyses et ses seuils.
  Future<void> deletePoint(String pointId) async {
    final db = await LocalDatabase.instance.database;
    for (final table in ['plant_analyses', 'plant_thresholds']) {
      for (final row in await db.query(table, columns: ['id'], where: 'point_id = ?', whereArgs: [pointId])) {
        await LocalDatabase.recordDeletion(db, table, row['id'] as String);
      }
      await db.delete(table, where: 'point_id = ?', whereArgs: [pointId]);
    }
    await LocalDatabase.recordDeletion(db, 'sample_points', pointId);
    await db.delete('sample_points', where: 'id = ?', whereArgs: [pointId]);
    await _afterWrite();
  }

  /// Prochain numéro d'ordre (nouveau point affiché en fin de liste).
  int get nextSortOrder => state.points.fold<int>(0, (m, p) => p.sortOrder > m ? p.sortOrder : m) + 1;

  Future<void> _afterWrite() async {
    await _load();
    LocalDatabase.instance.notifyChange();
  }
}

SamplePoint _pointFromRow(Map<String, Object?> row) => SamplePoint(
  id: row['id'] as String,
  code: row['code'] as String,
  circuit: PlantCircuitX.fromKey(row['circuit'] as String),
  name: row['name'] as String,
  equipment: row['equipment'] as String? ?? '',
  profile: row['profile'] as String,
  sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
  active: (row['active'] as num?) != 0,
  paramKeys: _decodeKeys(row['params_json'] as String?),
);

List<String>? _decodeKeys(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    return decoded is List ? [for (final k in decoded) '$k'] : null;
  } catch (_) {
    return null;
  }
}

PlantAnalysis? _analysisFromRow(Map<String, Object?> row) {
  try {
    final date = DateTime.parse(row['analysis_date'] as String);
    final decoded = jsonDecode(row['values_json'] as String? ?? '{}');
    return PlantAnalysis(
      id: row['id'] as String,
      pointId: row['point_id'] as String,
      date: DateTime(date.year, date.month, date.day),
      values: decoded is Map ? Map<String, Object?>.from(decoded) : const {},
      source: row['source'] as String? ?? plantSources.first,
      operatorName: row['operator_name'] as String? ?? '',
      comment: row['comment'] as String?,
      recordedAt: DateTime.tryParse(row['recorded_at'] as String? ?? '') ?? date,
    );
  } catch (_) {
    // Ligne illisible (ex: synchronisée par une version plus récente) :
    // ignorée plutôt que de bloquer tout l'écran.
    return null;
  }
}

final plantControllerProvider = StateNotifierProvider<PlantController, PlantState>((ref) => PlantController());

/// Jour consulté dans le module Usine (aujourd'hui par défaut).
final plantDayProvider = StateProvider<DateTime>((ref) => _day(DateTime.now()));
