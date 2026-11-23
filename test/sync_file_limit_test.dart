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

  test('une base déjà en v36 sans table sops la reçoit à l\'ouverture', () async {
    sqfliteFfiInit();
    final db = await LocalDatabase.openAt(inMemoryDatabasePath, factory: databaseFactoryFfi);
    await db.execute('drop table sops');
    await db.close();
    // Ouverture d'une base neuve : la table doit exister (création + onOpen).
    final fresh = await LocalDatabase.openAt(inMemoryDatabasePath, factory: databaseFactoryFfi);
    final cols = await fresh.rawQuery('pragma table_info(sops)');
    expect(cols.map((c) => c['name']), contains('file_name'));
    await fresh.close();
  });
}
