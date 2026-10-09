import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';
import '../team/team_service.dart';
import 'firebase_config.dart';
import 'firebase_rest.dart';
import 'firestore_value.dart';

/// Petit stockage clé/valeur (dernière synchronisation par table...) :
/// SharedPreferences dans l'app, mémoire dans les tests.
abstract class SyncStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class MemorySyncStore implements SyncStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

class SyncReport {
  final int pushed;
  final int pulled;
  const SyncReport({required this.pushed, required this.pulled});
}

/// Nombre de lignes par écriture groupée (max Firestore : 500 écritures,
/// chaque ligne s'accompagne d'une entrée du journal d'audit).
const _pushBatch = 200;

/// Taille d'une page de lecture.
const _pullPage = 500;

/// Recouvrement entre deux lectures : un document écrit juste avant la
/// lecture précédente, mais devenu visible juste après, n'est pas oublié.
const _pullOverlap = Duration(minutes: 2);

const _epoch = '1970-01-01T00:00:00Z';

/// Synchronisation bidirectionnelle entre la base locale (SQLite) et
/// Firestore, où les données de l'équipe sont partagées sous
/// `<table>/<id>` :
///
/// 1. lecture des documents modifiés depuis la dernière synchronisation
///    (`syncedAt` > dernière date connue), fusionnés dans la base locale ;
/// 2. envoi des lignes modifiées localement (`dirty = 1`) et des suppressions
///    (`sync_deletions`) des tables que le rôle du compte peut modifier,
///    horodatées par le serveur (`syncedAt`), avec une entrée du journal
///    d'audit par ligne.
///
/// En cas de conflit (même ligne modifiée sur deux appareils), la version
/// la plus récente (`updated_at`) l'emporte. La base locale reste la source
/// des écrans : sans réseau, l'app fonctionne normalement et rattrape au
/// retour du réseau.
class SyncEngine {
  final Future<Database> Function() openDatabase;
  final FirestoreRest firestore;
  final FirebaseRestConfig config;
  final SyncStore store;

  SyncEngine({required this.openDatabase, required this.firestore, required this.config, required this.store});

  final _columns = <String, Set<String>>{};

  String _key(String name, String uid) => 'sync2_${name}_${config.projectId}_$uid';

  /// Première connexion de ce compte sur cet appareil : les données saisies
  /// ici (hors données de démarrage jamais modifiées) des tables que le rôle
  /// peut modifier seront envoyées.
  Future<void> prepareFirstSync(String uid, {Set<String>? writable}) async {
    final key = _key('initialized', uid);
    if (await store.read(key) != null) return;
    final db = await openDatabase();
    for (final table in LocalDatabase.dataTables) {
      if (writable == null || writable.contains(table)) {
        await db.update(table, {'dirty': 1}, where: 'updated_at > 0');
      }
    }
    await store.write(key, DateTime.now().toIso8601String());
  }

  /// Lit d'abord les changements des autres appareils (une version distante
  /// plus récente remplace une modification locale plus ancienne), puis
  /// envoie ce qui reste à envoyer — dans l'ordre inverse, un appareil
  /// pourrait écraser sur le serveur une version plus récente venue
  /// d'ailleurs.
  ///
  /// [writable] : tables que le compte peut modifier (toutes par défaut) ;
  /// les modifications locales des autres tables sont abandonnées au profit
  /// de la version de l'équipe. [actor] : auteur inscrit au journal d'audit.
  Future<SyncReport> sync(AuthSession session, {Set<String>? writable, AuditActor? actor}) async {
    final allowed = writable ?? LocalDatabase.dataTables.toSet();
    await _discardForbidden(session, allowed);
    final pulled = await _pull(session);
    final pushed = await _push(session, allowed, actor);
    return SyncReport(pushed: pushed, pulled: pulled);
  }

  /// Modifications locales d'une table que le rôle ne permet pas d'envoyer
  /// (ex: puits modifié avant de rejoindre l'équipe en opérateur) : elles
  /// sont abandonnées et la table est relue entièrement depuis Firestore.
  Future<void> _discardForbidden(AuthSession session, Set<String> allowed) async {
    final db = await openDatabase();
    for (final table in LocalDatabase.dataTables) {
      if (allowed.contains(table)) continue;
      final dirty = await db.update(table, {'dirty': 0, 'updated_at': 0}, where: 'dirty = 1');
      final deletions = await db.delete('sync_deletions', where: 'table_name = ?', whereArgs: [table]);
      if (dirty > 0 || deletions > 0) await store.write(_key('last', '${session.uid}_$table'), null);
    }
  }

