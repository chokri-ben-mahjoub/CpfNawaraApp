// Administration : configuration Firebase collée / QR, règles de sécurité,
// rôles, unités SI/API, paramètres partagés et import CSV/Excel.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/app_info.dart';
import 'package:puitstrack/core/config/shared_config.dart';
import 'package:puitstrack/core/data/wells_repository.dart';
import 'package:puitstrack/core/export/excel_exporter.dart';
import 'package:puitstrack/core/export/export_table.dart';
import 'package:puitstrack/core/import/analysis_importer.dart';
import 'package:puitstrack/core/models/analysis_record.dart';
import 'package:puitstrack/core/models/analysis_type.dart';
import 'package:puitstrack/core/models/user_role.dart';
import 'package:puitstrack/core/models/well.dart';
import 'package:puitstrack/core/plant/plant_catalog.dart';
import 'package:puitstrack/core/plant/plant_repository.dart';
import 'package:puitstrack/core/sync/firebase_config.dart';
import 'package:puitstrack/core/team/firestore_rules.dart';
import 'package:puitstrack/core/team/team_service.dart';
import 'package:puitstrack/core/data/local_database.dart';
import 'package:puitstrack/features/setup/presentation/widgets/team_account_form.dart';
import 'package:puitstrack/core/units/unit_system.dart';

WellsState _wells() => WellsState(
  wells: const [
    Well(id: 'w1', code: 'PN-01', name: 'Puits Nord 1', active: true, group: 'Zone Nord'),
    Well(id: 'w2', code: 'PN-02', name: 'Puits Nord 2', active: true, group: 'Zone Nord'),
  ],
  analysisTypes: const [
    AnalysisType(id: 't_bsw', label: 'BSW', unit: '%', min: 0, max: 2, frequency: AnalysisFrequency.daily),
    AnalysisType(
      id: 't_salinity',
      label: 'Salinité',
      unit: 'mg/L',
      min: 0,
      max: 5000,
      frequency: AnalysisFrequency.daily,
    ),
    AnalysisType(
      id: 't_pressure',
      label: 'Pression',
      unit: 'bar',
      min: 20,
      max: 120,
      frequency: AnalysisFrequency.daily,
    ),
  ],
  records: [
    AnalysisRecord(
      id: 'r1',
      wellId: 'w1',
      typeId: 't_bsw',
      value: 0.8,
      serviceKey: 'serviceLaboratoire',
      operatorName: 'Ahmed',
      dateTime: DateTime(2026, 10, 1, 8),
    ),
  ],
);

final _circuitsById = {
  for (final row in plantSeedCircuits)
    row['id']! as String: PlantCircuit(
      id: row['id']! as String,
      labelKey: row['label_key']! as String,
      colorValue: row['color']! as int,
      iconKey: row['icon']! as String,
      defaultProfile: row['default_profile']! as String,
      sortOrder: row['sort_order']! as int,
    ),
};

PlantState _plant() => PlantState(
  points: [
    for (final row in plantSeedPoints)
      SamplePoint(
        id: row['id'] as String,
        code: row['code'] as String,
        circuit: _circuitsById[row['circuit'] as String]!,
        name: row['name'] as String,
        equipment: row['equipment'] as String,
        profile: row['profile'] as String,
      ),
  ],
  analyses: const [],
  thresholds: const {},
  circuits: _circuitsById.values.toList(),
);

AnalysisImporter _importer() => AnalysisImporter(
  wells: _wells(),
  plant: _plant(),
  locale: const Locale('fr'),
  defaultService: 'serviceLaboratoire',
  operatorName: 'Import',
);

