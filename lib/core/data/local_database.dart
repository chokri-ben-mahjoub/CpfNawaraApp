import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../plant/plant_catalog.dart';
import '../platform/app_platform.dart';

/// Base locale SQLite (sqflite) : source de données de l'app sur chaque
/// appareil. Quand un compte de synchronisation est connecté (Réglages ›
/// Synchronisation), elle est recopiée dans Firestore et fusionnée avec les
/// autres appareils (voir `lib/core/sync/`).
///
/// Chaque ligne porte `updated_at` (ms depuis l'époque, 0 = donnée de
/// démarrage jamais modifiée) et `dirty` (1 = modification locale pas encore
/// envoyée) ; les suppressions sont notées dans `sync_deletions` pour être
/// propagées aux autres appareils.
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  /// Version du schéma (voir `onUpgrade`), enregistrée dans les sauvegardes.
  static const schemaVersion = 17;

  /// Tables sauvegardées / restaurées / synchronisées.
  static const dataTables = [
    'wells',
    'analysis_types',
    'analysis_records',
    'interventions',
    // Module Usine CPF (v7).
    'sample_points',
    'plant_analyses',
    'plant_thresholds',
    // Paramètres partagés (heure limite des analyses...), v8.
    'app_config',
    // Circuits configurables (remplace l'énumération fixe), v9.
    'plant_circuits',
    // Schémas de l'usine (dessin intégré, image importée ou fond vierge), v11.
    'plant_schemas',
    // Paramètres personnalisés et modèles de paramètres modifiables, v12.
    'plant_params',
    'plant_profiles',
    // Gestion de stock (articles + mouvements), v13.
    'stock_items',
    'stock_movements',
  ];

  /// Tables qui ont reçu les colonnes de synchronisation par migration (v6) ;
  /// les suivantes sont créées directement avec.
  static const _v6Tables = ['wells', 'analysis_types', 'analysis_records', 'interventions'];

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  final _changes = StreamController<void>.broadcast();

  /// Émis après chaque modification locale (saisie, correction, suppression)
  /// : la synchronisation s'en sert pour envoyer les changements.
  Stream<void> get changes => _changes.stream;

  void notifyChange() => _changes.add(null);

  /// Colonnes de suivi à ajouter à une ligne écrite localement.
  static Map<String, Object?> stamp(Map<String, Object?> row) => {
    ...row,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
    'dirty': 1,
  };

  /// Efface toutes les données de cet appareil et remet les données de
  /// démarrage : utilisé quand l'appareil passe à une autre entreprise, pour
  /// que les données d'une entreprise ne partent jamais dans une autre.
  Future<void> resetToSeed() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in dataTables) {
        await txn.delete(table);
      }
      await txn.delete('sync_deletions');
    });
    await _seed(db);
    notifyChange();
  }

  /// Note la suppression d'une ligne pour la propager aux autres appareils.
  static Future<void> recordDeletion(DatabaseExecutor db, String table, String id) => db.insert('sync_deletions', {
    'table_name': table,
    'row_id': id,
    'deleted_at': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Chemin du fichier de base (affiché dans Réglages › Données). Sur PC, dans
  /// AppData (dossier de l'app) plutôt que dans "Documents", visible et
  /// modifiable par l'utilisateur.
  Future<String> get path async {
    // Navigateur : simple nom de base (stockée dans IndexedDB).
    if (isWeb) return 'suivi_puits.db';
    final dir = isAndroid || isIOS ? await getApplicationDocumentsDirectory() : await getApplicationSupportDirectory();
    return p.join(dir.path, 'suivi_puits.db');
  }

  Future<Database> _open() async => openAt(await path);

  /// Ouvre (ou crée) une base au schéma de l'app à [dbPath] — utilisé par
  /// l'app, et par les tests de synchronisation pour simuler plusieurs
  /// appareils.
  static Future<Database> openAt(String dbPath, {DatabaseFactory? factory}) async {
    return (factory ?? databaseFactory).openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
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
          await _addSyncColumns(db);
          await _createPlantTables(db);
          await _migrateV8(db);
          await _createPlantCircuitsTable(db);
          await _createPlantSchemasTable(db);
          await _createPlantParamTables(db);
          await _createStockTables(db);
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
          if (oldVersion < 6) {
            // Synchronisation entre appareils : date de modification + marqueur
            // "à envoyer" + journal des suppressions. Les données déjà saisies
            // reçoivent une date de modification (> 0) ; les puits et types de
            // démarrage jamais modifiés restent à 0, pour ne jamais écraser une
            // version modifiée sur un autre appareil.
            await _addSyncColumns(db);
            final now = DateTime.now().millisecondsSinceEpoch;
            await db.update('analysis_records', {'updated_at': now});
            await db.update('interventions', {'updated_at': now});
            await _stampModifiedSeeds(db, 'wells', _seedWells, now);
            await _stampModifiedSeeds(db, 'analysis_types', _seedTypes, now);
          }
          if (oldVersion < 7) {
            // Module Usine CPF : points de prélèvement, analyses, seuils.
            await _createPlantTables(db);
            await _seedPlantPoints(db);
          }
          if (oldVersion < 8) {
            // Administration : type, statut et coordonnées des puits,
            // paramètres choisis par point, alerte activable par seuil,
            // paramètres partagés.
            await _migrateV8(db);
          }
          if (oldVersion < 9) {
            // Circuits configurables par l'administrateur (Administration >
            // Circuits), remplace l'énumération fixe condensat/eau/gaz/amine.
            await _createPlantCircuitsTable(db);
            await _seedPlantCircuits(db);
          }
          if (oldVersion < 10) {
            // Circuit "Traitement eau" (puits, chloration, stockage, osmose
            // inverse) ajouté aux données de démarrage.
            await _seedPlantCircuits(db);
            await _seedPlantPoints(db);
          }
          if (oldVersion < 11) {
            // Schémas configurables : plusieurs schémas, points placés par
            // l'administrateur (Usine › Schéma › Configurer).
            await _createPlantSchemasTable(db);
            await _seedPlantSchemas(db);
          }
          if (oldVersion < 12) {
            // Paramètres personnalisés et modèles modifiables
            // (Administration > Paramètres et modèles).
            await _createPlantParamTables(db);
          }
          if (oldVersion < 13) {
            // Gestion de stock : articles (chimie, pièces, consommables...)
            // et mouvements (entrées/sorties), avec alerte de seuil bas.
            await _createStockTables(db);
          }
          if (oldVersion < 14) {
            // Plusieurs analyses possibles pour un même point le même jour
            // (plusieurs prélèvements) : l'unicité point + jour n'est plus
            // imposée en base, seule la saisie manuelle en décide.
            await db.execute('drop index if exists plant_analyses_point_date');
          }
          if (oldVersion >= 7 && oldVersion < 15) {
            // Heure de début et de fin du prélèvement/essai (facultatives),
            // en plus de la date. Seulement si la table existait déjà avant
            // cette mise à niveau : sinon elle vient d'être créée avec ces
            // colonnes par `_createPlantTables` (ci-dessus, oldVersion < 7).
            await db.execute('alter table plant_analyses add column start_time text');
            await db.execute('alter table plant_analyses add column end_time text');
          }
          if (oldVersion >= 12 && oldVersion < 16) {
            // Masquage d'un paramètre intégré (retiré du catalogue sans
            // toucher au code) : même mécanisme qu'une surcharge de
            // paramètre personnalisé, avec ce drapeau en plus.
            await db.execute('alter table plant_params add column hidden integer not null default 0');
          }
          if (oldVersion >= 7 && oldVersion < 17) {
            // Photo jointe à une analyse (ex: aspect visuel, étiquette
            // d'échantillon), facultative.
            await db.execute('alter table plant_analyses add column photo text');
          }
        },
      ),
    );
  }

  static Future<void> _migrateV8(Database db) async {
    await db.execute("alter table wells add column well_type text not null default ''");
    await db.execute("alter table wells add column status text not null default ''");
    await db.execute('alter table wells add column latitude real');
    await db.execute('alter table wells add column longitude real');
    await db.execute('alter table sample_points add column params_json text');
    await db.execute('alter table plant_thresholds add column alert_enabled integer not null default 1');
    await db.execute('''
      create table if not exists app_config (
        id text primary key,
        value text,
        updated_at integer not null default 0,
        dirty integer not null default 0
      )
    ''');
  }

  static Future<void> _addSyncColumns(Database db) async {
    for (final table in _v6Tables) {
      await db.execute('alter table $table add column updated_at integer not null default 0');
      await db.execute('alter table $table add column dirty integer not null default 0');
    }
    await db.execute('''
      create table if not exists sync_deletions (
        table_name text not null,
        row_id text not null,
        deleted_at integer not null,
        primary key (table_name, row_id)
      )
    ''');
  }

  /// Module Usine CPF (voir `lib/core/plant/`). `plant_analyses.values_json`
  /// contient les valeurs mesurées ({"bsw": 0.2, "appearance": "..."}) ;
  /// plusieurs analyses peuvent coexister pour un même point et un même jour
  /// (plusieurs prélèvements) : l'unicité n'est plus imposée en base, voir
  /// `PlantController.saveAnalysis`.
  static Future<void> _createPlantTables(DatabaseExecutor db) async {
    await db.execute('''
      create table if not exists sample_points (
        id text primary key,
        code text not null,
        circuit text not null,
        name text not null,
        equipment text not null default '',
        profile text not null,
        sort_order integer not null default 0,
        active integer not null default 1,
        updated_at integer not null default 0,
        dirty integer not null default 0
      )
    ''');
    await db.execute('''
      create table if not exists plant_analyses (
        id text primary key,
        point_id text not null,
        analysis_date text not null,
        values_json text not null,
        source text not null,
        operator_name text not null default '',
        comment text,
        recorded_at text not null,
        start_time text,
        end_time text,
        photo text,
        updated_at integer not null default 0,
        dirty integer not null default 0
      )
    ''');
    await db.execute('''
      create table if not exists plant_thresholds (
        id text primary key,
        point_id text not null,
        param_key text not null,
        min_value real,
        max_value real,
        updated_at integer not null default 0,
        dirty integer not null default 0
      )
    ''');
  }

  static Future<void> _seedPlantPoints(DatabaseExecutor db) async {
    for (final point in plantSeedPoints) {
      await db.insert('sample_points', point, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Circuits de l'usine (Administration > Circuits) : regroupent les points
  /// de prélèvement, remplacent l'ancienne énumération fixe condensat/eau/
  /// gaz/amine, désormais éditables (nom, couleur, icône, profil par défaut).
  static Future<void> _createPlantCircuitsTable(DatabaseExecutor db) async {
    await db.execute('''
      create table if not exists plant_circuits (
        id text primary key,
        label_key text not null,
        color integer not null,
        icon text not null default 'science',
        default_profile text not null default 'condensate',
        sort_order integer not null default 0,
        updated_at integer not null default 0,
        dirty integer not null default 0
      )
    ''');
  }

  /// Schémas de l'usine : `kind` = `pfd` (dessin intégré), `image` (photo ou
  /// scan importé, JPEG en base64 dans `image`) ou `blank` (fond quadrillé).
  /// `positions_json` : {pointId: [x, y]} en fractions de la largeur et de la
  /// hauteur (0 à 1), ou {pointId: null} pour retirer un point du schéma.
  static Future<void> _createPlantSchemasTable(DatabaseExecutor db) async {
    await db.execute('''
      create table if not exists plant_schemas (
        id text primary key,
        name text not null,
        kind text not null default 'blank',
        image text,
        image_width integer,
        image_height integer,
        positions_json text,
        sort_order integer not null default 0,
        updated_at integer not null default 0,
        dirty integer not null default 0
      )
    ''');
  }

  /// Paramètres personnalisés (`plant_params` : libellé et unité libres,
  /// `kind` = `number` ou `choice`, choix en JSON) et modèles de paramètres
  /// (`plant_profiles` : nouveaux modèles, ou modèles intégrés modifiés sous
  /// le même id ; `params_json` = liste ordonnée des clés). Aucune donnée de
  /// démarrage : les modèles intégrés restent dans `plant_catalog.dart`.
  static Future<void> _createPlantParamTables(DatabaseExecutor db) async {
    await db.execute('''
      create table if not exists plant_params (
        id text primary key,
        label text not null,
        unit text not null default '',
        kind text not null default 'number',
        choices_json text,
        ok_choices_json text,
        sort_order integer not null default 0,
        hidden integer not null default 0,
        updated_at integer not null default 0,
        dirty integer not null default 0
      )
    ''');
    await db.execute('''
      create table if not exists plant_profiles (
        id text primary key,
        label text not null,
        params_json text not null default '[]',
        sort_order integer not null default 0,
        updated_at integer not null default 0,
        dirty integer not null default 0
      )
    ''');
  }

  /// Stock : `stock_items` (quantité dénormalisée pour un affichage
  /// instantané, voir `StockItem`) et `stock_movements` (historique des
  /// entrées/sorties, chacune pouvant être liée à un puits consommateur).
  /// Aucune donnée de démarrage : les articles sont propres à chaque
  /// installation.
  static Future<void> _createStockTables(DatabaseExecutor db) async {
    await db.execute('''
      create table if not exists stock_items (
        id text primary key,
        name text not null,
        unit text not null default '',
        quantity real not null default 0,
        threshold real not null default 0,
        category text not null default '',
        notes text,
        updated_at integer not null default 0,
        dirty integer not null default 0
      )
    ''');
    await db.execute('''
      create table if not exists stock_movements (
        id text primary key,
        item_id text not null,
        delta real not null,
        reason text,
        well_id text,
        operator_name text not null default '',
        recorded_at text not null,
        updated_at integer not null default 0,
        dirty integer not null default 0
      )
    ''');
  }

  static Future<void> _seedPlantSchemas(DatabaseExecutor db) async {
    await db.insert('plant_schemas', {
      'id': 'pfd',
      'name': 'plantSchemaPfd',
      'kind': 'pfd',
      'sort_order': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _seedPlantCircuits(DatabaseExecutor db) async {
    for (final circuit in plantSeedCircuits) {
      await db.insert('plant_circuits', circuit, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Date de modification pour les lignes ajoutées ou modifiées par
  /// l'utilisateur ; les lignes identiques aux données de démarrage restent
  /// à 0.
  static Future<void> _stampModifiedSeeds(Database db, String table, List<Map<String, Object?>> seeds, int now) async {
    final byId = {for (final seed in seeds) seed['id']: seed};
    for (final row in await db.query(table)) {
      final seed = byId[row['id']];
      final unchanged = seed != null && seed.entries.every((e) => _sameValue(row[e.key], e.value));
      if (!unchanged) {
        await db.update(table, {'updated_at': now}, where: 'id = ?', whereArgs: [row['id']]);
      }
    }
  }

  static bool _sameValue(Object? a, Object? b) {
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    return a == b;
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
    if (fromVersion < 7) {
      await _seedPlantPoints(db);
    }
    if (fromVersion < 9) {
      await _createPlantCircuitsTable(db);
      await _seedPlantCircuits(db);
    }
    if (fromVersion < 10) {
      await _seedPlantCircuits(db);
      await _seedPlantPoints(db);
    }
    if (fromVersion < 11) {
      await _createPlantSchemasTable(db);
      await _seedPlantSchemas(db);
    }
    if (fromVersion < 12) {
      await _createPlantParamTables(db);
    }
    if (fromVersion < 13) {
      await _createStockTables(db);
    }
  }

  /// Puits et types d'analyse de démarrage, pour ne pas ouvrir l'app sur un
  /// écran totalement vide. Aucun enregistrement d'analyse n'est pré-rempli :
  /// l'historique reflète uniquement les vraies saisies.
  static Future<void> _seed(Database db) async {
    for (final well in _seedWells) {
      await db.insert('wells', well);
    }

    for (final type in _seedTypes) {
      await db.insert('analysis_types', type);
    }
    await _seedPlantCircuits(db);
    await _seedPlantPoints(db);
    await _seedPlantSchemas(db);
  }
}

/// Puits de démarrage (aussi utilisés pour reconnaître, à la migration v6,
/// ceux que l'utilisateur n'a jamais modifiés).
const _seedWells = [
  {
    'id': 'w1',
    'code': 'PN-01',
    'name': 'Puits Nord 1',
    'active': 1,
    'group_name': 'Zone Nord',
    'reservoir_pressure': null,
  },
  {
    'id': 'w2',
    'code': 'PN-02',
    'name': 'Puits Nord 2',
    'active': 1,
    'group_name': 'Zone Nord',
    'reservoir_pressure': null,
  },
  {
    'id': 'w3',
    'code': 'PS-01',
    'name': 'Puits Sud 1',
    'active': 1,
    'group_name': 'Zone Sud',
    'reservoir_pressure': null,
  },
  {
    'id': 'w4',
    'code': 'PS-02',
    'name': 'Puits Sud 2',
    'active': 0,
    'group_name': 'Zone Sud',
    'reservoir_pressure': null,
  },
  {
    'id': 'w5',
    'code': 'PS-03',
    'name': 'Puits Sud 3',
    'active': 1,
    'group_name': 'Zone Sud',
    'reservoir_pressure': null,
  },
];

/// Types d'analyse de démarrage.
const _seedTypes = [
  {'id': 't_bsw', 'label': 'BSW', 'unit': '%', 'min_value': 0.0, 'max_value': 2.0, 'frequency': 'daily'},
  {
    'id': 't_salinity',
    'label': 'Salinité',
    'unit': 'mg/L',
    'min_value': 0.0,
    'max_value': 5000.0,
    'frequency': 'daily',
  },
  {
    'id': 't_density',
    'label': 'Densité',
    'unit': 'kg/m³',
    'min_value': 780.0,
    'max_value': 860.0,
    'frequency': 'weekly',
  },
  {'id': 't_h2s', 'label': 'H2S', 'unit': 'ppm', 'min_value': 0.0, 'max_value': 10.0, 'frequency': 'daily'},
  {'id': 't_pressure', 'label': 'Pression', 'unit': 'bar', 'min_value': 20.0, 'max_value': 120.0, 'frequency': 'daily'},
  {
    'id': 't_temperature',
    'label': 'Température',
    'unit': '°C',
    'min_value': 15.0,
    'max_value': 90.0,
    'frequency': 'daily',
  },
  ..._productionFlowTypes,
  _bottomHolePressureType,
];

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
  {
    'id': 't_oil_flow',
    'label': 'Débit huile',
    'unit': 'm³/j',
    'min_value': 0.0,
    'max_value': 100000.0,
    'frequency': 'daily',
  },
  {
    'id': 't_gas_flow',
    'label': 'Débit gaz',
    'unit': 'Sm³/j',
    'min_value': 0.0,
    'max_value': 1000000.0,
    'frequency': 'daily',
  },
  {
    'id': 't_water_flow',
    'label': 'Débit eau',
    'unit': 'm³/j',
    'min_value': 0.0,
    'max_value': 100000.0,
    'frequency': 'daily',
  },
];
