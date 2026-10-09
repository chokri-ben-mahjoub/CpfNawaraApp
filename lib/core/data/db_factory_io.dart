import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// sqflite ne gère que Android/iOS : sur PC, même base SQLite via FFI
/// (sqlite3.dll fourni au build par le paquet sqlite3).
void configureDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
