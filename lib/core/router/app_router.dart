import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/code_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/admin/presentation/analysis_types_screen.dart';
import '../../features/entry/presentation/quick_entry_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/wells/presentation/trend_screen.dart';
import '../../features/wells/presentation/well_detail_screen.dart';
import '../auth/auth_providers.dart';
import '../models/user_role.dart';

const _authFreeLocations = {
  '/onboarding',
  '/login',
  '/login/code',
  '/signup',
  '/forgot-password',
  '/forgot-password/code',
  '/forgot-password/reset',
};

final appRouterProvider = Provider<GoRouter>((ref) {
  final onboardingDone = ref.watch(onboardingDoneProvider);
  final sessionAuthenticated = ref.watch(sessionAuthenticatedProvider);
  final role = ref.watch(currentRoleProvider);

  String initialLocation() {
    if (!onboardingDone) return '/onboarding';
    if (!sessionAuthenticated) return '/login';
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
        return _authFreeLocations.contains(loc) ? null : '/login';
      }
      if (_authFreeLocations.contains(loc)) return '/home';
      if (loc == '/entry' && !role.canEnterData) return '/home';
      if (loc == '/admin/analysis-types' && !role.canConfigure) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/login/code',
        builder: (context, state) => const CodeScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/forgot-password/code',
        builder: (context, state) => const CodeScreen(purpose: CodePurpose.passwordReset),
      ),
      GoRoute(
        path: '/forgot-password/reset',
        builder: (context, state) => const ResetPasswordScreen(),
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
    ],
  );
});
