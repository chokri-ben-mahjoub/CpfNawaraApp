import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/auth/auth_providers.dart';
import 'core/l10n/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  for (final locale in supportedLocales) {
    await initializeDateFormatting(locale.languageCode, null);
  }
  runApp(const ProviderScope(child: SuiviPuitsApp()));
}

class SuiviPuitsApp extends ConsumerWidget {
  const SuiviPuitsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authReady = ref.watch(authReadyProvider);
    final locale = ref.watch(localeProvider);

    if (authReady.isLoading) {
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
