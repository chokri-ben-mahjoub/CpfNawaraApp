import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../platform/app_platform.dart';

/// Base locale SQLite (sqflite) : seule source de données tant qu'aucun
/// backend partagé n'est branché (voir README, section "Mode local actuel").
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  /// Version du schéma (voir `onUpgrade`), enregistrée dans les sauvegardes.
  static const schemaVersion = 5;

  /// Tables sauvegardées / restaurées (voir `backup_service.dart`).
  static const dataTables = ['wells', 'analysis_types', 'analysis_records', 'interventions'];

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  /// Chemin du fichier de base (affiché dans Réglages › Données). Sur PC, dans
  /// AppData (dossier de l'app) plutôt que dans "Documents", visible et
  /// modifiable par l'utilisateur.
  Future<String> get path async {
    // Navigateur : simple nom de base (stockée dans IndexedDB).
    if (isWeb) return 'suivi_puits.db';
    final dir = isAndroid || isIOS ? await getApplicationDocumentsDirectory() : await getApplicationSupportDirectory();
    return p.join(dir.path, 'suivi_puits.db');
  }

  Future<Database> _open() async {
    return openDatabase(
      await path,
      version: schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          create table wells (
            id text primary key,
            code text not null,
            name text not null,
            active integer not null default 1,
            group_name text not null default '',
            reservoir_pressure real
          )
        ''');
        await db.execute('''
          create table analysis_types (
            id text primary key,
            label text not null,
            unit text not null,
            min_value real not null,
            max_value real not null,
            frequency text not null
          )
        ''');
        await db.execute('''
          create table analysis_records (
            id text primary key,
            well_id text not null,
            type_id text not null,
            value real not null,
            service_key text not null,
            operator_name text not null,
            operator_id text,
            comment text,
            recorded_at text not null
          )
        ''');
        await _createInterventionsTable(db);
        await _seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("alter table wells add column group_name text not null default ''");
        }
        if (oldVersion < 3) {
          for (final type in _productionFlowTypes) {
            await db.insert('analysis_types', type, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        if (oldVersion < 4) {
          // Renomme les puits de démo "Nawara ..." vers des noms génériques —
          // seulement s'ils n'ont pas déjà été renommés par l'utilisateur
          // (on ne touche qu'aux id/nom encore identiques au seed d'origine).
          for (final rename in _wellRenames) {
            await db.update(
              'wells',
              {'code': rename['newCode'], 'name': rename['newName']},
              where: 'id = ? and name = ?',
              whereArgs: [rename['id'], rename['oldName']],
            );
          }
        }
        if (oldVersion < 5) {
          // Journal des interventions + pression de gisement (Pr) par puits
          // + type "Pression de fond (Pwf)" : de quoi calculer le PI.
          await db.execute('alter table wells add column reservoir_pressure real');
          await _createInterventionsTable(db);
          await db.insert('analysis_types', _bottomHolePressureType, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      },
    );
  }

  /// Réajoute les types d'analyse intégrés apparus après la version
  /// [fromVersion] du schéma (débits en v3, Pwf en v5) — utilisé après la
  /// restauration d'une sauvegarde créée par une version plus ancienne.
  static Future<void> addBuiltInTypesSince(DatabaseExecutor db, int fromVersion) async {
    if (fromVersion < 3) {
      for (final type in _productionFlowTypes) {
        await db.insert('analysis_types', type, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    if (fromVersion < 5) {
      await db.insert('analysis_types', _bottomHolePressureType, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Puits et types d'analyse de démarrage, pour ne pas ouvrir l'app sur un
  /// écran totalement vide. Aucun enregistrement d'analyse n'est pré-rempli :
  /// l'historique reflète uniquement les vraies saisies.
  Future<void> _seed(Database db) async {
    const wells = [
      {'id': 'w1', 'code': 'PN-01', 'name': 'Puits Nord 1', 'active': 1, 'group_name': 'Zone Nord'},
      {'id': 'w2', 'code': 'PN-02', 'name': 'Puits Nord 2', 'active': 1, 'group_name': 'Zone Nord'},
      {'id': 'w3', 'code': 'PS-01', 'name': 'Puits Sud 1', 'active': 1, 'group_name': 'Zone Sud'},
      {'id': 'w4', 'code': 'PS-02', 'name': 'Puits Sud 2', 'active': 0, 'group_name': 'Zone Sud'},
      {'id': 'w5', 'code': 'PS-03', 'name': 'Puits Sud 3', 'active': 1, 'group_name': 'Zone Sud'},
    ];
    for (final well in wells) {
      await db.insert('wells', well);
    }

    const types = [
      {'id': 't_bsw', 'label': 'BSW', 'unit': '%', 'min_value': 0.0, 'max_value': 2.0, 'frequency': 'daily'},
      {'id': 't_salinity', 'label': 'Salinité', 'unit': 'mg/L', 'min_value': 0.0, 'max_value': 5000.0, 'frequency': 'daily'},
      {'id': 't_density', 'label': 'Densité', 'unit': 'kg/m³', 'min_value': 780.0, 'max_value': 860.0, 'frequency': 'weekly'},
      {'id': 't_h2s', 'label': 'H2S', 'unit': 'ppm', 'min_value': 0.0, 'max_value': 10.0, 'frequency': 'daily'},
      {'id': 't_pressure', 'label': 'Pression', 'unit': 'bar', 'min_value': 20.0, 'max_value': 120.0, 'frequency': 'daily'},
      {'id': 't_temperature', 'label': 'Température', 'unit': '°C', 'min_value': 15.0, 'max_value': 90.0, 'frequency': 'daily'},
      ..._productionFlowTypes,
      _bottomHolePressureType,
    ];
    for (final type in types) {
      await db.insert('analysis_types', type);
    }
  }
}

Future<void> _createInterventionsTable(Database db) async {
  await db.execute('''
    create table if not exists interventions (
      id text primary key,
      well_id text not null,
      intervention_date text not null,
      type_key text not null,
      cost real,
      currency text not null default 'TND',
      result_key text not null,
      description text,
      operator_name text not null,
      created_at text not null
    )
  ''');
}

/// Pression de fond dynamique (Pwf) : mesure ponctuelle ("à la demande"),
/// jamais attendue un jour donné — elle n'ajoute donc aucune tâche "à faire"
/// ni alerte de retard. Plage très large : pas de vrai seuil de conformité.
const _bottomHolePressureType = {
  'id': 't_pwf',
  'label': 'Pression de fond (Pwf)',
  'unit': 'bar',
  'min_value': 0.0,
  'max_value': 1000.0,
  'frequency': 'on_demand',
};

/// Correspondance ancien → nouveau nom des 5 puits de démo, utilisée par la
/// migration v4 (voir `onUpgrade`) pour les installations déjà existantes.
const _wellRenames = [
  {'id': 'w1', 'oldName': 'Nawara 12', 'newCode': 'PN-01', 'newName': 'Puits Nord 1'},
  {'id': 'w2', 'oldName': 'Nawara 07', 'newCode': 'PN-02', 'newName': 'Puits Nord 2'},
  {'id': 'w3', 'oldName': 'Nawara 21', 'newCode': 'PS-01', 'newName': 'Puits Sud 1'},
  {'id': 'w4', 'oldName': 'Nawara 04', 'newCode': 'PS-02', 'newName': 'Puits Sud 2'},
  {'id': 'w5', 'oldName': 'Nawara 15', 'newCode': 'PS-03', 'newName': 'Puits Sud 3'},
];

/// Débits de production (huile/gaz/eau), suivis quotidiennement puits par
/// puits — voir la carte "Production" sur la fiche puits. Pas de vrai seuil
/// de non-conformité pour ces valeurs (production normale très variable
/// selon le puits) : la plage est volontairement large pour ne jamais
/// déclencher d'alerte "hors seuil".
const _productionFlowTypes = [
  {'id': 't_oil_flow', 'label': 'Débit huile', 'unit': 'm³/j', 'min_value': 0.0, 'max_value': 100000.0, 'frequency': 'daily'},
  {'id': 't_gas_flow', 'label': 'Débit gaz', 'unit': 'Sm³/j', 'min_value': 0.0, 'max_value': 1000000.0, 'frequency': 'daily'},
  {'id': 't_water_flow', 'label': 'Débit eau', 'unit': 'm³/j', 'min_value': 0.0, 'max_value': 100000.0, 'frequency': 'daily'},
];
