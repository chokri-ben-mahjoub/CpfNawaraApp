import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';

/// Paramètres communs à toute l'équipe (table `app_config`, synchronisée
/// comme les données, modifiable par l'administrateur) — distincts des
/// Réglages, propres à chaque appareil.
class SharedConfig {
  final Map<String, String> values;
  const SharedConfig(this.values);

  static const empty = SharedConfig({});

  /// Heure limite de réception des analyses du jour : passé cette heure,
  /// une analyse attendue et non saisie est signalée "non reçue".
  TimeOfDay get missingDeadline {
    final parts = (values[missingDeadlineKey] ?? '').split(':');
    final h = int.tryParse(parts.first);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (h == null || h < 0 || h > 23 || m == null || m < 0 || m > 59) return defaultMissingDeadline;
    return TimeOfDay(hour: h, minute: m);
  }

  /// Vrai si l'heure limite du jour [now] est dépassée.
  bool isPastDeadline(DateTime now) {
    final d = missingDeadline;
    return now.hour > d.hour || (now.hour == d.hour && now.minute >= d.minute);
  }
}

const missingDeadlineKey = 'missing_deadline';
const defaultMissingDeadline = TimeOfDay(hour: 10, minute: 0);

String formatDeadline(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class SharedConfigController extends StateNotifier<SharedConfig> {
  SharedConfigController() : super(SharedConfig.empty) {
    reload();
  }

  @visibleForTesting
  SharedConfigController.seeded(super.initial);

  Future<void> reload() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query('app_config');
    state = SharedConfig({
      for (final row in rows)
        if (row['value'] != null) row['id'] as String: row['value'] as String,
    });
  }

  Future<void> set(String key, String value) async {
    final db = await LocalDatabase.instance.database;
    await db.insert(
      'app_config',
      LocalDatabase.stamp({'id': key, 'value': value}),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await reload();
    LocalDatabase.instance.notifyChange();
  }

  Future<void> setMissingDeadline(TimeOfDay time) => set(missingDeadlineKey, formatDeadline(time));
}

final sharedConfigProvider = StateNotifierProvider<SharedConfigController, SharedConfig>(
  (ref) => SharedConfigController(),
);
