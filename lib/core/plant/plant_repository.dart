import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

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

enum PlantSchemaKind { pfd, image, blank }

/// Dimensions logiques du schéma intégré (PFD dessiné).
const pfdCanvasSize = Size(1000, 560);

/// Position par défaut des points de prélèvement sur le schéma intégré (par
/// code, unités de [pfdCanvasSize]).
const pfdDefaultPositions = <String, Offset>{
  'C1': Offset(376, 180),
  'C2': Offset(340, 355),
  'C3': Offset(510, 355),
  'C4': Offset(915, 355),
  'W1': Offset(350, 490),
  'W2': Offset(200, 245),
  'W3': Offset(590, 490),
  'W4': Offset(300, 520),
  'G1': Offset(340, 255),
  'G2': Offset(318, 75),
  'G3': Offset(905, 55),
  'LA': Offset(720, 175),
  'RA': Offset(612, 208),
};

/// Un schéma de l'usine (table `plant_schemas`) : le dessin intégré, une
/// image importée (photo ou scan du PFD) ou un fond quadrillé, sur lequel
/// l'administrateur place les points de prélèvement.
class PlantSchema {
  final String id;

  /// Nom libre, ou clé de traduction pour le schéma intégré.
  final String name;
  final PlantSchemaKind kind;

  /// Image JPEG en base64 (schéma de type image).
  final String? image;
  final int? imageWidth;
  final int? imageHeight;

  /// pointId -> position en fractions (0 à 1) de la largeur / hauteur, ou
  /// `null` : point retiré de ce schéma.
  final Map<String, Offset?> positions;
  final int sortOrder;

  PlantSchema({
    required this.id,
    required this.name,
    required this.kind,
    this.image,
    this.imageWidth,
    this.imageHeight,
    this.positions = const {},
    this.sortOrder = 0,
  });

  /// Schéma intégré, utilisé si la table est vide (ancienne sauvegarde).
  static final builtIn = PlantSchema(id: 'pfd', name: 'plantSchemaPfd', kind: PlantSchemaKind.pfd, sortOrder: 1);

  late final Uint8List? imageBytes = () {
    final data = image;
    if (data == null || data.isEmpty) return null;
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }();

  /// Dimensions logiques du schéma (largeur 1000).
  Size get canvasSize => switch (kind) {
    PlantSchemaKind.pfd => pfdCanvasSize,
    PlantSchemaKind.image when (imageWidth ?? 0) > 0 && (imageHeight ?? 0) > 0 => Size(
      1000,
      (1000 * imageHeight! / imageWidth!).clamp(250, 2000).toDouble(),
    ),
    _ => const Size(1000, 600),
  };

  /// Position d'un point (fractions 0 à 1), ou `null` s'il n'est pas placé.
  Offset? positionOf(SamplePoint point) {
    if (positions.containsKey(point.id)) return positions[point.id];
    if (kind == PlantSchemaKind.pfd) {
      final p = pfdDefaultPositions[point.code];
      if (p != null) return Offset(p.dx / pfdCanvasSize.width, p.dy / pfdCanvasSize.height);
    }
    return null;
  }

  PlantSchema copyWith({
    String? name,
    Map<String, Offset?>? positions,
    String? image,
    int? imageWidth,
    int? imageHeight,
  }) => PlantSchema(
    id: id,
    name: name ?? this.name,
    kind: kind,
    image: image ?? this.image,
    imageWidth: imageWidth ?? this.imageWidth,
    imageHeight: imageHeight ?? this.imageHeight,
    positions: positions ?? this.positions,
    sortOrder: sortOrder,
  );
}

/// Évolution d'un paramètre entre deux analyses consécutives d'un point.
class PlantVariation {
  final DateTime date;
  final double value;
  final DateTime previousDate;
  final double previous;

  const PlantVariation({required this.date, required this.value, required this.previousDate, required this.previous});

  double get delta => value - previous;

  /// Variation en %, ou `null` si la valeur précédente est nulle.
  double? get percent => previous == 0 ? null : delta / previous.abs() * 100;

