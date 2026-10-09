import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Navigateur : SQLite compilé en WebAssembly (web/sqlite3.wasm), exécuté
/// dans un worker (web/sqflite_sw.js), données conservées dans IndexedDB.
/// Fichiers générés par `dart run sqflite_common_ffi_web:setup`.
void configureDatabaseFactory() {
  databaseFactory = databaseFactoryFfiWeb;
}
