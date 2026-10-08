import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/auth/app_lock.dart';
import 'core/auth/auth_providers.dart';
import 'core/config/env.dart';
import 'core/l10n/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  for (final locale in supportedLocales) {
    await initializeDateFormatting(locale.languageCode, null);
  }
  assert(Env.isConfigured, Env.missingConfigMessage);
  if (Env.isConfigured) {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: Env.firebaseApiKey,
        appId: Env.firebaseAppId,
        messagingSenderId: Env.firebaseMessagingSenderId,
        projectId: Env.firebaseProjectId,
        storageBucket: Env.firebaseStorageBucket.isEmpty ? null : Env.firebaseStorageBucket,
      ),
    );
  }
  runApp(const ProviderScope(child: SuiviPuitsApp()));
}

class SuiviPuitsApp extends ConsumerStatefulWidget {
  const SuiviPuitsApp({super.key});

  @override
  ConsumerState<SuiviPuitsApp> createState() => _SuiviPuitsAppState();
}

class _SuiviPuitsAppState extends ConsumerState<SuiviPuitsApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reverrouille l'app quand elle repasse en arrière-plan (code à 4
    // chiffres / empreinte redemandés au retour), comme une app bancaire.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      ref.read(appLockProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Env.isConfigured) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(Env.missingConfigMessage, textAlign: TextAlign.center),
            ),
          ),
        ),
      );
    }

    final authReady = ref.watch(authReadyProvider);
    final locale = ref.watch(localeProvider);
    final sessionAuthenticated = ref.watch(sessionAuthenticatedProvider);
    final appLockHasPin = ref.watch(appLockProvider.select((s) => s.hasPin));

    if (authReady.isLoading || (sessionAuthenticated && appLockHasPin == null)) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Suivi Puits',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
