import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';

const backupAppId = 'PuitsTrack';
const backupMimeType = 'application/json';

/// Sous-dossier de Téléchargements/PuitsTrack où sont rangées les
/// sauvegardes enregistrées sur le téléphone.
const backupFolder = 'Sauvegardes';

class InvalidBackupException implements Exception {
  /// Clé de traduction du message (voir `app_strings.dart`).
  final String messageKey;
  const InvalidBackupException(this.messageKey);

  @override
  String toString() => messageKey;
}

/// Contenu d'une sauvegarde, lu et vérifié avant restauration.
class BackupPayload {
  final int schemaVersion;
  final DateTime? exportedAt;
  final Map<String, List<Map<String, Object?>>> tables;

  const BackupPayload({required this.schemaVersion, required this.exportedAt, required this.tables});

  int count(String table) => tables[table]?.length ?? 0;
}

/// Sauvegarde complète des données (puits, types d'analyse et seuils,
/// analyses, interventions) dans un fichier JSON, et restauration.
///
/// Les réglages de l'appareil (thème, code, profil...) ne font pas partie de
/// la sauvegarde : elle sert à retrouver les données sur un autre téléphone
/// ou après une réinstallation.
class BackupService {
  static Future<Map<String, Object?>> _snapshot() async {
    final db = await LocalDatabase.instance.database;
    return {
      'app': backupAppId,
      'schemaVersion': LocalDatabase.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': {for (final table in LocalDatabase.dataTables) table: await db.query(table)},
    };
  }

  /// Contenu JSON (UTF-8) d'une sauvegarde de l'état actuel.
  static Future<List<int>> encode() async {
    final data = await _snapshot();
    return utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
  }

  /// Nombre total d'enregistrements (pour ne pas sauvegarder une base vide).
  static Future<int> recordCount() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.rawQuery('select count(*) as n from analysis_records');
    return (rows.first['n'] as int?) ?? 0;
  }

  static String fileName(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'puitstrack_sauvegarde_${at.year}${two(at.month)}${two(at.day)}_${two(at.hour)}${two(at.minute)}.json';
  }

  /// Lit et vérifie une sauvegarde. Lève [InvalidBackupException] si le
  /// fichier n'est pas une sauvegarde PuitsTrack exploitable.
  static BackupPayload parse(String content) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      throw const InvalidBackupException('backupErrorNotJson');
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != backupAppId || decoded['tables'] is! Map) {
      throw const InvalidBackupException('backupErrorNotPuitsTrack');
    }
    final version = decoded['schemaVersion'];
    if (version is! int) throw const InvalidBackupException('backupErrorNotPuitsTrack');
    if (version > LocalDatabase.schemaVersion) {
      throw const InvalidBackupException('backupErrorTooRecent');
    }

    final rawTables = decoded['tables'] as Map;
    final tables = <String, List<Map<String, Object?>>>{};
    try {
      for (final table in LocalDatabase.dataTables) {
        final rows = rawTables[table];
        // Table absente : sauvegarde d'une version plus ancienne de l'app,
        // ces données-là ne sont pas touchées à la restauration.
        if (rows == null) continue;
        tables[table] = [for (final row in rows as List) Map<String, Object?>.from(row as Map)];
      }
    } catch (_) {
      throw const InvalidBackupException('backupErrorCorrupted');
    }
    if ((tables['wells'] ?? const []).isEmpty && (tables['analysis_types'] ?? const []).isEmpty) {
      throw const InvalidBackupException('backupErrorEmpty');
    }
    final exportedAt = decoded['exportedAt'];
    return BackupPayload(
      schemaVersion: version,
      exportedAt: exportedAt is String ? DateTime.tryParse(exportedAt) : null,
      tables: tables,
    );
  }

  /// Remplace toutes les données par celles de [payload], en une seule
  /// transaction (tout ou rien). Les colonnes inconnues sont ignorées, les
  /// colonnes absentes (sauvegarde d'une version plus ancienne) prennent leur
  /// valeur par défaut.
  ///
  /// Avec la synchronisation, la sauvegarde restaurée devient la version la
  /// plus récente : toutes ses lignes sont marquées "à envoyer" et les
  /// lignes qui n'y figurent pas sont supprimées aussi sur les autres
  /// appareils.
  static Future<void> restore(BackupPayload payload) async {
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final table in LocalDatabase.dataTables) {
        if (!payload.tables.containsKey(table)) continue;
        final columns = (await txn.rawQuery('pragma table_info($table)')).map((c) => c['name'] as String).toSet();
        final previousIds = (await txn.query(table, columns: ['id'])).map((r) => r['id'] as String).toSet();
        await txn.delete(table);
        final batch = txn.batch();
        final restoredIds = <String>{};
        for (final row in payload.tables[table] ?? const <Map<String, Object?>>[]) {
          restoredIds.add('${row['id']}');
          batch.insert(table, {
            for (final entry in row.entries)
              if (columns.contains(entry.key)) entry.key: entry.value,
            'updated_at': now,
            'dirty': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
        for (final id in previousIds.difference(restoredIds)) {
          await LocalDatabase.recordDeletion(txn, table, id);
        }
      }
      await LocalDatabase.addBuiltInTypesSince(txn, payload.schemaVersion);
    });
    LocalDatabase.instance.notifyChange();
  }
}