void main() {
  tearDown(() => Units.system = UnitSystem.si);

  test('règles : la copie intégrée à l\'app est identique à firestore.rules', () {
    final file = File('firestore.rules').readAsStringSync().replaceAll('\r\n', '\n');
    expect(firestoreRules.replaceAll('\r\n', '\n'), file);
    expect(firestoreRules, contains('match /config/rules_v4'));
    expect(
      firestoreRules,
      contains("request.auth.token.email == '$platformOwnerEmail'"),
      reason: 'propriétaire identique dans app_info.dart et firestore.rules',
    );
  });

  test("règles : mêmes tables que la base locale, toutes modifiables par l'admin", () {
    final match = RegExp(
      r'function dataTables\(\) \{\s*return \[([^\]]+)\]',
      multiLine: true,
    ).firstMatch(firestoreRules)!;
    final ruleTables = RegExp("'([a-z_]+)'").allMatches(match.group(1)!).map((m) => m.group(1)).toSet();
    expect(ruleTables, LocalDatabase.dataTables.toSet(), reason: "nouvelle table : l'ajouter à firestore.rules");
    expect(UserRole.admin.writableTables, LocalDatabase.dataTables.toSet());
    for (final role in UserRole.values) {
      expect(LocalDatabase.dataTables.toSet().containsAll(role.writableTables), isTrue);
    }
  });

  group('invitations', () {
    test('code : saisie libre, affichage', () {
      expect(normalizeInviteCode(' abcd-efgh '), 'ABCDEFGH');
      expect(formatInviteCode('ABCDEFGH'), 'ABCD-EFGH');
      expect(isValidInviteCode('ABCDEFGH'), isTrue);
      expect(isValidInviteCode('ABCDEFG0'), isFalse, reason: 'pas de 0 (confondu avec O)');
      expect(isValidInviteCode('ABC'), isFalse);
    });

    test('QR code : code seul ou avec un projet personnalisé', () {
      expect(parseInviteQr('ABCD-EFGH').code, 'ABCDEFGH');
      final plain = parseInviteQr('{"app":"puitstrack","invite":"WXYZ2345"}');
      expect(plain.code, 'WXYZ2345');
      expect(plain.config, isNull);
      final custom = parseInviteQr(
        '{"app":"puitstrack","invite":"WXYZ2345","apiKey":"AIzaSyAbcdefghijklmnopqrstuvwxyz0123456","projectId":"client-x"}',
      );
      expect(custom.config!.projectId, 'client-x');
    });

    test('expiration et aperçu', () {
      final invite = Invite.fromFields('ABCDEFGH', {
        'companyId': 'c1',
        'companyName': 'Alpha',
        'role': 'operateur',
        'email': '',
        'expiresAt': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      });
      expect(invite.expired, isFalse);
      expect(invite.role, UserRole.operator);
      expect(invite.displayCode, 'ABCD-EFGH');
    });
  });

  group('configuration Firebase collée', () {
    test('objet firebaseConfig de la console (clés sans guillemets)', () {
      final config = FirebaseRestConfig.parse('''
// Import the functions you need from the SDKs you need
const firebaseConfig = {
  apiKey: "AIzaSyDPZfqckq75ugdlyyMnuZhpI8SX5uM35GE",
  authDomain: "puitstrack.firebaseapp.com",
  projectId: "puitstrack",
  storageBucket: "puitstrack.firebasestorage.app",
  messagingSenderId: "123456789012",
  appId: "1:123456789012:web:abcdef123456"
};''');
      expect(config, isNotNull);
      expect(config!.apiKey, 'AIzaSyDPZfqckq75ugdlyyMnuZhpI8SX5uM35GE');
      expect(config.projectId, 'puitstrack');
      expect(config.appId, '1:123456789012:web:abcdef123456');
      expect(config.messagingSenderId, '123456789012');
    });

    test('google-services.json', () {
      final config = FirebaseRestConfig.parse(
        jsonEncode({
          'project_info': {'project_number': '42', 'project_id': 'mon-projet-a1b2', 'storage_bucket': 'b'},
          'client': [
            {
              'client_info': {'mobilesdk_app_id': '1:42:android:ff'},
              'api_key': [
                {'current_key': 'AIzaSyAbcdefghijklmnopqrstuvwxyz0123456'},
              ],
            },
          ],
        }),
      );
      expect(config!.projectId, 'mon-projet-a1b2');
      expect(config.apiKey, 'AIzaSyAbcdefghijklmnopqrstuvwxyz0123456');
      expect(config.appId, '1:42:android:ff');
    });

    test('QR code d\'un autre appareil (aller-retour)', () {
      final parsed = FirebaseRestConfig.parse(FirebaseRestConfig.builtIn.qrPayload);
      expect(parsed, FirebaseRestConfig.builtIn);
      expect(FirebaseRestConfig.fromJson(FirebaseRestConfig.builtIn.toJson()), FirebaseRestConfig.builtIn);
    });

    test('texte quelconque refusé', () {
      expect(FirebaseRestConfig.parse('bonjour'), isNull);
      expect(FirebaseRestConfig.parse('apiKey: "court", projectId: "x"'), isNull);
    });

    test('liens console et clé masquée', () {
      const c = FirebaseRestConfig.builtIn;
      expect(c.consoleUrl('firestore/rules'), 'https://console.firebase.google.com/project/puitstrack/firestore/rules');
      expect(c.maskedApiKey, 'AIza…35GE');
    });
  });

  test('rôles : droits et clés stockées', () {
    expect(UserRole.admin.canConfigure, isTrue);
    expect(UserRole.engineer.canConfigure, isFalse);
    expect(UserRole.engineer.canManageInterventions, isTrue);
    expect(UserRole.operator.canManageInterventions, isFalse);
    expect(UserRole.operator.canEnterData, isTrue);
    expect(UserRole.reader.canEnterData, isFalse);
    expect(UserRole.operator.writableTables, {
      'analysis_records',
      'plant_analyses',
      'stock_movements',
      'well_rounds',
      'gas_bottles',
      'sample_manifest',
    });
    expect(UserRole.reader.writableTables, isEmpty);
    for (final role in UserRole.values) {
      expect(UserRoleX.fromStorageKey(role.storageKey), role);
    }
    expect(UserRoleX.fromStorageKey('user'), UserRole.operator, reason: 'ancien rôle');
    expect(UserRoleX.fromStorageKey(null), UserRole.reader);

    const member = TeamMember(
      uid: 'u1',
      email: 'a@b.c',
      name: 'A',
      role: UserRole.engineer,
      active: true,
      service: 'serviceHse',
    );
    final back = TeamMember.fromJson(jsonDecode(jsonEncode(member.toJson())) as Map<String, Object?>)!;
    expect(back.role, UserRole.engineer);
    expect(back.service, 'serviceHse');
    expect(member.fields['role'], 'ingenieur');
  });

  group('unités', () {
    test('SI : aucune conversion', () {
      expect(Units.unit('bar'), 'bar');
      expect(Units.display(10, 'bar'), 10);
    });

    test('API : psi, °F, bbl, scf, °API', () {
      Units.system = UnitSystem.api;
      expect(Units.unit('bar'), 'psi');
      expect(Units.display(1, 'bar'), closeTo(14.5038, 1e-4));
      expect(Units.display(100, '°C'), closeTo(212, 1e-9));
      expect(Units.display(1, 'm³/j'), closeTo(6.2898, 1e-4));
      expect(Units.display(1, 'Sm³/j'), closeTo(35.3147, 1e-4));
      expect(Units.display(999.016, 'kg/m³'), closeTo(10, 1e-9), reason: 'eau = 10 °API');
      expect(Units.unit('%'), '%');
      // Aller-retour sans dérive.
      expect(Units.toSi(Units.display(20, 'bar'), 'bar'), 20);
      expect(Units.toSi(Units.display(850, 'kg/m³'), 'kg/m³'), 850);
      // Seuils : masse volumique min/max → °API max/min.
      final (min, max) = Units.range(780, 860, 'kg/m³');
      expect(min, lessThan(max));
      expect(min, closeTo(32.87, 0.01));
      expect(max, closeTo(49.73, 0.01));
      final (smin, smax) = Units.rangeToSi(min, max, 'kg/m³');
      expect(smin, closeTo(780, 1e-6));
      expect(smax, closeTo(860, 1e-6));
      expect(Units.siUnitFor('psi'), 'bar');
    });

    test('paramètre de l\'usine : masse volumique de l\'eau jamais convertie', () {
      Units.system = UnitSystem.api;
      final water = plantParamByKey('density', profile: 'water')!;
      expect(water.displayed().unit, 'kg/m³');
      final condensate = plantParamByKey('density', profile: 'condensate')!;
      expect(condensate.displayed().unit, '°API');
      final dew = plantParamByKey('hc_dew_point', profile: 'gas_export')!.displayed();
      expect(dew.unit, '°F');
      expect(dew.siUnit, '°C');
      expect(dew.toDisplay(0), closeTo(32, 1e-9));
    });
  });

  test('paramètres partagés : heure limite', () {
    expect(SharedConfig.empty.missingDeadline, defaultMissingDeadline);
    const config = SharedConfig({missingDeadlineKey: '09:30'});
    expect(config.missingDeadline, const TimeOfDay(hour: 9, minute: 30));
    expect(config.isPastDeadline(DateTime(2026, 10, 9, 9, 29)), isFalse);
    expect(config.isPastDeadline(DateTime(2026, 10, 9, 9, 30)), isTrue);
    expect(const SharedConfig({missingDeadlineKey: 'n/a'}).missingDeadline, defaultMissingDeadline);
  });

  test('point de prélèvement : paramètres choisis', () {
    const point = SamplePoint(
      id: 'p',
      code: 'X1',
      circuit: PlantCircuit(
        id: 'water',
        labelKey: 'plantCircuitWater',
        colorValue: 0xFF1E88E5,
        iconKey: 'water_drop',
        defaultProfile: 'water',
      ),
      name: 'Test',
      equipment: '',
      profile: 'water',
      paramKeys: ['ph', 'h2s', 'inconnu'],
    );
    expect(point.params.map((p) => p.key), ['ph', 'h2s']);
    expect(plantParamCatalog.map((p) => p.key).toSet(), containsAll(['ph', 'density', 'bsw', 'salinity', 'h2s']));
  });

  group('import', () {
    test('lecture : dates, nombres, en-têtes', () {
      expect(parseImportDate('2026-10-09'), DateTime(2026, 10, 9));
      expect(parseImportDate('09/10/2026 08:30'), DateTime(2026, 10, 9, 8, 30));
      expect(parseImportDate('45939'), DateTime(2025, 10, 9));
      expect(parseImportDate('demain'), isNull);
      expect(parseImportNumber('0,8'), 0.8);
      expect(parseImportNumber('1 234,5'), 1234.5);
      expect(parseImportNumber('1,234.5'), 1234.5);
      expect(normalizeHeader('Densité (kg/m³)'), 'densite');
      expect(normalizeHeader("Type d'analyse"), 'typedanalyse');
    });

    test('CSV format long (export de l\'app) : doublon et erreurs signalés', () {
      final table = readCsv('''
Date;Puits;Type d'analyse;Valeur;Unité;Service;Opérateur;Commentaire
01/10/2026 08:00;Puits Nord 1 (PN-01);BSW;0,8;%;Laboratoire;Ahmed;
02/10/2026 08:00;PN-01;BSW;0,9;%;Laboratoire;Ahmed;"note; avec point-virgule"
02/10/2026;PN-02;Salinité;4200;mg/L;Production;;
03/10/2026;PN-99;BSW;1;%;;;
pas une date;PN-01;BSW;1;%;;;
03/10/2026;PN-01;Inconnu;1;%;;;
''')!;
      final plan = _importer().analyze([table]);
      expect(plan.kinds, [ImportKind.wellsLong]);
      expect(plan.wellRecords, 2);
      expect(plan.duplicates, 1, reason: 'r1 déjà présente');
      expect(plan.issues.map((i) => i.messageKey), ['importUnknownWell', 'importBadDate', 'importUnknownType']);
      expect(plan.issues.first.line, 5);
    });

    test('Excel format large et usine', () {
      final bytes = ExcelExporter.encode([
        ExportTable(
          name: 'Puits',
          headers: ['Date', 'Puits', 'BSW (%)', 'Pression (bar)', 'Autre'],
          rows: [
            [DateOnly(DateTime(2026, 10, 5)), 'PN-02', 0.5, 80.0, 'x'],
            [DateOnly(DateTime(2026, 10, 6)), 'PN-02', null, 82.0, null],
          ],
        ),
        ExportTable(
          name: 'Usine',
          headers: ['Date', 'Point', 'pH', 'Densité (kg/m³)', 'Aspect', 'Commentaire'],
          rows: [
            [DateOnly(DateTime(2026, 10, 5)), 'W1', 7.1, 1020.0, 'Limpide', 'ok'],
            [DateOnly(DateTime(2026, 10, 5)), 'ZZ', 7.0, null, null, null],
          ],
        ),
      ])!;
      final tables = readTables('import.xlsx', bytes);
      expect(tables.map((t) => t.name), ['Puits', 'Usine']);
      final plan = _importer().analyze(tables);
      expect(plan.kinds, [ImportKind.wellsWide, ImportKind.plant]);
      expect(plan.wellRecords, 3);
      expect(plan.plantRecords, 1);
      expect(plan.issues.single.messageKey, 'importUnknownPoint');
      final preview = plan.preview(const Locale('fr'));
      expect(preview.last.last, contains('appearance=plantAppearanceClear'));
    });

    test('fichier sans colonne date', () {
      final plan = _importer().analyze([readCsv('Puits,BSW\nPN-01,1')!]);
      expect(plan.total, 0);
      expect(plan.issues.single.messageKey, 'importNoDateColumn');
    });
  });
}
