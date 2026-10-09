// Rendu des écrans d'analyse (fiche puits, comparaison, déclin, ratios,
// interventions, filtres, feuille d'export) avec un jeu de données réaliste,
// sur un écran de téléphone : échoue en cas d'exception ou de débordement de
// mise en page.
import 'dart:math' as math;

import 'package:puitstrack/core/auth/auth_providers.dart';
import 'package:puitstrack/core/data/wells_repository.dart';
import 'package:puitstrack/core/export/download_saver.dart';
import 'package:puitstrack/core/export/export_format_sheet.dart';
import 'package:puitstrack/core/l10n/app_strings.dart';
import 'package:puitstrack/core/models/analysis_record.dart';
import 'package:puitstrack/core/models/analysis_type.dart';
import 'package:puitstrack/core/models/intervention.dart';
import 'package:puitstrack/core/models/production_types.dart';
import 'package:puitstrack/core/models/user_role.dart';
import 'package:puitstrack/core/models/well.dart';
import 'package:puitstrack/core/theme/app_theme.dart';
import 'package:puitstrack/features/analysis/presentation/compare_screen.dart';
import 'package:puitstrack/features/analysis/presentation/decline_screen.dart';
import 'package:puitstrack/features/analysis/presentation/ratio_trend_screen.dart';
import 'package:puitstrack/core/analysis/production_metrics.dart';
import 'package:puitstrack/features/interventions/presentation/interventions_screen.dart';
import 'package:puitstrack/features/stats/presentation/stats_screen.dart';
import 'package:puitstrack/features/wells/presentation/well_detail_screen.dart';
import 'package:puitstrack/features/wells/presentation/wells_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:puitstrack/core/notifications/reminder_service.dart';
import 'package:puitstrack/features/settings/presentation/settings_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

WellsState _seed() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  const types = [
    AnalysisType(id: 't_bsw', label: 'BSW', unit: '%', min: 0, max: 2, frequency: AnalysisFrequency.daily),
    AnalysisType(id: 't_h2s', label: 'H2S', unit: 'ppm', min: 0, max: 10, frequency: AnalysisFrequency.daily),
    AnalysisType(id: 't_pressure', label: 'Pression', unit: 'bar', min: 20, max: 120, frequency: AnalysisFrequency.daily),
    AnalysisType(id: oilFlowTypeId, label: 'Débit huile', unit: 'm³/j', min: 0, max: 100000, frequency: AnalysisFrequency.daily),
    AnalysisType(id: gasFlowTypeId, label: 'Débit gaz', unit: 'Sm³/j', min: 0, max: 1000000, frequency: AnalysisFrequency.daily),
    AnalysisType(id: waterFlowTypeId, label: 'Débit eau', unit: 'm³/j', min: 0, max: 100000, frequency: AnalysisFrequency.daily),
    AnalysisType(id: bottomHolePressureTypeId, label: 'Pression de fond (Pwf)', unit: 'bar', min: 0, max: 1000, frequency: AnalysisFrequency.onDemand),
  ];
  const wells = [
    Well(id: 'w1', code: 'PN-01', name: 'Puits Nord 1', active: true, group: 'Zone Nord', reservoirPressure: 210),
    Well(id: 'w2', code: 'PN-02', name: 'Puits Nord 2', active: true, group: 'Zone Nord'),
    Well(id: 'w3', code: 'PS-01', name: 'Puits Sud 1', active: false, group: 'Zone Sud'),
  ];
  final rnd = math.Random(4);
  final records = <AnalysisRecord>[];
  var n = 0;
  void add(String well, String type, double v, DateTime at) => records.add(AnalysisRecord(
        id: 'r${n++}',
        wellId: well,
        typeId: type,
        value: double.parse(v.toStringAsFixed(2)),
        serviceKey: 'serviceProduction',
        operatorName: 'Ahmed',
        dateTime: at,
      ));
  final intervention = today.subtract(const Duration(days: 40));
  for (var d = 120; d >= 0; d--) {
    final day = today.subtract(Duration(days: d)).add(const Duration(hours: 9));
    final boost = day.isAfter(intervention) ? 1.35 : 1.0;
    final sinceStart = day.isAfter(intervention) ? day.difference(intervention).inDays : 120 - d;
    final oil = 110 * boost * math.exp(-0.004 * sinceStart) * (1 + (rnd.nextDouble() - 0.5) * 0.06);
    add('w1', oilFlowTypeId, oil, day);
    add('w1', gasFlowTypeId, oil * (140 + d * 0.1), day);
    add('w1', waterFlowTypeId, oil * (0.15 + (120 - d) * 0.001), day);
    add('w1', 't_bsw', 1.2 + rnd.nextDouble() * 0.6, day);
    if (d % 15 == 0) add('w1', bottomHolePressureTypeId, 150 - (120 - d) * 0.1, day);
    final oil2 = 70 * math.exp(-0.002 * (120 - d)) * (1 + (rnd.nextDouble() - 0.5) * 0.08);
    add('w2', oilFlowTypeId, oil2, day);
    add('w2', gasFlowTypeId, oil2 * 180, day);
    add('w2', waterFlowTypeId, oil2 * 0.3, day);
  }
  final interventions = [
    Intervention(
      id: 'i1',
      wellId: 'w1',
      date: intervention,
      typeKey: 'interventionTypeStimulation',
      cost: 45000,
      currency: 'TND',
      resultKey: 'interventionResultSuccess',
      description: 'Acidification 15 % HCl, duse inchangée',
      operatorName: 'Ahmed',
    ),
    Intervention(
      id: 'i2',
      wellId: 'w1',
      date: today.subtract(const Duration(days: 95)),
      typeKey: 'interventionTypeChokeChange',
      cost: 1200,
      currency: 'TND',
      resultKey: 'interventionResultPartial',
      operatorName: 'Ahmed',
    ),
  ];
  return WellsState(wells: wells, analysisTypes: types, records: records, interventions: interventions);
}

