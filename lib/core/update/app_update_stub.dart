import 'package:flutter/foundation.dart';

/// Hors navigateur : jamais de mise à jour web à proposer.
final ValueNotifier<bool> appUpdateReady = ValueNotifier<bool>(false);

void startWatchingAppUpdates() {}

void applyAppUpdate() {}
