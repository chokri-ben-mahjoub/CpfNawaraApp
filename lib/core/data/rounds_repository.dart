import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:uuid/uuid.dart';

import '../models/well_round.dart';
import 'local_database.dart';

/// Tournées des opérateurs de puits (table `well_rounds`), reflet de la base
/// locale — plusieurs tournées possibles le même jour (matin / soir).
class RoundsState {
  final List<WellRound> rounds;
  final bool ready;
  const RoundsState({required this.rounds, this.ready = true});

  static const empty = RoundsState(rounds: [], ready: false);

  static DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Tournées d'un puits (ou du site) pour un jour, par heure.
  List<WellRound> on(String wellId, DateTime day) {
    final d = dayOf(day);
    return rounds.where((r) => r.wellId == wellId && r.day == d).toList()..sort((a, b) => a.time.compareTo(b.time));
  }

  /// Toutes les tournées d'un jour.
  List<WellRound> allOn(DateTime day) {
    final d = dayOf(day);
    return rounds.where((r) => r.day == d).toList()
      ..sort((a, b) {
        final byWell = a.wellId.compareTo(b.wellId);
        return byWell != 0 ? byWell : a.time.compareTo(b.time);
      });
  }

  /// Dernière tournée d'un puits strictement avant [before] (valeurs de
  /// référence affichées à la saisie).
  WellRound? previous(String wellId, DateTime before, {String? excludeId}) {
    WellRound? best;
    for (final r in rounds) {
      if (r.wellId != wellId || r.id == excludeId) continue;
      final at = DateTime(r.day.year, r.day.month, r.day.day);
      if (at.isAfter(dayOf(before))) continue;
      if (best == null || r.day.isAfter(best.day) || (r.day == best.day && r.time.compareTo(best.time) > 0)) best = r;
    }
    return best;
  }
}

class RoundsController extends StateNotifier<RoundsState> {
  RoundsController() : super(RoundsState.empty) {
    _load();
  }

  RoundsController.seeded(super.initial);

  static const _uuid = Uuid();

  Future<void> reload() => _load();

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('well_rounds');
    state = RoundsState(rounds: rows.map(_fromRow).toList());
  }

  WellRound? byId(String id) {
    for (final r in state.rounds) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Enregistre une tournée : nouvelle si [id] est nul, sinon remplace.
  Future<void> save({
    String? id,
    required String wellId,
    required DateTime day,
    required String time,
    required Map<String, Object?> values,
    required String operatorName,
    String? comment,
    String? photo,
  }) async {
    final db = await LocalDatabase.instance.database;
    final row = LocalDatabase.stamp({
      'id': id ?? _uuid.v4(),
      'well_id': wellId,
      'round_date': _dateKey(day),
      'round_time': time,
      'values_json': jsonEncode(values),
      'operator_name': operatorName,
      'comment': comment,
      'photo': photo,
      'recorded_at': DateTime.now().toIso8601String(),
    });
    await db.insert('well_rounds', row, conflictAlgorithm: ConflictAlgorithm.replace);
    await _load();
    LocalDatabase.instance.notifyChange();
  }

  Future<void> delete(String id) async {
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      await LocalDatabase.recordDeletion(txn, 'well_rounds', id, label: 'Round');
      await txn.delete('well_rounds', where: 'id = ?', whereArgs: [id]);
    });
    await _load();
    LocalDatabase.instance.notifyChange();
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  WellRound _fromRow(Map<String, Object?> row) {
    final parts = (row['round_date'] as String).split('-');
    Map<String, Object?> values = const {};
    try {
      values = Map<String, Object?>.from(jsonDecode(row['values_json'] as String? ?? '{}') as Map);
    } catch (_) {}
    return WellRound(
      id: row['id'] as String,
      wellId: row['well_id'] as String? ?? '',
      day: DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
      time: row['round_time'] as String? ?? '',
      values: values,
      operatorName: row['operator_name'] as String? ?? '',
      comment: row['comment'] as String?,
      photo: row['photo'] as String?,
      recordedAt: DateTime.tryParse(row['recorded_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

final roundsControllerProvider = StateNotifierProvider<RoundsController, RoundsState>((ref) => RoundsController());
