import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';

/// Statuts suggérés (texte libre, pas de liste fermée).
const gasBottleStatusSuggestions = ['In service', 'Stand By', 'Out of service'];

/// Emplacements suggérés (idem, texte libre).
const gasBottleLocationSuggestions = ['NAC Lab Shelter', 'Down Area'];

/// Bouteille de gaz pressurisée du laboratoire (table `gas_bottles`), pour le
/// relevé « Laboratory Pressurized Gas Bottles Survey » ajouté en fin de
/// rapport usine.
class GasBottle {
  final String id;
  final String name;
  final String status;
  final double pressure;
  final String location;
  final int sortOrder;

  const GasBottle({
    required this.id,
    required this.name,
    this.status = '',
    required this.pressure,
    this.location = '',
    this.sortOrder = 0,
  });

  /// « Helium bottle (In service) », comme dans le modèle de rapport.
  String get label => status.trim().isEmpty ? name : '$name (${status.trim()})';

  GasBottle copyWith({
    String? name,
    String? status,
    double? pressure,
    String? location,
  }) => GasBottle(
    id: id,
    name: name ?? this.name,
    status: status ?? this.status,
    pressure: pressure ?? this.pressure,
    location: location ?? this.location,
    sortOrder: sortOrder,
  );
}

final gasBottleControllerProvider = StateNotifierProvider<GasBottleController, List<GasBottle>>(
  (ref) => GasBottleController(),
);

class GasBottleController extends StateNotifier<List<GasBottle>> {
  GasBottleController() : super(const []) {
    _load();
  }

  final _uuid = const Uuid();

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('gas_bottles', orderBy: 'sort_order, name');
    state = rows.map(_fromRow).toList();
  }

  Future<void> add({
    required String name,
    String status = '',
    required double pressure,
    String location = '',
  }) async {
    final db = await LocalDatabase.instance.database;
    final sortOrder = state.isEmpty ? 0 : state.map((b) => b.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    await db.insert(
      'gas_bottles',
      LocalDatabase.stamp({
        'id': 'gb_${_uuid.v4()}',
        'name': name,
        'status': status,
        'pressure': pressure,
        'location': location,
        'sort_order': sortOrder,
      }),
    );
    await _load();
  }

  Future<void> update(GasBottle bottle) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'gas_bottles',
      LocalDatabase.stamp({
        'name': bottle.name,
        'status': bottle.status,
        'pressure': bottle.pressure,
        'location': bottle.location,
      }),
      where: 'id = ?',
      whereArgs: [bottle.id],
    );
    await _load();
  }

  Future<void> delete(String id) async {
    final db = await LocalDatabase.instance.database;
    final label = state.where((b) => b.id == id).firstOrNull?.label ?? id;
    await LocalDatabase.recordDeletion(db, 'gas_bottles', id, label: label);
    await db.delete('gas_bottles', where: 'id = ?', whereArgs: [id]);
    await _load();
  }

  static GasBottle _fromRow(Map<String, Object?> row) => GasBottle(
    id: row['id'] as String,
    name: row['name'] as String? ?? '',
    status: row['status'] as String? ?? '',
    pressure: (row['pressure'] as num?)?.toDouble() ?? 0,
    location: row['location'] as String? ?? '',
    sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
  );
}

/// Pour le rapport PDF usine (fonction pure, sans contexte Riverpod) : lit
/// directement la base locale, triée comme à l'écran.
Future<List<GasBottle>> loadGasBottles() async {
  final db = await LocalDatabase.instance.database;
  final rows = await db.query('gas_bottles', orderBy: 'sort_order, name');
  return rows.map(GasBottleController._fromRow).toList();
}
