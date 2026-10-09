import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Base locale SQLite (sqflite) : seule source de données tant qu'aucun
/// backend partagé n'est branché (voir README, section "Mode local actuel").
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'suivi_puits.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          create table wells (
            id text primary key,
            code text not null,
            name text not null,
            active integer not null default 1,
            group_name text not null default ''
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
      },
    );
  }

  /// Puits et types d'analyse de démarrage, pour ne pas ouvrir l'app sur un
  /// écran totalement vide. Aucun enregistrement d'analyse n'est pré-rempli :
  /// l'historique reflète uniquement les vraies saisies.
  Future<void> _seed(Database db) async {
    const wells = [
      {'id': 'w1', 'code': 'NWR-12', 'name': 'Nawara 12', 'active': 1, 'group_name': 'Zone Nord'},
      {'id': 'w2', 'code': 'NWR-07', 'name': 'Nawara 07', 'active': 1, 'group_name': 'Zone Nord'},
      {'id': 'w3', 'code': 'NWR-21', 'name': 'Nawara 21', 'active': 1, 'group_name': 'Zone Sud'},
      {'id': 'w4', 'code': 'NWR-04', 'name': 'Nawara 04', 'active': 0, 'group_name': 'Zone Sud'},
      {'id': 'w5', 'code': 'NWR-15', 'name': 'Nawara 15', 'active': 1, 'group_name': 'Zone Sud'},
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
    ];
    for (final type in types) {
      await db.insert('analysis_types', type);
    }
  }
}

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
