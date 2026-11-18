import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Vrai quand une nouvelle version est téléchargée et attend l'accord de
/// l'utilisateur (signalé par web/flutter_bootstrap.js).
final ValueNotifier<bool> appUpdateReady = ValueNotifier<bool>(false);

bool _watching = false;

void startWatchingAppUpdates() {
  if (_watching) return;
  _watching = true;
  void sync() {
    final flag = globalContext.getProperty<JSAny?>('__appUpdateReady'.toJS);
    if (flag != null && (flag as JSBoolean).toDart) appUpdateReady.value = true;
  }

  web.window.addEventListener(
    'app-update-ready',
    ((web.Event _) => sync()).toJS,
  );
  sync();
}

Map<Object?, Object?>? _notes() {
  final raw = globalContext
      .getProperty<JSAny?>('__appUpdateNotes'.toJS)
      .dartify();
  return raw is Map ? raw : null;
}

/// Numéro de la version en attente, si le serveur l'indique.
String? appUpdateVersion() {
  final v = _notes()?['version'];
  return v is String && v.isNotEmpty ? v : null;
}

/// Nouveautés de la version en attente dans la langue demandée (sinon le
/// français), vides si le fichier est introuvable.
List<String> appUpdateNotesFor(String languageCode) {
  final notes = _notes()?['notes'];
  if (notes is! Map) return const [];
  final list = notes[languageCode] ?? notes['fr'];
  return list is List ? [for (final n in list) '$n'] : const [];
}

/// Active la nouvelle version : la page se recharge toute seule.
void applyAppUpdate() {
  globalContext.callMethod<JSAny?>('__applyAppUpdate'.toJS);
}
