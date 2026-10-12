// Entreprises, invitations, rôles, Cloud Functions et synchronisation, via
// les émulateurs Firebase locaux (règles de firestore.rules et fonctions de
// functions/ incluses). Ignoré si les émulateurs ne tournent pas :
//   firebase emulators:start --only auth,firestore,functions --project puitstrack
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

/// Même projet, mais Cloud Functions injoignables (forfait gratuit).
final _noFunctions = FirebaseRestConfig(
  apiKey: _config.apiKey,
  projectId: _config.projectId,
  authBaseUrl: _config.authBaseUrl,
  tokenBaseUrl: _config.tokenBaseUrl,
  firestoreBaseUrl: _config.firestoreBaseUrl,
  functionsBaseUrl: 'http://127.0.0.1:5999/absent',
);

Future<bool> _up(String url) async {
  try {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));
    return r.statusCode < 500;
  } catch (_) {
    return false;
  }
}

class _Device {
  final Database db;
  final SyncEngine engine;
  late AuthSession session;
  late String scope;
  UserRole role = UserRole.admin;

  _Device(this.db)
    : engine = SyncEngine(
        openDatabase: () async => db,
        firestore: FirestoreRest(_config),
        config: _config,
        store: MemorySyncStore(),
      );

  Future<SyncReport> sync() => engine.sync(
    session,
    scope: scope,
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

Matcher _invite(String reason) => throwsA(isA<InviteException>().having((e) => e.reason, 'reason', reason));

void main() {
  late Directory dir;
  late bool running;
  late bool functionsRunning;
  final team = TeamService(_config);
  final teamWithoutFunctions = TeamService(_noFunctions);
  final auth = FirebaseAuthRest(_config);
  final firestore = FirestoreRest(_config);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  late AuthSession adminA;
  late Company alpha;
  late AuthSession operatorA;

  setUpAll(() async {
    sqfliteFfiInit();
    running = await _up('http://127.0.0.1:9099/') && await _up('http://127.0.0.1:8080/');
    functionsRunning = running && await _up('http://127.0.0.1:5001/');
    dir = await Directory.systemTemp.createTemp('puitstrack_sync_');
    if (running) {
      // Repart d'un Firestore vide.
      await http.delete(Uri.parse('http://127.0.0.1:8080/emulator/v1/projects/puitstrack/databases/(default)/documents'));
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

  Future<List<Map<String, Object?>>> list(AuthSession session, String parent, String collection) =>
      firestore.runQuery(session.idToken, parent, {
        'from': [
          {'collectionId': collection},
        ],
      });

  Map<String, Object?> write(String path, Map<String, Object?> fields) => {
    'update': {'name': _config.documentName(path), 'fields': encodeFields(fields)},
  };

  test('nouvelle entreprise : le fondateur en est l\'administrateur, une seule par compte', () async {
    if (!running) return markTestSkipped('Émulateurs Firebase non démarrés');
    adminA = await auth.signUp('admin.a$stamp@example.com', 'secret123');
    expect(await team.probeRules(adminA), RulesStatus.ok, reason: 'règles publiées (émulateur)');
    expect(await team.companyIdOf(adminA), isNull);
    final (company, member) = await team.createCompany(adminA, companyName: 'Alpha', name: 'Admin A');
    alpha = company;
    expect(member.role, UserRole.admin);
    expect(await team.companyIdOf(adminA), alpha.id);
    expect((await team.company(adminA, alpha.id))!.name, 'Alpha');
    await expectLater(
      team.createCompany(adminA, companyName: 'Alpha bis', name: 'A'),
      throwsA(isA<AlreadyInCompanyException>()),
    );

    // Un autre compte ne peut ni s'ajouter à l'entreprise, ni la lire.
    final intruder = await auth.signUp('intrus$stamp@example.com', 'secret123');
    await expectLater(
      firestore.commit(intruder.idToken, [
        write('${alpha.path}/members/${intruder.uid}', {
          'email': intruder.email,
          'nom': 'X',
          'role': 'admin',
          'actif': true,
        }),
      ]),
      _denied(),
    );
    await expectLater(team.company(intruder, alpha.id), _denied());
    await expectLater(list(intruder, alpha.path, 'wells'), _denied());
    // ... ni se rattacher à l'entreprise.
    await expectLater(
      firestore.commit(intruder.idToken, [
        write('accounts/${intruder.uid}', {'companyId': alpha.id}),
      ]),
      _denied(),
    );
  });

  test('invitations : code, rôle, usage unique, expiration, e-mail imposé', () async {
    if (!running) return markTestSkipped('Émulateurs Firebase non démarrés');
    final invite = await team.createInvite(adminA, alpha, adminName: 'Admin A', role: UserRole.operator);
    final preview = await team.previewInvite(invite.displayCode.toLowerCase());
    expect(preview!.companyName, 'Alpha', reason: 'aperçu sans compte, code insensible à la casse');
    expect(preview.role, UserRole.operator);

    operatorA = await auth.signUp('op.a$stamp@example.com', 'secret123');
    final (_, member) = await team.joinWithInvite(operatorA, invite.code, name: 'Opérateur A');
    expect(member.role, UserRole.operator);
    expect(await team.companyIdOf(operatorA), alpha.id);

    // Usage unique.
    final late = await auth.signUp('late$stamp@example.com', 'secret123');
    await expectLater(team.joinWithInvite(late, invite.code, name: 'Trop tard'), _invite('used'));
    await expectLater(
      firestore.commit(late.idToken, [
        write('${alpha.path}/members/${late.uid}', {
          'email': late.email,
          'nom': 'X',
          'role': 'operateur',
          'actif': true,
          'invite': invite.code,
        }),
      ]),
      _denied(),
      reason: 'les règles refusent aussi un code déjà utilisé',
    );

    // E-mail imposé.
    final forBob = await team.createInvite(
      adminA,
      alpha,
      adminName: 'Admin A',
      role: UserRole.engineer,
      email: 'bob$stamp@example.com',
    );
    await expectLater(team.joinWithInvite(late, forBob.code, name: 'Pas Bob'), _invite('email'));
    final bob = await auth.signUp('bob$stamp@example.com', 'secret123');
    expect((await team.joinWithInvite(bob, forBob.code, name: 'Bob')).$2.role, UserRole.engineer);

    // Expiration.
    final expired = await team.createInvite(
      adminA,
      alpha,
      adminName: 'Admin A',
      role: UserRole.admin,
      validity: const Duration(seconds: -1),
    );
    await expectLater(team.joinWithInvite(late, expired.code, name: 'X'), _invite('expired'));
    await expectLater(
      firestore.commit(late.idToken, [
        write('${alpha.path}/members/${late.uid}', {
          'email': late.email,
          'nom': 'X',
          'role': 'admin',
          'actif': true,
          'invite': expired.code,
        }),
        {
          'update': {
            'name': _config.documentName('${alpha.path}/invites/${expired.code}'),
            'fields': encodeFields({'used': true, 'usedBy': late.uid}),
          },
          'updateMask': {
            'fieldPaths': ['used', 'usedBy'],
          },
        },
      ]),
      _denied(),
      reason: 'les règles refusent un code expiré',
    );
    await expectLater(team.previewInvite('ZZZZ-ZZZZ'), completion(isNull));

    // L'administrateur voit les invitations restantes et peut les supprimer.
    final invites = await team.listInvites(adminA, alpha.id);
    expect(invites.where((i) => !i.used).map((i) => i.code), contains(expired.code));
    await team.deleteInvite(adminA, alpha.id, expired.code);
    expect(await team.previewInvite(expired.code), isNull);
    await expectLater(team.listInvites(operatorA, alpha.id), _denied());
  });

  test('isolation entre entreprises', () async {
    if (!running) return markTestSkipped('Émulateurs Firebase non démarrés');
    final adminB = await auth.signUp('admin.b$stamp@example.com', 'secret123');
    final (beta, _) = await team.createCompany(adminB, companyName: 'Beta', name: 'Admin B');
    // Données d'Alpha.
    await firestore.commit(adminA.idToken, [
      write('${alpha.path}/wells/wa', {'code': 'A-1', 'name': 'Puits Alpha', 'updated_at': 1}),
    ]);
    await expectLater(list(adminB, alpha.path, 'wells'), _denied());
    await expectLater(team.listMembers(adminB, alpha.id), _denied());
    await expectLater(team.createInvite(adminB, alpha, adminName: 'B', role: UserRole.admin), _denied());
    await expectLater(
      firestore.commit(adminB.idToken, [
        write('${alpha.path}/wells/wb', {'code': 'B'}),
      ]),
      _denied(),
    );
    expect(await list(adminB, beta.path, 'wells'), isEmpty);
    expect((await list(adminA, alpha.path, 'wells')).length, 1);
  });

  test('rôles et désactivation, sans Cloud Functions', () async {
    if (!running) return markTestSkipped('Émulateurs Firebase non démarrés');
    expect(await teamWithoutFunctions.functionsAvailable(adminA), isFalse);
    // Compte créé par l'administrateur (sans le déconnecter).
    final reader = await teamWithoutFunctions.createMember(
      adminA,
      alpha.id,
      adminName: 'Admin A',
      email: 'reader$stamp@example.com',
      password: 'temp1234',
      name: 'Lecteur',
      role: UserRole.reader,
    );
    final readerSession = await auth.signIn('reader$stamp@example.com', 'temp1234');
    expect(await team.companyIdOf(readerSession), alpha.id);
    expect(await list(readerSession, alpha.path, 'wells'), isNotEmpty);
    await expectLater(
      firestore.commit(readerSession.idToken, [
        write('${alpha.path}/analysis_records/r_x', {'value': 1}),
      ]),
      _denied(),
    );
    // Opérateur : analyses oui, puits non, membres non.
    await firestore.commit(operatorA.idToken, [
      write('${alpha.path}/analysis_records/r_op', {'value': 0.4}),
    ]);
    await expectLater(
      firestore.commit(operatorA.idToken, [
        write('${alpha.path}/wells/w9', {'code': 'X'}),
      ]),
      _denied(),
    );
    await expectLater(team.listMembers(operatorA, alpha.id), _denied());
    // Il change son nom, pas son rôle.
    await team.renameSelf(operatorA, alpha.id, 'Opérateur 1');
    expect((await team.member(operatorA, alpha.id))!.name, 'Opérateur 1');

    // Désactivation (fiche) : plus aucun accès aux données.
    await teamWithoutFunctions.updateMember(
      adminA,
      alpha.id,
      adminName: 'Admin A',
      member: reader.copyWith(active: false),
      previousActive: true,
    );
    await expectLater(list(readerSession, alpha.path, 'wells'), _denied());
    // Retrait : fiche et rattachement supprimés.
    await teamWithoutFunctions.removeMember(adminA, alpha.id, adminName: 'Admin A', member: reader);
    expect(await team.companyIdOf(readerSession), isNull);
  });

  test('Cloud Functions : création, désactivation réelle, mot de passe, suppression', () async {
    if (!functionsRunning) return markTestSkipped('Émulateur des Cloud Functions non démarré');
    expect(await team.functionsAvailable(adminA), isTrue);
    final member = await team.createMember(
      adminA,
      alpha.id,
      adminName: 'Admin A',
      email: 'fn$stamp@example.com',
      password: 'temp1234',
      name: 'Par fonction',
      role: UserRole.engineer,
    );
    final session = await auth.signIn('fn$stamp@example.com', 'temp1234');
    expect((await team.member(session, alpha.id))!.role, UserRole.engineer);

    // Désactivation : la connexion elle-même est bloquée.
    await team.updateMember(
      adminA,
      alpha.id,
      adminName: 'Admin A',
      member: member.copyWith(active: false),
      previousActive: true,
    );
    await expectLater(
      auth.signIn('fn$stamp@example.com', 'temp1234'),
      throwsA(isA<SyncAuthException>().having((e) => e.code, 'code', 'USER_DISABLED')),
    );
    await team.updateMember(adminA, alpha.id, adminName: 'Admin A', member: member, previousActive: false);

    // Nouveau mot de passe choisi par l'administrateur.
    await team.setMemberPassword(adminA, alpha.id, uid: member.uid, password: 'nouveau123');
    await auth.signIn('fn$stamp@example.com', 'nouveau123');

    // Un administrateur d'une autre entreprise ne peut rien sur ce compte.
    final adminC = await auth.signUp('admin.c$stamp@example.com', 'secret123');
    final (gamma, _) = await team.createCompany(adminC, companyName: 'Gamma', name: 'Admin C');
    await expectLater(
      team.functions.call(adminC.idToken, 'setMemberPassword', {
        'companyId': gamma.id,
        'uid': member.uid,
        'password': 'pirate123',
      }),
      throwsA(isA<FunctionCallException>().having((e) => e.status, 'status', 'PERMISSION_DENIED')),
    );
    await expectLater(
      team.functions.call(operatorA.idToken, 'deleteMember', {'companyId': alpha.id, 'uid': member.uid}),
      throwsA(isA<FunctionCallException>().having((e) => e.status, 'status', 'PERMISSION_DENIED')),
    );

    // Suppression : le compte n'existe plus.
    await team.removeMember(adminA, alpha.id, adminName: 'Admin A', member: member);
    await expectLater(auth.signIn('fn$stamp@example.com', 'nouveau123'), throwsA(isA<SyncAuthException>()));
  });

  test('deux appareils de l\'entreprise : envoi, réception, suppression, conflit, repère', () async {
    if (!running) return markTestSkipped('Émulateurs Firebase non démarrés');
    final a = await device('a')
      ..session = adminA
      ..scope = alpha.path;
    await a.upsert('wells', {
      'id': 'w1', 'code': 'PN-01', 'name': 'Puits Nord 1 renommé', 'active': 1, 'group_name': 'Zone Nord',
      'well_type': 'oil_producer', 'status': 'producing', 'latitude': 32.5, 'longitude': 9.1,
    });
    await a.upsert('analysis_records', {
      'id': 'r1', 'well_id': 'w1', 'type_id': 't_oil_flow', 'value': 123.5, 'service_key': 'serviceProduction',
      'operator_name': 'Ahmed', 'recorded_at': '2026-10-09T08:00:00.000',
    });
    await a.upsert('plant_circuits', {
      'id': 'water_treatment', 'label_key': 'Traitement eau (modifié)', 'color': 0xFF00897B, 'icon': 'water',
      'default_profile': 'water', 'sort_order': 5,
    });
    await a.engine.prepareFirstSync(a.scope, a.session.uid);
    await a.sync();
    expect((await a.row('analysis_records', 'r1'))!['dirty'], 0, reason: 'envoyée');
    expect((await a.row('plant_circuits', 'water_treatment'))!['dirty'], 0, reason: 'circuits synchronisés');

    final b = await device('b')
      ..session = await auth.signIn('admin.a$stamp@example.com', 'secret123')
      ..scope = alpha.path;
    await b.engine.prepareFirstSync(b.scope, b.session.uid);
    await b.sync();
    expect((await b.row('wells', 'w1'))!['name'], 'Puits Nord 1 renommé', reason: 'reçu de A');
    expect((await b.row('analysis_records', 'r1'))!['value'], 123.5);
    expect((await b.row('plant_circuits', 'water_treatment'))!['label_key'], 'Traitement eau (modifié)');

    // Rien de nouveau : une seule lecture (le repère), aucune ligne reçue.
    expect((await b.sync()).pulled, 0);

    await b.delete('analysis_records', 'r1');
    await b.upsert('interventions', {
      'id': 'i1', 'well_id': 'w1', 'intervention_date': '2026-10-01T00:00:00.000', 'type_key': 'interventionTypeWorkover',
      'cost': 45000.0, 'currency': 'TND', 'result_key': 'interventionResultSuccess', 'description': null,
      'operator_name': 'Ahmed', 'created_at': '2026-10-01T10:00:00.000',
    });
    await b.sync();
    await a.sync();
    expect(await a.row('analysis_records', 'r1'), isNull, reason: 'suppression propagée');
    expect((await a.row('interventions', 'i1'))!['cost'], 45000.0);

    await a.upsert('wells', {'id': 'w2', 'code': 'PN-02', 'name': 'Version A', 'active': 1, 'group_name': 'Zone Nord'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await b.upsert('wells', {'id': 'w2', 'code': 'PN-02', 'name': 'Version B', 'active': 1, 'group_name': 'Zone Nord'});
    await b.sync();
    await a.sync();
    await b.sync();
    expect((await a.row('wells', 'w2'))!['name'], 'Version B');
    expect((await b.row('wells', 'w2'))!['name'], 'Version B');

    // Opérateur : ses analyses partent, ses changements de puits sont abandonnés.
    final op = await device('op')
      ..session = operatorA
      ..scope = alpha.path
      ..role = UserRole.operator;
    await op.upsert('analysis_records', {
      'id': 'r_op2', 'well_id': 'w1', 'type_id': 't_bsw', 'value': 0.5, 'service_key': 'serviceLaboratoire',
      'operator_name': 'Opérateur 1', 'recorded_at': '2026-10-10T08:00:00.000',
    });
    await op.upsert('wells', {'id': 'w1', 'code': 'PN-01', 'name': 'Modifié par opérateur', 'active': 1, 'group_name': ''});
    await op.sync();
    expect((await op.row('analysis_records', 'r_op2'))!['dirty'], 0);
    expect((await op.row('wells', 'w1'))!['name'], 'Puits Nord 1 renommé', reason: 'version de l\'entreprise');

    // Journal d'audit : lisible par l'administrateur seulement.
    final audit = await team.audit(adminA, alpha.id);
    expect(audit.any((e) => e.docId == 'r_op2' && e.email == operatorA.email), isTrue);
    expect(audit.any((e) => e.action == 'invite_use'), isTrue);
    await expectLater(team.audit(operatorA, alpha.id), _denied());
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
