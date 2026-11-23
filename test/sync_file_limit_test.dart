import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/data/local_database.dart';
import 'package:puitstrack/core/sync/sync_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  String big(int n) => 'a' * n;

  group('limitSyncedFiles (limite 1 Mo du document Firestore)', () {
    test('deux fichiers qui passent seuls mais pas ensemble : le plus gros est écarté', () {
      final data = <String, Object?>{'attachment': big(600000), 'coa': big(500000)};
      limitSyncedFiles(data);
      expect(data['attachment'], isNull);
      expect(data['coa'], isNotNull);
    });

    test('sous la limite : rien ne change', () {
      final data = <String, Object?>{'attachment': big(400000), 'coa': big(400000)};
      limitSyncedFiles(data);
      expect(data['attachment'], isNotNull);
      expect(data['coa'], isNotNull);
    });

    test('champs absents : sans effet', () {
      final data = <String, Object?>{'name': 'x'};
      limitSyncedFiles(data);
      expect(data, {'name': 'x'});
    });
  });

  test('base déjà notée v37 mais sans table sops ni colonne packaging : réparée à la réouverture', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('puits_heal');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/heal.db';

    var db = await LocalDatabase.openAt(path, factory: databaseFactoryFfi);
    // Simule une base ouverte par une version intermédiaire de l'app.
    await db.execute('drop table sops');
    await db.execute('alter table stock_items drop column packaging');
    expect((await db.rawQuery('pragma table_info(stock_items)')).map((c) => c['name']), isNot(contains('packaging')));
    await db.close();

    db = await LocalDatabase.openAt(path, factory: databaseFactoryFfi);
    expect((await db.rawQuery('pragma table_info(sops)')).map((c) => c['name']), contains('file_name'));
    expect((await db.rawQuery('pragma table_info(stock_items)')).map((c) => c['name']), contains('packaging'));
    await db.close();
  });
}
