import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../export/csv_exporter.dart';

enum AutoBackupFrequency { off, daily, weekly }

extension AutoBackupFrequencyX on AutoBackupFrequency {
  String get labelKey {
    switch (this) {
      case AutoBackupFrequency.off:
        return 'autoBackupOff';
      case AutoBackupFrequency.daily:
        return 'autoBackupDaily';
      case AutoBackupFrequency.weekly:
        return 'autoBackupWeekly';
    }
  }

  Duration? get interval {
    switch (this) {
      case AutoBackupFrequency.off:
        return null;
      case AutoBackupFrequency.daily:
        return const Duration(days: 1);
      case AutoBackupFrequency.weekly:
        return const Duration(days: 7);
    }
  }
}

/// Valeur spéciale de [AppSettings.defaultService] : reprendre le service
/// du profil.
const defaultServiceFromProfile = 'profile';

/// Valeur spéciale de [AppSettings.defaultService] : aucun service
/// pré-sélectionné (à choisir à chaque saisie).
const defaultServiceNone = 'none';

/// Réglages de l'app, propres à l'appareil (SharedPreferences) — distincts
/// des données (puits, analyses...) qui sont dans la base locale.
class AppSettings {
  final ThemeMode themeMode;

  // Sécurité
  final bool biometricEnabled;

  /// Délai avant reverrouillage une fois l'app en arrière-plan (0 = immédiat).
  final int autoLockSeconds;

  /// Masque l'app dans les applications récentes et bloque les captures
  /// d'écran (Android FLAG_SECURE).
  final bool secureScreen;

  // Sauvegarde
  final AutoBackupFrequency autoBackup;
  final DateTime? lastBackupAt;
  final DateTime? lastAutoBackupAt;

  // Rappels
  final bool dailyReminder;
  final int reminderHour;
  final int reminderMinute;

  // Saisie & export
  /// `profile`, `none`, ou une clé de service (voir `serviceKeys`).
  final String defaultService;
  final String defaultCurrency;

  /// CSV "international" (séparateur `,`, point décimal) au lieu du format
  /// Excel FR (séparateur `;`, virgule décimale).
  final bool csvInternational;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.biometricEnabled = true,
    this.autoLockSeconds = 0,
    this.secureScreen = false,
    this.autoBackup = AutoBackupFrequency.weekly,
    this.lastBackupAt,
    this.lastAutoBackupAt,
    this.dailyReminder = false,
    this.reminderHour = 8,
    this.reminderMinute = 0,
    this.defaultService = defaultServiceFromProfile,
    this.defaultCurrency = 'TND',
    this.csvInternational = false,
  });

  TimeOfDay get reminderTime => TimeOfDay(hour: reminderHour, minute: reminderMinute);

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? biometricEnabled,
    int? autoLockSeconds,
    bool? secureScreen,
    AutoBackupFrequency? autoBackup,
    DateTime? lastBackupAt,
    DateTime? lastAutoBackupAt,
    bool? dailyReminder,
    int? reminderHour,
    int? reminderMinute,
    String? defaultService,
    String? defaultCurrency,
    bool? csvInternational,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
        secureScreen: secureScreen ?? this.secureScreen,
        autoBackup: autoBackup ?? this.autoBackup,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
        lastAutoBackupAt: lastAutoBackupAt ?? this.lastAutoBackupAt,
        dailyReminder: dailyReminder ?? this.dailyReminder,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
        defaultService: defaultService ?? this.defaultService,
        defaultCurrency: defaultCurrency ?? this.defaultCurrency,
        csvInternational: csvInternational ?? this.csvInternational,
      );
}

const _kTheme = 'settings_theme_mode';
const _kBiometric = 'settings_biometric';
const _kAutoLock = 'settings_auto_lock_seconds';
const _kSecure = 'settings_secure_screen';
const _kAutoBackup = 'settings_auto_backup';
const _kLastBackup = 'settings_last_backup_at';
const _kLastAutoBackup = 'settings_last_auto_backup_at';
const _kReminder = 'settings_daily_reminder';
const _kReminderHour = 'settings_reminder_hour';
const _kReminderMinute = 'settings_reminder_minute';
const _kDefaultService = 'settings_default_service';
const _kCurrency = 'settings_default_currency';
const _kCsvIntl = 'settings_csv_international';

