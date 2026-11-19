import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../plant/plant_repository.dart' show plantDateKey;

/// Types d'échantillon suggérés (texte libre, pas de liste fermée).
const sampleTestItemSuggestions = [
  'Lean Amine',
  'Produced water',
  'Condensate',
  'Rich Amine',
  'Gas',
  'TEG',
  'Hot oil',
  'Fresh water',
  'Plant Water',
  'Demin Water',
  'Permeate Water',
  'Aquifer Water',
  'Deposite sample',
  'Sludge Sample',
];

/// Conditionnements suggérés (idem, texte libre).
const sampleConditioningSuggestions = ['01 glass bottle', '01 Cylinder bottle', '01 Plastic bottle'];

/// Avancement d'un échantillon : préparé (défaut) → envoyé → résultat reçu.
const sampleStatuses = ['prepared', 'sent', 'received'];

/// Statut suivant dans le cycle préparé → envoyé → reçu → préparé.
String nextSampleStatus(String status) {
  final i = sampleStatuses.indexOf(status.isEmpty ? 'prepared' : status);
  return sampleStatuses[(i + 1) % sampleStatuses.length];
}

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

  /// Heure de prélèvement (« HH:mm »), vide si non renseignée.
  final String samplingTime;

  /// Un de [sampleStatuses] (vide = préparé).
  final String status;
  final int sortOrder;

  const SampleManifestEntry({
    required this.id,
    required this.date,
    required this.testItem,
    this.conditioning = '',
    this.quantity = 1,
    this.label = '',
    this.cpfCode = '',
    this.samplingTime = '',
    this.status = '',
    this.sortOrder = 0,
  });

  SampleManifestEntry copyWith({
    String? testItem,
    String? conditioning,
    int? quantity,
    String? label,
    String? cpfCode,
    String? samplingTime,
    String? status,
  }) => SampleManifestEntry(
    id: id,
    date: date,
    testItem: testItem ?? this.testItem,
    conditioning: conditioning ?? this.conditioning,
    quantity: quantity ?? this.quantity,
    label: label ?? this.label,
    cpfCode: cpfCode ?? this.cpfCode,
    samplingTime: samplingTime ?? this.samplingTime,
    status: status ?? this.status,
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
    String samplingTime = '',
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
        'sampling_time': samplingTime,
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
        'sampling_time': entry.samplingTime,
        'status': entry.status,
      }),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    await _load();
  }

  /// Reprend la liste d'un autre jour (sans l'heure ni le statut, remis à
  /// « préparé ») ; ignore les lignes déjà présentes. Renvoie le nombre
  /// d'échantillons ajoutés.
  Future<int> copyFromDay(DateTime from) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('sample_manifest', where: 'date = ?', whereArgs: [plantDateKey(from)], orderBy: 'sort_order');
    final existing = {for (final e in state) '${e.testItem}|${e.label}|${e.cpfCode}'};
    var sortOrder = state.isEmpty ? 0 : state.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    var count = 0;
    for (final e in rows.map(_fromRow)) {
      if (!existing.add('${e.testItem}|${e.label}|${e.cpfCode}')) continue;
      await db.insert(
        'sample_manifest',
        LocalDatabase.stamp({
          'id': 'sm_${_uuid.v4()}',
          'date': _dateKey,
          'test_item': e.testItem,
          'conditioning': e.conditioning,
          'quantity': e.quantity,
          'label': e.label,
          'cpf_code': e.cpfCode,
          'sampling_time': '',
          'status': '',
          'sort_order': sortOrder++,
        }),
      );
      count++;
    }
    await _load();
    return count;
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
    samplingTime: row['sampling_time'] as String? ?? '',
    status: row['status'] as String? ?? '',
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
