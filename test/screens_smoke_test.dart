// Rendu des écrans d'analyse (fiche puits, comparaison, déclin, ratios,
// interventions, filtres, feuille d'export) avec un jeu de données réaliste,
// sur un écran de téléphone : échoue en cas d'exception ou de débordement de
// mise en page.
import 'dart:convert';
import 'dart:math' as math;

import 'package:puitstrack/core/app_info.dart';
import 'package:puitstrack/core/auth/auth_providers.dart';
import 'package:puitstrack/core/config/shared_config.dart';
import 'package:puitstrack/core/sync/firebase_config.dart';
import 'package:puitstrack/features/admin/presentation/admin_screen.dart';
import 'package:puitstrack/features/admin/presentation/audit_screen.dart';
import 'package:puitstrack/features/admin/presentation/data_admin_screen.dart';
import 'package:puitstrack/features/admin/presentation/firebase_project_screen.dart';
import 'package:puitstrack/features/admin/presentation/sample_points_screen.dart';
import 'package:puitstrack/features/admin/presentation/thresholds_screen.dart';
import 'package:puitstrack/features/admin/presentation/users_screen.dart';
import 'package:puitstrack/features/admin/presentation/wells_manage_screen.dart';
import 'package:puitstrack/features/alerts/presentation/alerts_screen.dart';
import 'package:puitstrack/features/setup/presentation/setup_screen.dart';
import 'package:puitstrack/features/setup/presentation/widgets/firebase_project_picker.dart';
import 'package:puitstrack/core/widgets/app_loader.dart';
import 'package:puitstrack/features/auth/presentation/pin_setup_screen.dart';
import 'package:puitstrack/features/auth/presentation/profile_setup_screen.dart';
import 'package:puitstrack/features/auth/presentation/unlock_screen.dart';
import 'package:puitstrack/features/dashboard/presentation/dashboard_screen.dart';
import 'package:puitstrack/features/qr/presentation/qr_screen.dart';
import 'package:puitstrack/features/home/presentation/home_shell.dart';
import 'package:puitstrack/features/home/presentation/widgets/notification_bell.dart';
import 'package:puitstrack/features/splash/splash_screen.dart';
import 'package:puitstrack/core/data/stock_repository.dart';
import 'package:puitstrack/core/data/wells_repository.dart';
import 'package:puitstrack/core/models/stock_item.dart';
import 'package:puitstrack/features/stock/presentation/stock_item_detail_screen.dart';
import 'package:puitstrack/features/stock/presentation/stock_screen.dart';
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
import 'package:puitstrack/features/entry/presentation/batch_entry_screen.dart';
import 'package:puitstrack/features/wells/presentation/well_detail_screen.dart';
import 'package:puitstrack/features/wells/presentation/well_history_screen.dart';
import 'package:puitstrack/features/wells/presentation/wells_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:puitstrack/core/filters/well_filter.dart';
import 'package:puitstrack/features/stats/presentation/widgets/stats_extras.dart';
import 'package:puitstrack/core/plant/plant_catalog.dart';
import 'package:puitstrack/core/plant/plant_repository.dart';
import 'package:puitstrack/features/plant/presentation/plant_entry_screen.dart';
import 'package:puitstrack/features/admin/presentation/params_screen.dart';
import 'package:puitstrack/features/plant/presentation/plant_point_screen.dart';
import 'package:puitstrack/features/plant/presentation/plant_schema_screens.dart';
import 'package:puitstrack/features/plant/presentation/plant_screen.dart';
import 'package:puitstrack/features/plant/presentation/plant_trend_screen.dart';
import 'package:puitstrack/core/notifications/reminder_service.dart';
import 'package:puitstrack/features/settings/presentation/pdf_export_settings_screen.dart';
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
    AnalysisType(
      id: 't_pressure',
      label: 'Pression',
      unit: 'bar',
      min: 20,
      max: 120,
      frequency: AnalysisFrequency.daily,
    ),
    AnalysisType(
      id: oilFlowTypeId,
      label: 'Débit huile',
      unit: 'm³/j',
      min: 0,
      max: 100000,
      frequency: AnalysisFrequency.daily,
    ),
    AnalysisType(
      id: gasFlowTypeId,
      label: 'Débit gaz',
      unit: 'Sm³/j',
      min: 0,
      max: 1000000,
      frequency: AnalysisFrequency.daily,
    ),
    AnalysisType(
      id: waterFlowTypeId,
      label: 'Débit eau',
      unit: 'm³/j',
      min: 0,
      max: 100000,
      frequency: AnalysisFrequency.daily,
    ),
    AnalysisType(
      id: bottomHolePressureTypeId,
      label: 'Pression de fond (Pwf)',
      unit: 'bar',
      min: 0,
      max: 1000,
      frequency: AnalysisFrequency.onDemand,
    ),
  ];
  const wells = [
    Well(id: 'w1', code: 'PN-01', name: 'Puits Nord 1', active: true, group: 'Zone Nord', reservoirPressure: 210),
    Well(id: 'w2', code: 'PN-02', name: 'Puits Nord 2', active: true, group: 'Zone Nord'),
    Well(id: 'w3', code: 'PS-01', name: 'Puits Sud 1', active: false, group: 'Zone Sud'),
  ];
  final rnd = math.Random(4);
  final records = <AnalysisRecord>[];
  var n = 0;
  void add(String well, String type, double v, DateTime at) => records.add(
    AnalysisRecord(
      id: 'r${n++}',
      wellId: well,
      typeId: type,
      value: double.parse(v.toStringAsFixed(2)),
      serviceKey: 'serviceProduction',
      operatorName: 'Ahmed',
      dateTime: at,
    ),
  );
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