class AppSettingsController extends StateNotifier<AppSettings> {
  AppSettingsController() : super(const AppSettings()) {
    _ready = load();
  }

  late final Future<void> _ready;

  /// Terminé une fois les réglages relus (utile avant une décision prise
  /// au démarrage : sauvegarde automatique, rappels...).
  Future<void> get ready => _ready;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    DateTime? date(String key) {
      final v = p.getString(key);
      return v == null ? null : DateTime.tryParse(v);
    }

    state = AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == p.getString(_kTheme),
        orElse: () => ThemeMode.system,
      ),
      biometricEnabled: p.getBool(_kBiometric) ?? true,
      autoLockSeconds: p.getInt(_kAutoLock) ?? 0,
      secureScreen: p.getBool(_kSecure) ?? false,
      autoBackup: AutoBackupFrequency.values.firstWhere(
        (f) => f.name == p.getString(_kAutoBackup),
        orElse: () => AutoBackupFrequency.weekly,
      ),
      lastBackupAt: date(_kLastBackup),
      lastAutoBackupAt: date(_kLastAutoBackup),
      dailyReminder: p.getBool(_kReminder) ?? false,
      reminderHour: p.getInt(_kReminderHour) ?? 8,
      reminderMinute: p.getInt(_kReminderMinute) ?? 0,
      defaultService: p.getString(_kDefaultService) ?? defaultServiceFromProfile,
      defaultCurrency: p.getString(_kCurrency) ?? 'TND',
      csvInternational: p.getBool(_kCsvIntl) ?? false,
    );
    CsvExporter.international = state.csvInternational;
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await (await _prefs).setString(_kTheme, mode.name);
  }

  Future<void> setBiometricEnabled(bool value) async {
    state = state.copyWith(biometricEnabled: value);
    await (await _prefs).setBool(_kBiometric, value);
  }

  Future<void> setAutoLockSeconds(int value) async {
    state = state.copyWith(autoLockSeconds: value);
    await (await _prefs).setInt(_kAutoLock, value);
  }

  Future<void> setSecureScreen(bool value) async {
    state = state.copyWith(secureScreen: value);
    await (await _prefs).setBool(_kSecure, value);
  }

  Future<void> setAutoBackup(AutoBackupFrequency value) async {
    state = state.copyWith(autoBackup: value);
    await (await _prefs).setString(_kAutoBackup, value.name);
  }

  Future<void> markBackupDone({required bool automatic}) async {
    final now = DateTime.now();
    state = automatic
        ? state.copyWith(lastBackupAt: now, lastAutoBackupAt: now)
        : state.copyWith(lastBackupAt: now);
    final p = await _prefs;
    await p.setString(_kLastBackup, now.toIso8601String());
    if (automatic) await p.setString(_kLastAutoBackup, now.toIso8601String());
  }

  Future<void> setDailyReminder(bool enabled, {TimeOfDay? time}) async {
    state = state.copyWith(
      dailyReminder: enabled,
      reminderHour: time?.hour,
      reminderMinute: time?.minute,
    );
    final p = await _prefs;
    await p.setBool(_kReminder, enabled);
    await p.setInt(_kReminderHour, state.reminderHour);
    await p.setInt(_kReminderMinute, state.reminderMinute);
  }

  Future<void> setDefaultService(String value) async {
    state = state.copyWith(defaultService: value);
    await (await _prefs).setString(_kDefaultService, value);
  }

  Future<void> setDefaultCurrency(String value) async {
    state = state.copyWith(defaultCurrency: value);
    await (await _prefs).setString(_kCurrency, value);
  }

  Future<void> setCsvInternational(bool value) async {
    state = state.copyWith(csvInternational: value);
    CsvExporter.international = value;
    await (await _prefs).setBool(_kCsvIntl, value);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsController, AppSettings>((ref) => AppSettingsController());
