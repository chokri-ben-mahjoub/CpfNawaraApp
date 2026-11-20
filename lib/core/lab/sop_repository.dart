import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';

/// Procédure d'analyse (SOP) : un PDF joint (base64, comme les pièces jointes
/// du stock) avec un titre et une catégorie facultative.
class Sop {
  final String id;
  final String title;
  final String category;
  final String fileName;

  /// PDF encodé en base64.
  final String data;
  final int updatedAt;

  const Sop({
    required this.id,
    required this.title,
    this.category = '',
    required this.fileName,
    required this.data,
    this.updatedAt = 0,
  });
}

final sopControllerProvider = StateNotifierProvider<SopController, List<Sop>>((ref) => SopController());

class SopController extends StateNotifier<List<Sop>> {
  SopController() : super(const []) {
    _load();
  }

  final _uuid = const Uuid();

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('sops', orderBy: 'title collate nocase');
    state = rows.map(_fromRow).toList();
  }

  Future<void> save({
    String? id,
    required String title,
    required String category,
    required String fileName,
    required String data,
  }) async {
    final db = await LocalDatabase.instance.database;
    final values = {'title': title, 'category': category, 'file_name': fileName, 'file': data};
    if (id == null) {
      await db.insert('sops', LocalDatabase.stamp({'id': 'sop_${_uuid.v4()}', ...values}));
    } else {
      await db.update('sops', LocalDatabase.stamp(values), where: 'id = ?', whereArgs: [id]);
    }
    await _load();
  }

  Future<void> delete(String id) async {
    final db = await LocalDatabase.instance.database;
    final label = state.where((e) => e.id == id).firstOrNull?.title ?? id;
    await LocalDatabase.recordDeletion(db, 'sops', id, label: label);
    await db.delete('sops', where: 'id = ?', whereArgs: [id]);
    await _load();
  }

  static Sop _fromRow(Map<String, Object?> row) => Sop(
    id: row['id'] as String,
    title: row['title'] as String? ?? '',
    category: row['category'] as String? ?? '',
    fileName: row['file_name'] as String? ?? '',
    data: row['file'] as String? ?? '',
    updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
  );
}
