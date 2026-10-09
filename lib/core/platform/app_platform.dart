import 'package:flutter/foundation.dart';

/// Plateforme courante, sans `dart:io` (indisponible dans un navigateur).

bool get isWeb => kIsWeb;

bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// PC (Windows, Linux, macOS) en application installée — pas le web.
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);
