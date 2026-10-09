// Équipe et synchronisation via les émulateurs Firebase locaux (règles de
// firestore.rules incluses). Ignoré si les émulateurs ne tournent pas :
//   firebase emulators:start --only auth,firestore --project puitstrack
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:puitstrack/core/data/local_database.dart';
import 'package:puitstrack/core/models/user_role.dart';
import 'package:puitstrack/core/sync/firebase_config.dart';
import 'package:puitstrack/core/sync/firebase_rest.dart';
import 'package:puitstrack/core/sync/firestore_value.dart';
import 'package:puitstrack/core/sync/sync_engine.dart';
import 'package:puitstrack/core/team/team_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _config = FirebaseRestConfig.emulator();

Future<bool> _emulatorsRunning() async {
  try {
    final auth = await http.get(Uri.parse('http://127.0.0.1:9099/')).timeout(const Duration(seconds: 2));
    final firestore = await http.get(Uri.parse('http://127.0.0.1:8080/')).timeout(const Duration(seconds: 2));
    return auth.statusCode < 500 && firestore.statusCode < 500;
  } catch (_) {
    return false;
  }
}

class _Device {
  final Database db;
  final SyncEngine engine;
  late AuthSession session;
  UserRole role = UserRole.admin;

  _Device(this.db)
    : engine = SyncEngine(
        openDatabase: () async => db,
        firestore: FirestoreRest(_config),
        config: _config,
        store: MemorySyncStore(),
      );

  Future<void> sync() => engine.sync(
    session,
    writable: role.writableTables,
    actor: AuditActor(uid: session.uid, email: session.email, name: 'Test'),
  );

  Future<Map<String, Object?>?> row(String table, String id) async =>
      (await db.query(table, where: 'id = ?', whereArgs: [id])).firstOrNull;

