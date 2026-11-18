import 'package:flutter/foundation.dart';

/// Hors navigateur : jamais de mise à jour web à proposer.
final ValueNotifier<bool> appUpdateReady = ValueNotifier<bool>(false);

void startWatchingAppUpdates() {}

/// Version et nouveautés de la mise à jour en attente (web uniquement).
String? appUpdateVersion() => null;

List<String> appUpdateNotesFor(String languageCode) => const [];

void applyAppUpdate() {}
