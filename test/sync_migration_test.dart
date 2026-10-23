// Migration d'une base existante (v5, avant la synchronisation) vers v6 :
// les données saisies doivent être prêtes à être envoyées, les puits et
// types de démarrage jamais modifiés ne doivent jamais écraser une version
// modifiée ailleurs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/data/local_database.dart';
import 'package:puitstrack/core/sync/firebase_config.dart';
import 'package:puitstrack/core/sync/firebase_rest.dart';
import 'package:puitstrack/core/sync/sync_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _createV5(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 5,
      onCreate: (db, _) async {
        await db.execute(
          'create table wells (id text primary key, code text not null, name text not null, '
          "active integer not null default 1, group_name text not null default '', reservoir_pressure real)",
        );
        await db.execute(
          'create table analysis_types (id text primary key, label text not null, unit text not null, '
          'min_value real not null, max_value real not null, frequency text not null)',
        );
        await db.execute(
          'create table analysis_records (id text primary key, well_id text not null, '
          'type_id text not null, value real not null, service_key text not null, operator_name text not null, '
          'operator_id text, comment text, recorded_at text not null)',
        );
        await db.execute(
          'create table interventions (id text primary key, well_id text not null, '
          'intervention_date text not null, type_key text not null, cost real, currency text not null, '
          'result_key text not null, description text, operator_name text not null, created_at text not null)',
        );
        // Puits de démarrage intact, puits de démarrage renommé, puits ajouté.
        await db.insert('wells', {
          'id': 'w1',
          'code': 'PN-01',
          'name': 'Puits Nord 1',
          'active': 1,
          'group_name': 'Zone Nord',
        });
        await db.insert('wells', {
          'id': 'w2',
          'code': 'PN-02',
          'name': 'Mon puits',
          'active': 1,
          'group_name': 'Zone Nord',
        });
        await db.insert('wells', {'id': 'x9', 'code': 'X-9', 'name': 'Nouveau', 'active': 1, 'group_name': ''});
        await db.insert('analysis_types', {
          'id': 't_bsw',
          'label': 'BSW',
          'unit': '%',
          'min_value': 0.0,
          'max_value': 2.0,
          'frequency': 'daily',
        });
        await db.insert('analysis_types', {
          'id': 't_h2s',
          'label': 'H2S',
          'unit': 'ppm',
          'min_value': 0.0,
          'max_value': 5.0,
          'frequency': 'daily',
        });
        await db.insert('analysis_records', {
          'id': 'r1',
          'well_id': 'w1',
          'type_id': 't_bsw',
          'value': 1.2,
          'service_key': 'serviceLaboratoire',
          'operator_name': 'Ahmed',
          'recorded_at': '2026-10-01T08:00:00.000',
        });
      },
    ),
  );
  await db.close();
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('v5 → v6 : dates de modification et données prêtes à envoyer', () async {
    final dir = await Directory.systemTemp.createTemp('puitstrack_mig_');
    final path = '${dir.path}/old.db';
    await _createV5(path);

    final db = await LocalDatabase.openAt(path, factory: databaseFactoryFfi);
    Future<int> updatedAt(String table, String id) async =>
        (await db.query(table, where: 'id = ?', whereArgs: [id])).first['updated_at'] as int;

    expect(await updatedAt('wells', 'w1'), 0, reason: 'puits de démarrage intact');
    expect(await updatedAt('wells', 'w2'), greaterThan(0), reason: 'puits renommé');
    expect(await updatedAt('wells', 'x9'), greaterThan(0), reason: 'puits ajouté');
    expect(await updatedAt('analysis_types', 't_bsw'), 0, reason: 'type intact');
    expect(await updatedAt('analysis_types', 't_h2s'), greaterThan(0), reason: 'seuil modifié');
    expect(await updatedAt('analysis_records', 'r1'), greaterThan(0));
    expect(await db.query('sync_deletions'), isEmpty);
    // v7 : module Usine (points de prélèvement de démarrage, non envoyés).
    // v10 : + circuit Traitement eau (7 points de plus).
    expect(await db.query('sample_points'), hasLength(20));
    expect(await db.query('sample_points', where: 'dirty = 1 or updated_at > 0'), isEmpty);
    // v9 : circuits configurables (Administration > Circuits), de démarrage.
    // v10 : + circuit Traitement eau.
    expect(await db.query('plant_circuits'), hasLength(5));
    expect(await db.query('plant_circuits', where: 'dirty = 1 or updated_at > 0'), isEmpty);
    // v8 : type, statut, coordonnées des puits (statut déduit de "actif"),
    // paramètres par point, alerte par seuil, paramètres partagés.
    final w1 = (await db.query('wells', where: 'id = ?', whereArgs: ['w1'])).first;
    expect(w1['well_type'], '');
    expect(w1['status'], '');
    expect(w1.containsKey('latitude'), isTrue);
    expect((await db.query('sample_points')).first.containsKey('params_json'), isTrue);
    expect(await db.query('app_config'), isEmpty);
    // v11 : schémas configurables (schéma intégré de démarrage, non envoyé).
    expect(await db.query('plant_schemas'), hasLength(1));
    expect(await db.query('plant_schemas', where: 'dirty = 1 or updated_at > 0'), isEmpty);
    // v12 : paramètres personnalisés et modèles modifiables (vides).
    expect(await db.query('plant_params'), isEmpty);
    expect(await db.query('plant_profiles'), isEmpty);
    // v13 : stock (articles et mouvements, vides).
    expect(await db.query('stock_items'), isEmpty);
    expect(await db.query('stock_movements'), isEmpty);
    // v14 : plusieurs analyses possibles par point et par jour (l'index
    // unique point + jour de la v7 est supprimé).
    final plantIndexes = await db.rawQuery(
      "select name from sqlite_master where type = 'index' and tbl_name = 'plant_analyses'",
    );
    expect(plantIndexes.map((r) => r['name']), isNot(contains('plant_analyses_point_date')));
    // v15 : heure de début et de fin du prélèvement (facultatives).
    final plantAnalysesColumns = await db.rawQuery('pragma table_info(plant_analyses)');
    expect(plantAnalysesColumns.map((r) => r['name']), containsAll(['start_time', 'end_time']));
    // v16 : masquage d'un paramètre intégré (retiré du catalogue).
    final plantParamsColumns = await db.rawQuery('pragma table_info(plant_params)');
    expect(plantParamsColumns.map((r) => r['name']), contains('hidden'));
    // v17 : photo jointe à une analyse (facultative).
    expect(plantAnalysesColumns.map((r) => r['name']), contains('photo'));
    // v18 : description lisible d'une ligne supprimée (journal d'audit).
    final syncDeletionsColumns = await db.rawQuery('pragma table_info(sync_deletions)');
    expect(syncDeletionsColumns.map((r) => r['name']), contains('label'));
    // v19 : suivi annuel du stock (référence, MMN, consommation N-1, commande).
    final stockItemsColumns = await db.rawQuery('pragma table_info(stock_items)');
    expect(stockItemsColumns.map((r) => r['name']), containsAll(['reference', 'mmn', 'prev_consumption', 'pending_order']));
    // v20 : types d'analyse "test de puits" (choke, tête de puits, injection
    // chimique, séparateur de test).
    final testTypeIds = (await db.query('analysis_types', columns: ['id'])).map((r) => r['id']);
    expect(testTypeIds, containsAll(['t_choke', 't_wellhead_pressure', 't_test_gas_rate']));
    // v21 : regroupement visuel des types d'analyse (ex: "Tête de puits"),
    // appliqué aux types "test de puits" qui viennent d'être insérés ci-dessus.
    final analysisTypesColumns = await db.rawQuery('pragma table_info(analysis_types)');
    expect(analysisTypesColumns.map((r) => r['name']), contains('group_label'));
    final wellhead = (await db.query(
      'analysis_types',
      columns: ['group_label'],
      where: 'id = ?',
      whereArgs: ['t_wellhead_pressure'],
    )).first;
    expect(wellhead['group_label'], 'Tête de puits');
    expect(LocalDatabase.schemaVersion, 21);

    // Première connexion : tout ce qui a été saisi/modifié part au serveur.
    final engine = SyncEngine(
      openDatabase: () async => db,
      firestore: FirestoreRest(FirebaseRestConfig.emulator()),
      config: FirebaseRestConfig.emulator(),
      store: MemorySyncStore(),
    );
    // Opérateur : seules ses tables (analyses) sont préparées à l'envoi.
    await engine.prepareFirstSync('companies/c1', 'uid-op', writable: {'analysis_records', 'plant_analyses'});
    expect((await db.query('wells', where: 'dirty = 1')), isEmpty);
    await db.update('analysis_records', {'dirty': 0});

    await engine.prepareFirstSync('companies/c1', 'uid-test');
    final dirty = {
      for (final table in LocalDatabase.dataTables)
        for (final row in await db.query(table, where: 'dirty = 1')) '$table/${row['id']}',
    };
    expect(dirty, {'wells/w2', 'wells/x9', 'analysis_types/t_h2s', 'analysis_records/r1'});

    await db.close();
    await dir.delete(recursive: true);
  });
}