/// Usine : analyses du jour sur 3 points (une hors seuil), les autres non
/// analysés.
PlantController _seedPlant() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final circuitsById = {
    for (final row in plantSeedCircuits)
      row['id']! as String: PlantCircuit(
        id: row['id']! as String,
        labelKey: row['label_key']! as String,
        colorValue: row['color']! as int,
        iconKey: row['icon']! as String,
        defaultProfile: row['default_profile']! as String,
        sortOrder: row['sort_order']! as int,
      ),
  };
  final points = [
    for (final row in plantSeedPoints)
      SamplePoint(
        id: row['id']! as String,
        code: row['code']! as String,
        circuit: circuitsById[row['circuit']! as String]!,
        name: row['name']! as String,
        equipment: row['equipment']! as String,
        profile: row['profile']! as String,
      ),
  ];
  PlantAnalysis analysis(String pointId, DateTime day, Map<String, Object?> values) => PlantAnalysis(
    id: plantAnalysisId(pointId, day),
    pointId: pointId,
    date: day,
    values: values,
    source: 'plantSourceLab',
    operatorName: 'Ahmed',
    recordedAt: day,
  );
  return PlantController.seeded(
    PlantState(
      points: points,
      analyses: [
        analysis('pp_c1', today, {'density': 735.0, 'bsw': 0.8, 'water_cut': 0.5, 'salinity': 12.0, 'chlorides': 7.0}),
        for (var d = 1; d < 20; d++)
          analysis('pp_c1', today.subtract(Duration(days: d)), {'density': 730.0 + d % 5, 'bsw': 0.2 + (d % 4) * 0.05}),
        analysis('pp_w1', today, {'ph': 6.8, 'appearance': 'plantAppearanceClear', 'tph': 12.0, 'iron': 0.4}),
        analysis('pp_g3', today, {
          'ch4': 88.2,
          'c2h6': 6.1,
          'c3h8': 2.3,
          'c4plus': 1.1,
          'co2': 1.9,
          'n2': 0.4,
          'h2s': 2.0,
        }),
        analysis('pp_la', today, {'concentration': 45.0, 'ph': 11.2, 'co2_loading': 0.02}),
      ],
      thresholds: const {
        'pp_c1': {'bsw': PlantThreshold(max: 0.5)},
        'pp_g3': {'h2s': PlantThreshold(max: 4)},
      },
      circuits: circuitsById.values.toList(),
      schemas: [
        PlantSchema.builtIn,
        PlantSchema(
          id: 'ps_1',
          name: 'Unité de déshydratation',
          kind: PlantSchemaKind.blank,
          positions: const {'pp_c1': Offset(0.3, 0.4), 'pp_g3': Offset(0.7, 0.2)},
          sortOrder: 2,
        ),
      ],
      customParams: [customPlantParam(key: 'cp_turb', label: 'Turbidité', unit: 'NTU')],
    ),
  );
}

