import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/auth/app_lock.dart';
import 'core/auth/auth_providers.dart';
import 'core/data/db_factory.dart';
import 'core/l10n/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/settings/app_settings.dart';
import 'core/settings/startup_tasks.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/page_transitions.dart';
import 'features/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Moteur SQLite : natif (mobile), FFI (PC) ou WebAssembly (navigateur).
  configureDatabaseFactory();
  for (final locale in supportedLocales) {
    await initializeDateFormatting(locale.languageCode, null);
  }
  runApp(const ProviderScope(child: SuiviPuitsApp()));
}

class SuiviPuitsApp extends ConsumerStatefulWidget {
  const SuiviPuitsApp({super.key});

  @override
  ConsumerState<SuiviPuitsApp> createState() => _SuiviPuitsAppState();
}

/// Durée minimale de l'écran de démarrage : le temps de son animation
/// d'entrée (sinon il ne ferait que clignoter).
const _splashMinDuration = Duration(milliseconds: 1100);

class _SuiviPuitsAppState extends ConsumerState<SuiviPuitsApp> with WidgetsBindingObserver {
  bool _splashShown = false;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(_splashMinDuration, () {
      if (mounted) setState(() => _splashShown = true);
    });
    WidgetsBinding.instance.addObserver(this);
    // Écran protégé, rappels, sauvegarde automatique (voir startup_tasks.dart).
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(onAppForeground(ref)));
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Moment du dernier passage en arrière-plan, quand un délai de
  /// verrouillage automatique est réglé.
  DateTime? _pausedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final delay = Duration(seconds: ref.read(appSettingsProvider).autoLockSeconds);
    // Reverrouille l'app quand elle repasse en arrière-plan (code à 4
    // chiffres / empreinte redemandés au retour), comme une app bancaire —
    // immédiatement, ou après le délai choisi dans les Réglages.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (LockGuard.active) return;
      if (delay == Duration.zero) {
        ref.read(appLockProvider.notifier).lock();
      } else {
        _pausedAt ??= DateTime.now();
      }
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt != null && DateTime.now().difference(pausedAt) >= delay) {
        ref.read(appLockProvider.notifier).lock();
      }
      unawaited(onAppForeground(ref));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authReady = ref.watch(authReadyProvider);
    final locale = ref.watch(localeProvider);
    final sessionAuthenticated = ref.watch(sessionAuthenticatedProvider);
    final appLockHasPin = ref.watch(appLockProvider.select((s) => s.hasPin));

    // Écran de démarrage tant que l'app se prépare (réglages, profil,
    // verrouillage), et au moins le temps de son animation.
    if (!_splashShown || authReady.isLoading || (sessionAuthenticated && appLockHasPin == null)) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: SplashScreen(appName: ref.watch(appNameProvider), tagline: tr(locale, 'appTagline')),
      );
    }

    final router = ref.watch(appRouterProvider);

    final themeMode = ref.watch(appSettingsProvider.select((s) => s.themeMode));

    return MaterialApp.router(
      title: ref.watch(appNameProvider),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      // Entrée en fondu après l'écran de démarrage.
      builder: (context, child) => FadeInOnce(child: child ?? const SizedBox.shrink()),
    );
  }
}