  /// Même écriture que l'app (WellsController) : colonnes de suivi.
  Future<void> upsert(String table, Map<String, Object?> data) =>
      db.insert(table, LocalDatabase.stamp(data), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> delete(String table, String id) async {
    await LocalDatabase.recordDeletion(db, table, id);
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
}

Matcher _denied() => throwsA(isA<SyncServerException>().having((e) => e.statusCode, 'statusCode', 403));

void main() {
  late Directory dir;
  late bool running;
  final team = TeamService(_config);
  final auth = FirebaseAuthRest(_config);
  final firestore = FirestoreRest(_config);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  late AuthSession admin;

  setUpAll(() async {
    sqfliteFfiInit();
    running = await _emulatorsRunning();
    dir = await Directory.systemTemp.createTemp('puitstrack_sync_');
    if (running) {
      // Repart d'un Firestore vide (aucun administrateur).
      await http.delete(
        Uri.parse('http://127.0.0.1:8080/emulator/v1/projects/puitstrack/databases/(default)/documents'),
      );
    }
  });

  final opened = <Database>[];

  tearDownAll(() async {
    for (final db in opened) {
      await db.close();
    }
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<_Device> device(String name) async {
    final db = await LocalDatabase.openAt('${dir.path}/$name.db', factory: databaseFactoryFfi);
    opened.add(db);
    return _Device(db);
  }

  Future<List<Map<String, Object?>>> list(AuthSession session, String collection) =>
      firestore.runQuery(session.idToken, '', {
        'from': [
          {'collectionId': collection},
        ],
      });

  test('installation : premier compte administrateur, une seule fois', () async {
    if (!running) return markTestSkipped('Émulateurs Firebase non démarrés');
    admin = await auth.signUp('admin$stamp@example.com', 'secret123');
    expect(await team.probeRules(admin), RulesStatus.ok, reason: 'règles publiées (émulateur)');
    expect(await team.isSetupDone(admin), isFalse);
    final member = await team.bootstrapAdmin(admin, name: 'Admin');
    expect(member.role, UserRole.admin);
    expect(await team.isSetupDone(admin), isTrue);
    expect((await team.member(admin))!.active, isTrue);

    // Un second compte ne peut pas devenir administrateur.
    final intruder = await auth.signUp('intruder$stamp@example.com', 'secret123');
    await expectLater(team.bootstrapAdmin(intruder, name: 'Intrus'), throwsA(isA<SyncServerException>()));
    // ... ni se créer une fiche active ou s'attribuer un rôle.
    await expectLater(
      firestore.commit(intruder.idToken, [
        {
          'update': {
            'name': _config.documentName('users/${intruder.uid}'),
            'fields': encodeFields({
              'email': intruder.email,
              'nom': 'X',
              'role': 'admin',
              'actif': true,
              'demande': false,
            }),
          },
        },
      ]),
      _denied(),
    );
    // Sans fiche active : aucune donnée lisible.
    await expectLater(list(intruder, 'wells'), _denied());
  });

  test('demande d\'accès, validation, rôles et désactivation', () async {
    if (!running) return markTestSkipped('Émulateurs Firebase non démarrés');
    // Demande d'accès (lecteur inactif) puis validation en opérateur.
    final op = await auth.signUp('op$stamp@example.com', 'secret123');
    final request = await team.requestAccess(op, name: 'Opérateur');
    expect(request.pending, isTrue);
    expect(request.active, isFalse);
    await expectLater(list(op, 'wells'), _denied());
    // Le demandeur ne peut pas s'activer lui-même.
    await expectLater(
      team.updateMember(
        op,
        adminName: 'X',
        member: request.copyWith(active: true, role: UserRole.admin),
      ),
      _denied(),
    );

    final members = await team.listMembers(admin);
    expect(members.map((m) => m.email), contains('op$stamp@example.com'));
    await team.updateMember(
      admin,
      adminName: 'Admin',
      member: request.copyWith(active: true, pending: false, role: UserRole.operator),
    );
    expect((await team.member(op))!.role, UserRole.operator);

    // Un non-administrateur ne liste pas l'équipe.
    await expectLater(team.listMembers(op), _denied());
    // Il peut changer son nom, pas son rôle.
    await team.renameSelf(op, 'Opérateur 1');
    expect((await team.member(op))!.name, 'Opérateur 1');

    // Compte créé par l'administrateur (sans le déconnecter : la session
    // admin reste valable).
    final reader = await team.createMember(
      admin,
      adminName: 'Admin',
      email: 'reader$stamp@example.com',
      password: 'temp1234',
      name: 'Lecteur',
      role: UserRole.reader,
    );
    expect(reader.active, isTrue);
    expect(await team.listMembers(admin), hasLength(greaterThanOrEqualTo(3)));
    final readerSession = await auth.signIn('reader$stamp@example.com', 'temp1234');
    expect(await list(readerSession, 'wells'), isA<List<Object?>>());

    // Opérateur : analyses oui, puits non.
    final opDevice = await device('op');
    opDevice
      ..session = op
      ..role = UserRole.operator;
    await opDevice.upsert('analysis_records', {
      'id': 'r_op',
      'well_id': 'w1',
      'type_id': 't_bsw',
      'value': 0.4,
      'service_key': 'serviceLaboratoire',
      'operator_name': 'Opérateur 1',
      'recorded_at': '2026-10-09T08:00:00.000',
    });
    await opDevice.upsert('wells', {
      'id': 'w1',
      'code': 'PN-01',
      'name': 'Renommé par opérateur',
      'active': 1,
      'group_name': '',
    });
    await opDevice.sync();
    expect((await opDevice.row('analysis_records', 'r_op'))!['dirty'], 0, reason: 'analyse envoyée');
    expect((await opDevice.row('wells', 'w1'))!['dirty'], 0, reason: 'modification non autorisée abandonnée');
    // Écriture directe d'un puits refusée par les règles.
    await expectLater(
      firestore.commit(op.idToken, [
        {
          'update': {
            'name': _config.documentName('wells/w9'),
            'fields': encodeFields({'code': 'X'}),
          },
        },
      ]),
      _denied(),
    );
    // Lecteur : aucune écriture.
    await expectLater(
      firestore.commit(readerSession.idToken, [
        {
          'update': {
            'name': _config.documentName('analysis_records/r_x'),
            'fields': encodeFields({'value': 1}),
          },
        },
      ]),
      _denied(),
    );

    // Journal d'audit : l'envoi de l'opérateur y figure, lisible par l'admin seul.
    final audit = await team.audit(admin);
    expect(audit.any((e) => e.docId == 'r_op' && e.email == op.email && e.action == 'save'), isTrue);
    expect(audit.any((e) => e.action == 'user_create' && e.label.contains('reader$stamp')), isTrue);
    await expectLater(team.audit(op), _denied());

    // Désactivation : plus aucun accès.
    await team.updateMember(
      admin,
      adminName: 'Admin',
      member: (await team.member(admin, op.uid))!.copyWith(active: false),
    );
    await expectLater(list(op, 'analysis_records'), _denied());
  });

  test('deux appareils de l\'équipe : envoi, réception, suppression, conflit', () async {
    if (!running) return markTestSkipped('Émulateurs Firebase non démarrés');

    // --- Appareil A (administrateur, téléphone avec des données) ---
    final a = await device('a');
    a.session = admin;
    await a.upsert('wells', {
      'id': 'w1',
      'code': 'PN-01',
      'name': 'Puits Nord 1 renommé',
      'active': 1,
      'group_name': 'Zone Nord',
      'well_type': 'oil_producer',
      'status': 'producing',
      'latitude': 32.5,
      'longitude': 9.1,
    });
    await a.upsert('analysis_records', {
      'id': 'r1',
      'well_id': 'w1',
      'type_id': 't_oil_flow',
      'value': 123.5,
      'service_key': 'serviceProduction',
      'operator_name': 'Ahmed',
      'recorded_at': '2026-10-09T08:00:00.000',
    });
    await a.upsert('app_config', {'id': 'missing_deadline', 'value': '09:30'});
    await a.engine.prepareFirstSync(a.session.uid);
    await a.sync();
    expect((await a.row('analysis_records', 'r1'))!['dirty'], 0, reason: 'envoyée');

    // --- Appareil B (navigateur neuf, même compte) ---
    final b = await device('b');
    b.session = await auth.signIn('admin$stamp@example.com', 'secret123');
    expect((await b.row('wells', 'w1'))!['name'], 'Puits Nord 1');
    await b.engine.prepareFirstSync(b.session.uid);
    await b.sync();
    final w1 = (await b.row('wells', 'w1'))!;
    expect(w1['name'], 'Puits Nord 1 renommé', reason: 'reçu de A');
    expect(w1['well_type'], 'oil_producer');
    expect(w1['latitude'], 32.5);
    expect((await b.row('analysis_records', 'r1'))!['value'], 123.5);
    expect((await b.row('analysis_records', 'r_op'))!['value'], 0.4, reason: 'saisie de l\'opérateur reçue');
    expect((await b.row('app_config', 'missing_deadline'))!['value'], '09:30');
    await a.sync();
    expect((await a.row('wells', 'w1'))!['name'], 'Puits Nord 1 renommé');

    // --- Suppression sur B + nouvelle intervention, reçues par A ---
    await b.delete('analysis_records', 'r1');
    await b.upsert('interventions', {
      'id': 'i1',
      'well_id': 'w1',
      'intervention_date': '2026-10-01T00:00:00.000',
      'type_key': 'interventionTypeWorkover',
      'cost': 45000.0,
      'currency': 'TND',
      'result_key': 'interventionResultSuccess',
      'description': null,
      'operator_name': 'Ahmed',
      'created_at': '2026-10-01T10:00:00.000',
    });
    await b.sync();
    await a.sync();
    expect(await a.row('analysis_records', 'r1'), isNull, reason: 'suppression propagée');
    expect((await a.row('interventions', 'i1'))!['cost'], 45000.0);

    // --- Conflit : même puits modifié sur les deux, le plus récent gagne ---
    await a.upsert('wells', {'id': 'w2', 'code': 'PN-02', 'name': 'Version A', 'active': 1, 'group_name': 'Zone Nord'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await b.upsert('wells', {'id': 'w2', 'code': 'PN-02', 'name': 'Version B', 'active': 1, 'group_name': 'Zone Nord'});
    await b.sync();
    await a.sync();
    await b.sync();
    expect((await a.row('wells', 'w2'))!['name'], 'Version B');
    expect((await b.row('wells', 'w2'))!['name'], 'Version B');
    expect((await a.row('wells', 'w2'))!['dirty'], 0);
  });

  test('compte : erreurs explicites', () async {
    if (!running) return markTestSkipped('Émulateurs Firebase non démarrés');
    final email = 'dup$stamp@example.com';
    await auth.signUp(email, 'secret123');
    await expectLater(
      auth.signUp(email, 'secret123'),
      throwsA(isA<SyncAuthException>().having((e) => e.code, 'code', 'EMAIL_EXISTS')),
    );
    await expectLater(auth.signIn(email, 'mauvais'), throwsA(isA<SyncAuthException>()));
  });
}