/// Stock : un article en rupture, un en alerte, un correct, avec quelques
/// mouvements d'historique.
StockController _seedStock() {
  final now = DateTime.now();
  const items = [
    StockItem(id: 's1', name: 'Antitartre', unit: 'L', quantity: 0, threshold: 20, category: 'Chimie'),
    StockItem(id: 's2', name: 'Joint torique', unit: 'u', quantity: 8, threshold: 10, category: 'Pièces'),
    StockItem(id: 's3', name: 'Gants nitrile', unit: 'u', quantity: 240, threshold: 50, category: 'EPI'),
  ];
  final movements = [
    StockMovement(id: 'm1', itemId: 's1', delta: 200, operatorName: 'Ahmed', dateTime: now.subtract(const Duration(days: 10))),
    StockMovement(
      id: 'm2',
      itemId: 's1',
      delta: -200,
      wellId: 'w1',
      reason: 'Traitement anti-dépôt',
      operatorName: 'Ahmed',
      dateTime: now.subtract(const Duration(days: 2)),
    ),
    StockMovement(id: 'm3', itemId: 's2', delta: -2, wellId: 'w2', operatorName: 'Sami', dateTime: now.subtract(const Duration(days: 1))),
  ];
  return StockController.seeded(StockState(items: items, movements: movements));
}

/// Force la langue de l'app (`localeProvider`, indépendant du `locale` de
/// `MaterialApp` qui ne pilote que les textes Flutter intégrés).
class _FixedLocale extends LocaleController {
  _FixedLocale(Locale locale) {
    state = locale;
  }
}

class _AdminProfile extends ProfileController {
  _AdminProfile() {
    state = const AppProfile(
      id: 'p',
      fullName: 'Ahmed',
      phone: '',
      serviceKey: 'serviceProduction',
      role: UserRole.admin,
    );
  }
}