  // ------------------------------------------------------------- Envoi

  Future<int> _push(AuthSession session, Set<String> allowed, AuditActor? actor) async {
    final db = await openDatabase();
    final describe = _Describer(db);
    var count = 0;
    for (final table in LocalDatabase.dataTables) {
      if (!allowed.contains(table)) continue;
      // Boucle par lots ; garde-fou contre une boucle infinie si une ligne
      // est modifiée en continu pendant l'envoi.
      for (var guard = 0; guard < 200; guard++) {
        final rows = await db.query(table, where: 'dirty = 1', limit: _pushBatch);
        if (rows.isEmpty) break;
        final writes = <Map<String, Object?>>[];
        for (final row in rows) {
          writes.add(_upsertWrite(table, row));
          if (actor != null) {
            writes.add(
              auditWrite(
                config,
                actor,
                action: 'save',
                table: table,
                docId: row['id'] as String,
                label: await describe(table, row),
                changedAt: (row['updated_at'] as num?)?.toInt(),
              ),
            );
          }
        }
        await firestore.commit(session.idToken, writes);
        for (final row in rows) {
          // Seulement si la ligne n'a pas changé entre-temps (sinon elle
          // reste à envoyer au prochain passage).
          await db.update(
            table,
            {'dirty': 0},
            where: 'id = ? and updated_at = ?',
            whereArgs: [row['id'], row['updated_at']],
          );
        }
        count += rows.length;
      }
    }

    final tables = allowed.where(LocalDatabase.dataTables.contains).toList();
    if (tables.isEmpty) return count;
    final inTables = 'table_name in (${List.filled(tables.length, '?').join(', ')})';
    for (var guard = 0; guard < 200; guard++) {
      final deletions = await db.query('sync_deletions', where: inTables, whereArgs: tables, limit: _pushBatch);
      if (deletions.isEmpty) break;
      final writes = <Map<String, Object?>>[];
      for (final d in deletions) {
        final table = d['table_name'] as String;
        final id = d['row_id'] as String;
        writes.add(_write(table, id, {'deleted': true, 'updated_at': d['deleted_at']}));
        if (actor != null) {
          writes.add(
            auditWrite(
              config,
              actor,
              action: 'delete',
              table: table,
              docId: id,
              label: id,
              changedAt: (d['deleted_at'] as num?)?.toInt(),
            ),
          );
        }
      }
      await firestore.commit(session.idToken, writes);
      for (final d in deletions) {
        await db.delete(
          'sync_deletions',
          where: 'table_name = ? and row_id = ? and deleted_at = ?',
          whereArgs: [d['table_name'], d['row_id'], d['deleted_at']],
        );
      }
      count += deletions.length;
    }
    return count;
  }

  Map<String, Object?> _upsertWrite(String table, Map<String, Object?> row) {
    final data = Map<String, Object?>.from(row)..remove('dirty');
    data['deleted'] = false;
    return _write(table, row['id'] as String, data);
  }

  /// Remplace entièrement le document et lui donne l'heure du serveur dans
  /// `syncedAt` (base de la lecture incrémentale des autres appareils).
  Map<String, Object?> _write(String table, String id, Map<String, Object?> data) => {
    'update': {'name': config.documentName('$table/$id'), 'fields': encodeFields(data)},
    'updateTransforms': [
      {'fieldPath': 'syncedAt', 'setToServerValue': 'REQUEST_TIME'},
    ],
  };

  // ------------------------------------------------------------- Lecture

