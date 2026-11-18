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

/// Active la nouvelle version : la page se recharge toute seule.
void applyAppUpdate() {
  globalContext.callMethod<JSAny?>('__applyAppUpdate'.toJS);
}
