import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../plant/plant_repository.dart' show plantDateKey;

/// Types d'échantillon suggérés (texte libre, pas de liste fermée).
const sampleTestItemSuggestions = ['Lean Amine', 'Produced water', 'Condensate', 'Rich Amine', 'Gas'];

/// Conditionnements suggérés (idem, texte libre).
const sampleConditioningSuggestions = ['01 glass bottle', '01 Cylinder bottle'];

/// Un échantillon envoyé au labo un jour donné (table `sample_manifest`),
/// pour la page « Scope of Work » ajoutée en début de rapport usine.
class SampleManifestEntry {
  final String id;

  /// Jour du prélèvement, au format [plantDateKey].
  final String date;
  final String testItem;
  final String conditioning;
  final int quantity;
  final String label;
  final String cpfCode;
  final int sortOrder;

  const SampleManifestEntry({
    required this.id,
    required this.date,
    required this.testItem,
    this.conditioning = '',
    this.quantity = 1,
    this.label = '',
    this.cpfCode = '',
    this.sortOrder = 0,
  });

  SampleManifestEntry copyWith({
    String? testItem,
    String? conditioning,
    int? quantity,
    String? label,
    String? cpfCode,
  }) => SampleManifestEntry(
    id: id,
    date: date,
    testItem: testItem ?? this.testItem,
    conditioning: conditioning ?? this.conditioning,
    quantity: quantity ?? this.quantity,
    label: label ?? this.label,
    cpfCode: cpfCode ?? this.cpfCode,
    sortOrder: sortOrder,
  );
}

/// Échantillons d'un jour précis — le contrôleur suit [day] : changer de
/// jour (ex: navigation dans l'écran Usine) recharge automatiquement la
/// bonne liste.
final sampleManifestControllerProvider =
    StateNotifierProvider.family<SampleManifestController, List<SampleManifestEntry>, DateTime>(
      (ref, day) => SampleManifestController(day),
    );

class SampleManifestController extends StateNotifier<List<SampleManifestEntry>> {
  SampleManifestController(this.day) : super(const []) {
    _load();
  }

  final DateTime day;
  final _uuid = const Uuid();

  String get _dateKey => plantDateKey(day);

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('sample_manifest', where: 'date = ?', whereArgs: [_dateKey], orderBy: 'sort_order');
    state = rows.map(_fromRow).toList();
  }

  Future<void> add({
    required String testItem,
    String conditioning = '',
    int quantity = 1,
    String label = '',
    String cpfCode = '',
  }) async {
    final db = await LocalDatabase.instance.database;
    final sortOrder = state.isEmpty ? 0 : state.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    await db.insert(
      'sample_manifest',
      LocalDatabase.stamp({
        'id': 'sm_${_uuid.v4()}',
        'date': _dateKey,
        'test_item': testItem,
        'conditioning': conditioning,
        'quantity': quantity,
        'label': label,
        'cpf_code': cpfCode,
        'sort_order': sortOrder,
      }),
    );
    await _load();
  }

  Future<void> update(SampleManifestEntry entry) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'sample_manifest',
      LocalDatabase.stamp({
        'test_item': entry.testItem,
        'conditioning': entry.conditioning,
        'quantity': entry.quantity,
        'label': entry.label,
        'cpf_code': entry.cpfCode,
      }),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    await _load();
  }

  Future<void> delete(String id) async {
    final db = await LocalDatabase.instance.database;
    final label = state.where((e) => e.id == id).firstOrNull?.testItem ?? id;
    await LocalDatabase.recordDeletion(db, 'sample_manifest', id, label: label);
    await db.delete('sample_manifest', where: 'id = ?', whereArgs: [id]);
    await _load();
  }

  static SampleManifestEntry _fromRow(Map<String, Object?> row) => SampleManifestEntry(
    id: row['id'] as String,
    date: row['date'] as String? ?? '',
    testItem: row['test_item'] as String? ?? '',
    conditioning: row['conditioning'] as String? ?? '',
    quantity: (row['quantity'] as num?)?.toInt() ?? 1,
    label: row['label'] as String? ?? '',
    cpfCode: row['cpf_code'] as String? ?? '',
    sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
  );
}

/// Pour le rapport PDF usine (fonction pure, sans contexte Riverpod) : lit
/// directement la base locale, triée comme à l'écran.
Future<List<SampleManifestEntry>> loadSampleManifest(DateTime day) async {
  final db = await LocalDatabase.instance.database;
  final rows = await db.query(
    'sample_manifest',
    where: 'date = ?',
    whereArgs: [plantDateKey(day)],
    orderBy: 'sort_order',
  );
  return rows.map(SampleManifestController._fromRow).toList();
}