  Future<int> _pull(AuthSession session) async {
    final db = await openDatabase();
    var applied = 0;
    for (final table in LocalDatabase.dataTables) {
      final key = _key('last', '${session.uid}_$table');
      final last = await store.read(key) ?? _epoch;
      final since = DateTime.parse(last).subtract(_pullOverlap).toUtc().toIso8601String();
      var newest = last;
      Map<String, Object?>? cursor;
      for (var guard = 0; guard < 1000; guard++) {
        final docs = await firestore.runQuery(session.idToken, '', {
          'from': [
            {'collectionId': table},
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': 'syncedAt'},
              'op': 'GREATER_THAN',
              'value': {'timestampValue': since},
            },
          },
          'orderBy': [
            {
              'field': {'fieldPath': 'syncedAt'},
              'direction': 'ASCENDING',
            },
            {
              'field': {'fieldPath': '__name__'},
              'direction': 'ASCENDING',
            },
          ],
          'startAt': ?cursor,
          'limit': _pullPage,
        });
        for (final doc in docs) {
          if (await _apply(db, table, doc)) applied++;
          final syncedAt = decodeFields(doc['fields'] as Map<String, Object?>?)['syncedAt'] as String?;
          if (syncedAt != null && DateTime.parse(syncedAt).isAfter(DateTime.parse(newest))) newest = syncedAt;
        }
        if (docs.length < _pullPage) break;
        final lastDoc = docs.last;
        cursor = {
          'values': [
            (lastDoc['fields'] as Map<String, Object?>)['syncedAt'],
            {'referenceValue': lastDoc['name']},
          ],
          'before': false,
        };
      }
      await store.write(key, newest);
    }
    return applied;
  }

  /// Fusionne un document distant dans la base locale. Retourne `true` si
  /// la base locale a changé.
  Future<bool> _apply(Database db, String table, Map<String, Object?> doc) async {
    final id = (doc['name'] as String).split('/').last;
    final data = decodeFields(doc['fields'] as Map<String, Object?>?);
    final deleted = data.remove('deleted') == true;
    data.remove('syncedAt');
    final remoteUpdated = (data['updated_at'] as num?)?.toInt() ?? 0;

    final local = (await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1)).firstOrNull;
    final localWins =
        local != null && local['dirty'] == 1 && ((local['updated_at'] as num?)?.toInt() ?? 0) > remoteUpdated;
    if (localWins) return false;

    if (deleted) {
      if (local == null) return false;
      await db.delete(table, where: 'id = ?', whereArgs: [id]);
      return true;
    }

    // Supprimée ici plus récemment que la version distante : la suppression
    // locale (encore à envoyer) l'emporte.
    final pendingDeletion = (await db.query(
      'sync_deletions',
      where: 'table_name = ? and row_id = ?',
      whereArgs: [table, id],
      limit: 1,
    )).firstOrNull;
    if (pendingDeletion != null && ((pendingDeletion['deleted_at'] as num?)?.toInt() ?? 0) > remoteUpdated) {
      return false;
    }

    // Déjà à jour (ex: document renvoyé par le recouvrement de lecture).
    if (local != null && local['dirty'] == 0 && ((local['updated_at'] as num?)?.toInt() ?? 0) == remoteUpdated) {
      return false;
    }

    final columns = await _tableColumns(db, table);
    final row = <String, Object?>{
      for (final entry in data.entries)
        if (columns.contains(entry.key)) entry.key: entry.value,
      'id': id,
      'updated_at': remoteUpdated,
      'dirty': 0,
    };
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<Set<String>> _tableColumns(Database db, String table) async {
    return _columns[table] ??= (await db.rawQuery('pragma table_info($table)')).map((c) => c['name'] as String).toSet();
  }
}

/// Description lisible d'une ligne pour le journal d'audit (ex:
/// "PN-01 · BSW = 0.8 %").
class _Describer {
  final Database db;
  _Describer(this.db);

  Map<String, Map<String, Object?>>? _wells;
  Map<String, Map<String, Object?>>? _types;
  Map<String, Map<String, Object?>>? _points;

  Future<Map<String, Map<String, Object?>>> _index(String table) async => {
    for (final row in await db.query(table)) row['id'] as String: row,
  };

  Future<String> call(String table, Map<String, Object?> row) async {
    String v(String key) => '${row[key] ?? ''}';
    switch (table) {
      case 'wells':
        return '${v('code')} — ${v('name')}';
      case 'analysis_types':
        return '${v('label')} (${v('unit')})';
      case 'analysis_records':
        final wells = _wells ??= await _index('wells');
        final types = _types ??= await _index('analysis_types');
        final type = types[row['type_id']];
        return '${wells[row['well_id']]?['code'] ?? v('well_id')} · ${type?['label'] ?? v('type_id')} = '
                '${v('value')} ${type?['unit'] ?? ''}'
            .trim();
      case 'interventions':
        final wells = _wells ??= await _index('wells');
        final date = v('intervention_date');
        return '${wells[row['well_id']]?['code'] ?? v('well_id')} · ${date.length >= 10 ? date.substring(0, 10) : date}';
      case 'sample_points':
        return '${v('code')} — ${v('name')}';
      case 'plant_analyses':
        final points = _points ??= await _index('sample_points');
        return '${points[row['point_id']]?['code'] ?? v('point_id')} · ${v('analysis_date')}';
      case 'plant_thresholds':
        final points = _points ??= await _index('sample_points');
        return '${points[row['point_id']]?['code'] ?? v('point_id')} · ${v('param_key')} : '
            '${row['min_value'] ?? '—'} – ${row['max_value'] ?? '—'}';
      case 'app_config':
        return '${v('id')} = ${v('value')}';
      default:
        return v('id');
    }
  }
}