class _AdminProfile extends ProfileController {
  _AdminProfile() {
    state = const AppProfile(id: 'p', fullName: 'Ahmed', phone: '', serviceKey: 'serviceProduction', role: UserRole.admin);
  }
}

Widget _app(Widget home, WellsState data, {bool dark = false}) => ProviderScope(
      overrides: [
        wellsControllerProvider.overrideWith((ref) => WellsController.seeded(data)),
        profileProvider.overrideWith((ref) => _AdminProfile()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        locale: const Locale('fr'),
        supportedLocales: supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

Future<void> _render(WidgetTester tester, Widget home, {double height = 844, bool dark = false}) async {
  tester.view.physicalSize = Size(390 * 2.0, height * 2.0);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(home, _seed(), dark: dark));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('fr');
    DownloadSaver.debugForceSupported = true;
    ReminderService.debugForceSupported = true;
  });

  testWidgets('fiche puits', (t) => _render(t, const WellDetailScreen(wellId: 'w1'), height: 2700));
  testWidgets('comparer puits', (t) => _render(t, const CompareScreen(), height: 1250));
  testWidgets(
    'avant/après',
    (t) => _render(
      t,
      const CompareScreen(initialMode: CompareMode.periods, initialWellA: 'w1', initialInterventionId: 'i1'),
      height: 1250,
    ),
  );
  testWidgets('déclin', (t) => _render(t, const DeclineScreen(wellId: 'w1'), height: 1700));
  testWidgets('PI', (t) => _render(t, const RatioTrendScreen(wellId: 'w1', ratio: DerivedRatio.pi), height: 1100));
  testWidgets('interventions', (t) => _render(t, const InterventionsScreen(wellId: 'w1')));
  testWidgets('liste puits', (t) => _render(t, const Scaffold(body: SafeArea(child: WellsListScreen()))));
  testWidgets('stats', (t) => _render(t, const Scaffold(body: SafeArea(child: StatsScreen())), height: 1100));
  testWidgets('réglages', (t) => _render(t, const SettingsScreen(), height: 2900));
  testWidgets('réglages (sombre)', (t) => _render(t, const SettingsScreen(), height: 2900, dark: true));
  testWidgets('fiche puits (sombre)', (t) => _render(t, const WellDetailScreen(wellId: 'w1'), height: 2700, dark: true));
  testWidgets('feuille export', (t) async {
    t.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(onPressed: () => chooseExport(context, const Locale('fr')), child: const Text('go')),
          ),
        ),
      ),
      _seed(),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Télécharger'), findsOneWidget);
    expect(find.text('Partager'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
