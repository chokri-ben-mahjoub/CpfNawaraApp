import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/pin_setup_screen.dart';
import '../../features/auth/presentation/profile_setup_screen.dart';
import '../../features/auth/presentation/unlock_screen.dart';
import '../../features/admin/presentation/params_screen.dart';
import '../../features/admin/presentation/admin_screen.dart';
import '../../features/admin/presentation/analysis_types_screen.dart';
import '../../features/admin/presentation/audit_screen.dart';
import '../../features/admin/presentation/circuits_screen.dart';
import '../../features/admin/presentation/data_admin_screen.dart';
import '../../features/admin/presentation/firebase_project_screen.dart';
import '../../features/admin/presentation/sample_points_screen.dart';
import '../../features/admin/presentation/thresholds_screen.dart';
import '../../features/admin/presentation/users_screen.dart';
import '../../features/admin/presentation/wells_manage_screen.dart';
import '../../features/analysis/presentation/compare_screen.dart';
import '../../features/analysis/presentation/decline_screen.dart';
import '../../features/analysis/presentation/ratio_trend_screen.dart';
import '../../features/assistant/presentation/assistant_screen.dart';
import '../../features/entry/presentation/quick_entry_screen.dart';
import '../../features/qr/presentation/qr_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/interventions/presentation/interventions_screen.dart';
import '../../features/plant/presentation/plant_entry_screen.dart';
import '../../features/plant/presentation/plant_point_screen.dart';
import '../../features/owner/owner_screen.dart';
import '../../features/plant/presentation/plant_schema_screens.dart';
import '../../features/plant/presentation/plant_trend_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/setup/presentation/setup_screen.dart';
import '../../features/stock/presentation/stock_item_detail_screen.dart';
import '../../features/stock/presentation/stock_screen.dart';
import '../../features/wells/presentation/trend_screen.dart';
import '../../features/wells/presentation/well_detail_screen.dart';
import '../../features/wells/presentation/well_history_screen.dart';
import '../analysis/production_metrics.dart';
import '../auth/app_lock.dart';
import '../auth/auth_providers.dart';
import '../models/user_role.dart';
import '../sync/sync_service.dart';

const _authFreeLocations = {'/onboarding', '/setup', '/setup-profile'};

final appRouterProvider = Provider<GoRouter>((ref) {
  final onboardingDone = ref.watch(onboardingDoneProvider);
  final sessionAuthenticated = ref.watch(sessionAuthenticatedProvider);
  final role = ref.watch(currentRoleProvider);
  final appLock = ref.watch(appLockProvider);

  String initialLocation() {
    if (!onboardingDone) return '/onboarding';
    if (!sessionAuthenticated) return '/setup';
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
        return _authFreeLocations.contains(loc) ? null : '/setup';
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
      if (loc.startsWith('/plant/entry') && !role.canEnterData) return '/home';
      if (loc.startsWith('/plant/schema') && !role.canConfigure) return '/home';
      // Clients (codes d'activation) : propriétaire de PuitsTrack seulement.
      if (loc == '/owner' && !ref.read(syncControllerProvider.notifier).isOwner) return '/home';
      // Administration : réservée au rôle admin (écrans masqués et protégés).
      if ((loc == '/admin' || loc.startsWith('/admin/')) && !role.canConfigure) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
      GoRoute(path: '/setup-profile', builder: (context, state) => const ProfileSetupScreen()),
      GoRoute(path: '/pin-setup', builder: (context, state) => const PinSetupScreen()),
      GoRoute(path: '/unlock', builder: (context, state) => const UnlockScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeShell()),
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
        builder: (context, state) =>
            TrendScreen(wellId: state.pathParameters['id']!, typeId: state.pathParameters['typeId']!),
      ),
      GoRoute(
        path: '/wells/:id/interventions',
        builder: (context, state) => InterventionsScreen(wellId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/wells/:id/decline',
        builder: (context, state) =>
            DeclineScreen(wellId: state.pathParameters['id']!, initialFluid: state.uri.queryParameters['fluid']),
      ),
      GoRoute(
        path: '/wells/:id/ratio/:ratio',
        builder: (context, state) => RatioTrendScreen(
          wellId: state.pathParameters['id']!,
          ratio: DerivedRatioX.fromKey(state.pathParameters['ratio']!) ?? DerivedRatio.gor,
        ),
      ),
      GoRoute(
        path: '/plant/point/:id',
        builder: (context, state) => PlantPointScreen(pointId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/plant/point/:id/trend/:param',
        builder: (context, state) =>
            PlantTrendScreen(pointId: state.pathParameters['id']!, paramKey: state.pathParameters['param']!),
      ),
      GoRoute(
        path: '/plant/entry/:id',
        builder: (context, state) => PlantEntryScreen(
          pointId: state.pathParameters['id']!,
          initialDate: DateTime.tryParse(state.uri.queryParameters['date'] ?? ''),
          analysisId: state.uri.queryParameters['analysisId'],
        ),
      ),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/stock', builder: (context, state) => const StockScreen()),
      GoRoute(path: '/assistant', builder: (context, state) => const AssistantScreen()),
      GoRoute(path: '/qr', builder: (context, state) => const QrScreen()),
      GoRoute(
        path: '/stock/:id',
        builder: (context, state) => StockItemDetailScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/compare',
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return CompareScreen(
            initialMode: q['mode'] == 'periods' ? CompareMode.periods : CompareMode.wells,
            initialWellA: q['wellA'],
            initialWellB: q['wellB'],
            initialMetric: q['metric'],
            initialInterventionId: q['interventionId'],
          );
        },
      ),
      GoRoute(
        path: '/entry',
        builder: (context, state) => QuickEntryScreen(
          initialWellId: state.uri.queryParameters['wellId'],
          initialTypeId: state.uri.queryParameters['typeId'],
        ),
      ),
      GoRoute(path: '/admin', builder: (context, state) => const AdminScreen()),
      GoRoute(path: '/admin/users', builder: (context, state) => const UsersScreen()),
      GoRoute(path: '/admin/points', builder: (context, state) => const SamplePointsScreen()),
      GoRoute(path: '/admin/circuits', builder: (context, state) => const CircuitsScreen()),
      GoRoute(path: '/admin/schemas', builder: (context, state) => const PlantSchemasScreen()),
      GoRoute(path: '/admin/params', builder: (context, state) => const ParamsScreen()),
      GoRoute(path: '/owner', builder: (context, state) => const OwnerScreen()),
      GoRoute(
        path: '/plant/schema/:id',
        builder: (context, state) => PlantSchemaEditorScreen(schemaId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/admin/thresholds', builder: (context, state) => const ThresholdsScreen()),
      GoRoute(path: '/admin/data', builder: (context, state) => const DataAdminScreen()),
      GoRoute(path: '/admin/firebase', builder: (context, state) => const FirebaseProjectScreen()),
      GoRoute(path: '/admin/audit', builder: (context, state) => const AuditScreen()),
      GoRoute(path: '/admin/analysis-types', builder: (context, state) => const AnalysisTypesScreen()),
      GoRoute(path: '/admin/wells', builder: (context, state) => const WellsManageScreen()),
    ],
  );
});