Widget _app(
  Widget home,
  WellsState data, {
  bool dark = false,
  PlantView plantView = PlantView.diagram,
  Locale locale = const Locale('fr'),
}) => ProviderScope(
      overrides: [
        wellsControllerProvider.overrideWith((ref) => WellsController.seeded(data)),
        plantControllerProvider.overrideWith((ref) => _seedPlant()),
        stockControllerProvider.overrideWith((ref) => _seedStock()),
        plantViewProvider.overrideWith((ref) => plantView),
        profileProvider.overrideWith((ref) => _AdminProfile()),
        sharedConfigProvider.overrideWith(
          (ref) => SharedConfigController.seeded(const SharedConfig({missingDeadlineKey: '00:00'})),
        ),
        localeProvider.overrideWith((ref) => _FixedLocale(locale)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        locale: locale,
        supportedLocales: supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

Future<void> _render(
  WidgetTester tester,
  Widget home, {
  double height = 844,
  double width = 390,
  bool dark = false,
  PlantView plantView = PlantView.diagram,
  Locale locale = const Locale('fr'),
}) async {
  tester.view.physicalSize = Size(width * 2.0, height * 2.0);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(home, _seed(), dark: dark, plantView: plantView, locale: locale));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('fr');
    await initializeDateFormatting('en');
    DownloadSaver.debugForceSupported = true;
    ReminderService.debugForceSupported = true;
  });

  testWidgets('fiche puits', (t) => _render(t, const WellDetailScreen(wellId: 'w1'), height: 2700));
  testWidgets(
    'fiche puits (anglais)',
    (t) async {
      await _render(t, const WellDetailScreen(wellId: 'w1'), height: 2700, locale: const Locale('en'));
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Analyses'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Interventions'), findsOneWidget);
    },
  );
  testWidgets(
    'historique puits (anglais, pagination)',
    (t) async {
      await _render(t, const WellHistoryScreen(wellId: 'w1'), height: 1800, locale: const Locale('en'));
      expect(find.textContaining('History'), findsWidgets);
      expect(find.textContaining('Page 1 of'), findsOneWidget);
    },
  );
  testWidgets(
    'saisie groupée test de puits (anglais)',
    (t) async {
      await _render(t, const BatchEntryScreen(initialWellId: 'w1'), height: 2000, locale: const Locale('en'));
      expect(find.text('Well test (batch entry)'), findsOneWidget);
      expect(find.text('Start time'), findsOneWidget);
      expect(find.text('End time (optional)'), findsOneWidget);
    },
  );
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
  testWidgets('stock', (t) => _render(t, const StockScreen(), height: 1700));
  testWidgets(
    'stats : courbes superposées',
    (t) => _render(
      t,
      const Scaffold(
        body: SingleChildScrollView(child: WellsOverlayView(filter: WellFilter(period: PeriodSelection.days90))),
      ),
      height: 1200,
    ),
  );
  testWidgets(
    'stats : comparaison de périodes',
    (t) => _render(
      t,
      const Scaffold(body: SingleChildScrollView(child: PeriodComparisonCard(filter: WellFilter(period: PeriodSelection.days30)))),
      height: 700,
    ),
  );
  testWidgets('stock : article en rupture', (t) => _render(t, const StockItemDetailScreen(itemId: 's1'), height: 1500));
  testWidgets('stock : article correct', (t) => _render(t, const StockItemDetailScreen(itemId: 's3'), height: 1200));
  testWidgets('stats', (t) => _render(t, const Scaffold(body: SafeArea(child: StatsScreen())), height: 1100));
  testWidgets('réglages', (t) => _render(t, const SettingsScreen(), height: 2900));
  testWidgets('réglages (sombre)', (t) => _render(t, const SettingsScreen(), height: 2900, dark: true));
  testWidgets(
    'fiche puits (sombre)',
    (t) => _render(t, const WellDetailScreen(wellId: 'w1'), height: 2700, dark: true),
  );
  testWidgets('usine : schéma', (t) => _render(t, const Scaffold(body: SafeArea(child: PlantScreen())), height: 1100));
  testWidgets(
    'usine : liste',
    (t) => _render(
      t,
      const Scaffold(body: SafeArea(child: PlantScreen())),
      height: 2600,
      plantView: PlantView.list,
    ),
  );
  testWidgets(
    'usine : carte thermique',
    (t) => _render(
      t,
      const Scaffold(body: SafeArea(child: PlantScreen())),
      height: 2200,
      plantView: PlantView.heatmap,
    ),
  );
  testWidgets(
    'usine : schéma (sombre)',
    (t) => _render(t, const Scaffold(body: SafeArea(child: PlantScreen())), height: 1100, dark: true),
  );
  testWidgets(
    'usine : courbes',
    (t) => _render(
      t,
      const Scaffold(body: SafeArea(child: PlantScreen())),
      height: 3600,
      plantView: PlantView.trends,
    ),
  );
  testWidgets(
    'usine : configuration du schéma intégré',
    (t) => _render(t, const PlantSchemaEditorScreen(schemaId: 'pfd'), height: 900),
  );
  testWidgets(
    'usine : configuration d\'un schéma vierge',
    (t) => _render(t, const PlantSchemaEditorScreen(schemaId: 'ps_1'), height: 900, width: 1200),
  );
  testWidgets('administration : schémas', (t) => _render(t, const PlantSchemasScreen()));
  testWidgets('administration : paramètres et modèles', (t) => _render(t, const ParamsScreen(), height: 1600));
  testWidgets('usine : fiche point', (t) => _render(t, const PlantPointScreen(pointId: 'pp_c1'), height: 1600));
  testWidgets('usine : saisie gaz export', (t) => _render(t, const PlantEntryScreen(pointId: 'pp_g3'), height: 1700));
  testWidgets('réglages exports PDF : aperçu en direct (téléphone)', (t) async {
    await _render(t, const PdfExportSettingsScreen(), height: 1000);
    expect(find.text('Aperçu en direct'), findsOneWidget);
    for (final kind in ['Échantillons CPI', 'Tableaux', 'Tous les circuits']) {
      await t.tap(find.text(kind));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: kind);
    }
    await t.dragUntilVisible(find.text('Paysage'), find.byType(ListView).last, const Offset(0, -300));
    await t.tap(find.text('Paysage'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'réglages exports PDF : aperçu en direct (grand écran, anglais)',
    (t) async {
      await _render(t, const PdfExportSettingsScreen(), width: 1280, height: 900, locale: const Locale('en'));
      expect(find.text('Live preview'), findsOneWidget);
      await t.tap(find.text('CPI samples'));
      await t.pumpAndSettle();
      expect(find.text('Produced samples from CPI'), findsWidgets, reason: 'titre de la page d\'aperçu');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('usine : saisie eau', (t) => _render(t, const PlantEntryScreen(pointId: 'pp_w1'), height: 1500));
  testWidgets('usine : saisie eau, calcul automatique des hydrocarbures', (t) async {
    await _render(t, const PlantEntryScreen(pointId: 'pp_w1'), height: 1700);
    Future<void> type(String label, String value) async {
      await t.enterText(find.widgetWithText(TextFormField, label), value);
      await t.pump();
    }

    expect(find.textContaining('Renseigne le débit'), findsOneWidget, reason: 'avant la saisie : consigne');
    await type("Débit d'eau produite vers les bassins d'évaporation", '386.6');
    await type('TPH (hydrocarbures)', '4100');
    await type('Densité du condensat', '745.5');
    expect(find.textContaining('1585'), findsWidgets, reason: 'masse en kg/j');
    expect(find.textContaining('2126'), findsWidgets, reason: 'volume en L/j');
    expect(find.textContaining('Renseigne le débit'), findsNothing);
  });
  testWidgets(
    'usine : tendance',
    (t) => _render(t, const PlantTrendScreen(pointId: 'pp_c1', paramKey: 'bsw'), height: 1400),
  );
  // Administration (téléphone puis grand écran).
  testWidgets('admin : accueil', (t) => _render(t, const AdminScreen(), height: 1300));
  testWidgets('admin : accueil (large)', (t) => _render(t, const AdminScreen(), width: 1280, height: 900));
  testWidgets('admin : utilisateurs (mode personnel)', (t) => _render(t, const UsersScreen()));
  testWidgets('admin : puits', (t) => _render(t, const WellsManageScreen(), height: 1000));
  testWidgets('admin : puits (tableau)', (t) => _render(t, const WellsManageScreen(), width: 1280, height: 800));
  testWidgets('admin : formulaire puits', (t) async {
    await _render(t, const WellsManageScreen(), height: 1000);
    await t.tap(find.byType(ListTile).first);
    await t.pumpAndSettle();
    expect(find.text('Latitude'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('admin : points', (t) => _render(t, const SamplePointsScreen(), height: 2600));
  testWidgets('admin : points (tableau)', (t) => _render(t, const SamplePointsScreen(), width: 1280, height: 1400));
  testWidgets('admin : formulaire point', (t) async {
    await _render(t, const SamplePointsScreen(), height: 2600);
    await t.tap(find.text('Ajouter un point'));
    await t.pumpAndSettle();
    expect(find.text('Paramètres analysés'), findsOneWidget);
    final e = t.takeException();
    if (e is FlutterError) debugPrint(e.toStringDeep());
    expect(e, isNull);
  });
  testWidgets('admin : seuils', (t) => _render(t, const ThresholdsScreen(), height: 1900));
  testWidgets('admin : seuils (large)', (t) => _render(t, const ThresholdsScreen(), width: 1280, height: 1300));
  testWidgets('admin : données', (t) => _render(t, const DataAdminScreen(), height: 1300));
  testWidgets('admin : projet Firebase (aucun)', (t) => _render(t, const FirebaseProjectScreen(), height: 1100));
  testWidgets('admin : projet Firebase (configuré)', (t) async {
    SharedPreferences.setMockInitialValues({'firebase_config': jsonEncode(FirebaseRestConfig.builtIn.toJson())});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    await _render(t, const FirebaseProjectScreen(), height: 2000);
    expect(find.text('Fonctions serveur (facultatif)'), findsWidgets);
    expect(find.textContaining('puitstrack'), findsWidgets);
  });
  testWidgets('admin : journal (mode personnel)', (t) => _render(t, const AuditScreen()));
  testWidgets('installation', (t) async {
    await _render(t, const SetupScreen());
    expect(find.text('Rejoindre mon entreprise'), findsOneWidget);
    await t.tap(find.text('Créer mon entreprise'));
    await t.pumpAndSettle();
    expect(find.text("Nom de l'entreprise"), findsOneWidget);
    await t.tap(find.byTooltip('Retour'));
    await t.pumpAndSettle();
    await t.tap(find.text('Rejoindre mon entreprise'));
    await t.pumpAndSettle();
    expect(find.text("Code d'invitation"), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('aujourd hui : mission du jour', (t) async {
    await _render(t, const Scaffold(body: DashboardScreen()), height: 2400);
    expect(find.text('Mission du jour'), findsOneWidget);
    expect(find.text('Saisir'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('code PIN : création', (t) async {
    await _render(t, const PinSetupScreen(), height: 844);
    await t.tap(find.text('1'));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
  });
  testWidgets('inscription locale (profil)', (t) async {
    await _render(t, const ProfileSetupScreen(), height: 844);
    expect(find.byType(TextFormField), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('déverrouillage', (t) async {
    await _render(t, const UnlockScreen(), height: 844);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await t.tap(find.text('1'));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
  });
  testWidgets('QR codes : scan et étiquettes', (t) async {
    await _render(t, const QrScreen(), height: 1200);
    expect(find.text('Scanner un QR code'), findsOneWidget);
    expect(find.text('Générer le PDF'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('alertes (heure limite passée)', (t) async {
    await _render(t, const Scaffold(body: AlertsScreen()), height: 2400);
    expect(find.textContaining('00:00'), findsWidgets);
  });
  // Navigation, chargements.
  testWidgets('accueil : menu latéral (téléphone)', (t) async {
    await _render(t, const HomeShell(), height: 1000);
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    expect(find.text('Outils'), findsOneWidget);
    expect(find.text('Administration'), findsWidgets);
    await t.tap(find.text('Usine').last);
    await t.pumpAndSettle();
    expect(find.text('Outils'), findsNothing, reason: 'menu refermé');
    expect(t.takeException(), isNull);
  });
  testWidgets('accueil : menu latéral réductible (large)', (t) async {
    await _render(t, const HomeShell(), width: 1280, height: 900);
    expect(find.text('Réglages'), findsWidgets);
    await t.tap(find.byTooltip('Réduire le menu'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Agrandir le menu'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('accueil : squelettes pendant le chargement', (t) async {
    t.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        wellsControllerProvider.overrideWith((ref) => WellsController.seeded(WellsState.empty)),
        plantControllerProvider.overrideWith((ref) => PlantController.seeded(PlantState.empty)),
        profileProvider.overrideWith((ref) => _AdminProfile()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('fr'),
        supportedLocales: supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeShell(),
      ),
    ));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(SkeletonPage), findsWidgets);
    expect(find.byType(Shimmer), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('écran de démarrage', (t) async {
    await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const SplashScreen()));
    await t.pump(const Duration(milliseconds: 1200));
    expect(find.text(appDisplayName), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('fenêtre de chargement + transition de page', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              ElevatedButton(
                onPressed: () => runWithLoading(
                  context,
                  'Génération…',
                  () => Future<void>.delayed(const Duration(milliseconds: 300)),
                ),
                child: const Text('charger'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('page 2'))),
                ),
                child: const Text('ouvrir'),
              ),
            ],
          ),
        ),
      ),
    ));
    await t.tap(find.text('charger'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Génération…'), findsOneWidget);
    expect(find.byType(AppLoader), findsOneWidget);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Génération…'), findsNothing, reason: 'fenêtre refermée');
    await t.tap(find.text('ouvrir'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 160));
    expect(find.text('page 2', skipOffstage: false), findsOneWidget, reason: 'transition en cours');
    await t.pumpAndSettle();
    expect(find.text('page 2'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('installation : édition client sans projet intégré', (t) async {
    await _render(
      t,
      Scaffold(body: FirebaseProjectPicker(onSelected: (_) {}, showBuiltIn: false)),
    );
    expect(find.text('Projet PuitsTrack (recommandé)'), findsNothing);
    expect(find.text('Coller la configuration'), findsOneWidget);
  });
  testWidgets('feuille export', (t) async {
    t.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => chooseExport(context, const Locale('fr')),
                child: const Text('go'),
              ),
            ),
          ),
        ),
        _seed(),
      ),
    );
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Télécharger'), findsOneWidget);
    expect(find.text('Partager'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('cloche de notifications : articles en alerte', (t) async {
    t.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      _app(
        Scaffold(appBar: AppBar(actions: const [NotificationBell()]), body: const SizedBox()),
        _seed(),
      ),
    );
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget, reason: 'badge visible : 2 articles en alerte');
    await t.tap(find.byIcon(Icons.notifications_active_rounded));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Stock bas'), findsNWidgets(2));
    expect(find.text('Voir tout'), findsOneWidget);
    expect(t.takeException(), isNull);
    // Laisse le clignotement borné (2.7 s) se terminer pour ne pas finir le
    // test avec un minuteur encore en attente.
    await t.pump(const Duration(seconds: 3));
  });
}
