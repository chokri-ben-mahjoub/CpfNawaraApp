// Choix du moteur SQLite selon la plateforme (voir `main.dart`) :
// sqflite natif sur mobile, FFI sur PC, WebAssembly dans le navigateur.
export 'db_factory_stub.dart'
    if (dart.library.io) 'db_factory_io.dart'
    if (dart.library.js_interop) 'db_factory_web.dart';