  /// 1 hausse, -1 baisse, 0 stable (moins de 1 % d'écart).
  int get direction {
    final pct = percent;
    if (pct == null) return delta == 0 ? 0 : delta.sign.toInt();
    if (pct.abs() < 1) return 0;
    return pct.sign.toInt();
  }
}

class PlantState {
  final List<SamplePoint> points;
  final List<PlantAnalysis> analyses;
  final List<PlantCircuit> circuits;
  final List<PlantSchema> schemas;

  /// pointId -> paramètre -> seuil.
  final Map<String, Map<String, PlantThreshold>> thresholds;

  /// Faux tant que la base locale n'a pas encore été lue.
  final bool ready;

  const PlantState({
    required this.points,
    required this.analyses,
    required this.thresholds,
    this.circuits = const [],
    this.schemas = const [],
    this.ready = true,
  });

  static const empty = PlantState(points: [], analyses: [], thresholds: {}, circuits: [], ready: false);

  /// Schémas à afficher (le schéma intégré si aucun n'est enregistré).
  List<PlantSchema> get visibleSchemas => schemas.isEmpty ? [PlantSchema.builtIn] : schemas;
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
    final circuits = (await db.query('plant_circuits', orderBy: 'sort_order')).map(_circuitFromRow).toList();
    final circuitsById = {for (final c in circuits) c.id: c};
    final points = (await db.query(
      'sample_points',
      orderBy: 'sort_order, code',
    )).map((row) => _pointFromRow(row, circuitsById)).toList();
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
    final schemas = (await db.query('plant_schemas', orderBy: 'sort_order, name')).map(_schemaFromRow).toList();
    state = PlantState(
      points: points,
      analyses: analyses,
      thresholds: thresholds,
      circuits: circuits,
      schemas: schemas,
    );
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

  /// Évolution d'un paramètre : analyse du jour [at] (ou la dernière) par
  /// rapport à l'analyse précédente qui a une valeur.
  PlantVariation? variation(String pointId, String param, {DateTime? at}) {
    final list = series(pointId, param);
    var i = list.length - 1;
    if (at != null) {
      final day = _day(at);
      i = list.lastIndexWhere((e) => !e.$1.isAfter(day));
      if (i < 0 || list[i].$1 != day) return null;
    }
    if (i < 1) return null;
    return PlantVariation(date: list[i].$1, value: list[i].$2, previousDate: list[i - 1].$1, previous: list[i - 1].$2);
  }

