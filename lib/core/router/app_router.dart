import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/pin_setup_screen.dart';
import '../../features/auth/presentation/profile_setup_screen.dart';
import '../../features/auth/presentation/unlock_screen.dart';
import '../../features/admin/presentation/analysis_types_screen.dart';
import '../../features/admin/presentation/wells_manage_screen.dart';
import '../../features/entry/presentation/quick_entry_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/wells/presentation/trend_screen.dart';
import '../../features/wells/presentation/well_detail_screen.dart';
import '../../features/wells/presentation/well_history_screen.dart';
import '../auth/app_lock.dart';
import '../auth/auth_providers.dart';
import '../models/user_role.dart';

const _authFreeLocations = {
  '/onboarding',
  '/setup-profile',
};

final appRouterProvider = Provider<GoRouter>((ref) {
  final onboardingDone = ref.watch(onboardingDoneProvider);
  final sessionAuthenticated = ref.watch(sessionAuthenticatedProvider);
  final role = ref.watch(currentRoleProvider);
  final appLock = ref.watch(appLockProvider);

  String initialLocation() {
    if (!onboardingDone) return '/onboarding';
    if (!sessionAuthenticated) return '/setup-profile';
    if (appLock.hasPin == false) return '/pin-setup';
    if (appLock.hasPin == true && !appLock.unlocked) return '/unlock';
    return '/home';
  }

  return GoRouter(
    initialLocation: initialLocation(),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (!onboardingDone) {
        return loc == '/onboarding' ? null : '/onboarding';
      }
      if (!sessionAuthenticated) {
        return _authFreeLocations.contains(loc) ? null : '/setup-profile';
      }
      // Profil configuré mais verrouillage local (code 4 chiffres / empreinte)
      // pas encore passé : on bloque tout le reste de l'app.
      if (appLock.hasPin == null) return null; // lecture locale en cours (quasi instantanée)
      if (appLock.hasPin == false) {
        return loc == '/pin-setup' ? null : '/pin-setup';
      }
      if (!appLock.unlocked) {
        return loc == '/unlock' ? null : '/unlock';
      }
      // '/pin-setup' n'est volontairement pas dans cette liste : une fois
      // déverrouillé, l'utilisateur peut encore y naviguer pour changer son
      // code (depuis le compte) ; l'écran se charge alors de revenir en
      // arrière lui-même après la saisie.
      if (_authFreeLocations.contains(loc) || loc == '/unlock') {
        return '/home';
      }
      if (loc == '/entry' && !role.canEnterData) return '/home';
      if (loc == '/admin/analysis-types' && !role.canConfigure) return '/home';
      if (loc == '/admin/wells' && !role.canConfigure) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/setup-profile',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/pin-setup',
        builder: (context, state) => const PinSetupScreen(),
      ),
      GoRoute(
        path: '/unlock',
        builder: (context, state) => const UnlockScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        path: '/wells/:id',
        builder: (context, state) => WellDetailScreen(wellId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/wells/:id/history',
        builder: (context, state) => WellHistoryScreen(wellId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/wells/:id/trend/:typeId',
        builder: (context, state) => TrendScreen(
          wellId: state.pathParameters['id']!,
          typeId: state.pathParameters['typeId']!,
        ),
      ),
      GoRoute(
        path: '/entry',
        builder: (context, state) => QuickEntryScreen(
          initialWellId: state.uri.queryParameters['wellId'],
          initialTypeId: state.uri.queryParameters['typeId'],
        ),
      ),
      GoRoute(
        path: '/admin/analysis-types',
        builder: (context, state) => const AnalysisTypesScreen(),
      ),
      GoRoute(
        path: '/admin/wells',
        builder: (context, state) => const WellsManageScreen(),
      ),
    ],
  );
});