  PlantSchema? schema(String id) {
    for (final sc in state.visibleSchemas) {
      if (sc.id == id) return sc;
    }
    return null;
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

  /// Crée ou modifie un circuit (id vide = nouveau circuit).
  Future<String> saveCircuit(PlantCircuit circuit) async {
    final db = await LocalDatabase.instance.database;
    final id = circuit.id.isEmpty ? 'pc_${_uuid.v4().substring(0, 8)}' : circuit.id;
    await db.insert(
      'plant_circuits',
      LocalDatabase.stamp({
        'id': id,
        'label_key': circuit.labelKey,
        'color': circuit.colorValue,
        'icon': circuit.iconKey,
        'default_profile': circuit.defaultProfile,
        'sort_order': circuit.sortOrder,
      }),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _afterWrite();
    return id;
  }

  /// Supprime un circuit ; refusé (retourne `false`) tant qu'un point lui est
  /// encore rattaché.
  Future<bool> deleteCircuit(String circuitId) async {
    if (state.points.any((p) => p.circuit.id == circuitId)) return false;
    final db = await LocalDatabase.instance.database;
    await LocalDatabase.recordDeletion(db, 'plant_circuits', circuitId);
    await db.delete('plant_circuits', where: 'id = ?', whereArgs: [circuitId]);
    await _afterWrite();
    return true;
  }

  /// Prochain numéro d'ordre (nouveau circuit affiché en fin de liste).
  int get nextCircuitSortOrder => state.circuits.fold<int>(0, (m, c) => c.sortOrder > m ? c.sortOrder : m) + 1;

  /// Crée ou modifie un schéma (id vide = nouveau schéma).
  Future<String> saveSchema(PlantSchema schema) async {
    final db = await LocalDatabase.instance.database;
    final id = schema.id.isEmpty ? 'ps_${_uuid.v4().substring(0, 8)}' : schema.id;
    final sortOrder = schema.id.isEmpty
        ? state.schemas.fold<int>(0, (m, sc) => sc.sortOrder > m ? sc.sortOrder : m) + 1
        : schema.sortOrder;
    await db.insert(
      'plant_schemas',
      LocalDatabase.stamp({
        'id': id,
        'name': schema.name,
        'kind': schema.kind.name,
        'image': schema.image,
        'image_width': schema.imageWidth,
        'image_height': schema.imageHeight,
        'positions_json': jsonEncode({
          for (final e in schema.positions.entries)
            e.key: e.value == null ? null : [_round(e.value!.dx), _round(e.value!.dy)],
        }),
        'sort_order': sortOrder,
      }),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _afterWrite();
    return id;
  }

  /// Supprime un schéma ; refusé (retourne `false`) pour le dernier.
  Future<bool> deleteSchema(String id) async {
    if (state.visibleSchemas.length <= 1) return false;
    final db = await LocalDatabase.instance.database;
    await LocalDatabase.recordDeletion(db, 'plant_schemas', id);
    await db.delete('plant_schemas', where: 'id = ?', whereArgs: [id]);
    await _afterWrite();
    return true;
  }

  static double _round(double v) => (v.clamp(0.0, 1.0) * 10000).roundToDouble() / 10000;

  Future<void> _afterWrite() async {
    await _load();
    LocalDatabase.instance.notifyChange();
  }
}

/// Circuit de secours si un point référence un circuit introuvable (ne
/// devrait pas arriver : la suppression d'un circuit encore utilisé est
/// refusée — voir [PlantController.deleteCircuit]).
const _unknownCircuit = PlantCircuit(
  id: '?',
  labelKey: 'plantCircuitUnknown',
  colorValue: 0xFF9E9E9E,
  iconKey: 'science',
  defaultProfile: 'condensate',
);

PlantCircuit _circuitFromRow(Map<String, Object?> row) => PlantCircuit(
  id: row['id'] as String,
  labelKey: row['label_key'] as String,
  colorValue: (row['color'] as num).toInt(),
  iconKey: row['icon'] as String? ?? 'science',
  defaultProfile: row['default_profile'] as String? ?? 'condensate',
  sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
);

SamplePoint _pointFromRow(Map<String, Object?> row, Map<String, PlantCircuit> circuitsById) => SamplePoint(
  id: row['id'] as String,
  code: row['code'] as String,
  circuit: circuitsById[row['circuit'] as String] ?? _unknownCircuit,
  name: row['name'] as String,
  equipment: row['equipment'] as String? ?? '',
  profile: row['profile'] as String,
  sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
  active: (row['active'] as num?) != 0,
  paramKeys: _decodeKeys(row['params_json'] as String?),
);

PlantSchema _schemaFromRow(Map<String, Object?> row) {
  final positions = <String, Offset?>{};
  try {
    final decoded = jsonDecode(row['positions_json'] as String? ?? '{}');
    if (decoded is Map) {
      for (final e in decoded.entries) {
        final v = e.value;
        positions['${e.key}'] = v is List && v.length == 2
            ? Offset((v[0] as num).toDouble(), (v[1] as num).toDouble())
            : null;
      }
    }
  } catch (_) {
    // Positions illisibles : schéma affiché sans points placés.
  }
  return PlantSchema(
    id: row['id'] as String,
    name: row['name'] as String? ?? '',
    kind: PlantSchemaKind.values.asNameMap()[row['kind']] ?? PlantSchemaKind.blank,
    image: row['image'] as String?,
    imageWidth: (row['image_width'] as num?)?.toInt(),
    imageHeight: (row['image_height'] as num?)?.toInt(),
    positions: positions,
    sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
  );
}

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

/// Schéma affiché dans l'onglet Usine (`null` : le premier).
final plantSchemaIdProvider = StateProvider<String?>((ref) => null);

/// Jour consulté dans le module Usine (aujourd'hui par défaut).
final plantDayProvider = StateProvider<DateTime>((ref) => _day(DateTime.now()));
