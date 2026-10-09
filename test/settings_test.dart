import 'dart:convert';

import 'package:puitstrack/core/backup/backup_service.dart';
import 'package:puitstrack/core/data/local_database.dart';
import 'package:puitstrack/core/export/csv_exporter.dart';
import 'package:puitstrack/core/export/export_table.dart';
import 'package:puitstrack/core/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _backup({Object? app = 'PuitsTrack', Object? version = 5, Map<String, Object?>? tables}) => jsonEncode({
      'app': app,
      'schemaVersion': version,
      'exportedAt': '2026-10-09T14:30:00.000',
      'tables': tables ??
          {
            'wells': [
              {'id': 'w1', 'code': 'PN-01', 'name': 'Puits Nord 1', 'active': 1, 'group_name': 'Zone Nord'},
            ],
            'analysis_types': [
              {'id': 't_bsw', 'label': 'BSW', 'unit': '%', 'min_value': 0, 'max_value': 2, 'frequency': 'daily'},
            ],
            'analysis_records': [
              {'id': 'r1', 'well_id': 'w1', 'type_id': 't_bsw', 'value': 1.2},
            ],
          },
    });

void main() {
  group('Lecture d\'une sauvegarde', () {
    test('sauvegarde valide : compteurs et date', () {
      final payload = BackupService.parse(_backup());
      expect(payload.count('wells'), 1);
      expect(payload.count('analysis_records'), 1);
      // Table absente (sauvegarde d'une version sans interventions) → vide.
      expect(payload.count('interventions'), 0);
      expect(payload.exportedAt, DateTime(2026, 10, 9, 14, 30));
    });

    test('fichiers refusés avec le bon message', () {
      Matcher fails(String key) =>
          throwsA(isA<InvalidBackupException>().having((e) => e.messageKey, 'messageKey', key));
      expect(() => BackupService.parse('pas du json'), fails('backupErrorNotJson'));
      expect(() => BackupService.parse(_backup(app: 'LocaTrack')), fails('backupErrorNotPuitsTrack'));
      expect(
        () => BackupService.parse(_backup(version: LocalDatabase.schemaVersion + 1)),
        fails('backupErrorTooRecent'),
      );
      expect(() => BackupService.parse(_backup(tables: {'wells': 'x'})), fails('backupErrorCorrupted'));
      expect(() => BackupService.parse(_backup(tables: {})), fails('backupErrorEmpty'));
    });

    test('nom de fichier daté', () {
      expect(BackupService.fileName(DateTime(2026, 1, 5, 7, 3)), 'puitstrack_sauvegarde_20260105_0703.json');
    });
  });

  group('Réglages', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => CsvExporter.international = false);

    test('valeurs par défaut', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.notifier).ready;
      final s = container.read(appSettingsProvider);
      expect(s.themeMode, ThemeMode.system);
      expect(s.biometricEnabled, isTrue);
      expect(s.autoLockSeconds, 0);
      expect(s.autoBackup, AutoBackupFrequency.weekly);
      expect(s.dailyReminder, isFalse);
      expect(s.defaultService, defaultServiceFromProfile);
    });

    test('les réglages sont conservés', () async {
      final firstContainer = ProviderContainer();
      addTearDown(firstContainer.dispose);
      final first = firstContainer.read(appSettingsProvider.notifier);
      await first.ready;
      await first.setThemeMode(ThemeMode.dark);
      await first.setAutoLockSeconds(300);
      await first.setDailyReminder(true, time: const TimeOfDay(hour: 7, minute: 30));
      await first.setCsvInternational(true);
      await first.markBackupDone(automatic: true);

      final second = ProviderContainer();
      addTearDown(second.dispose);
      await second.read(appSettingsProvider.notifier).ready;
      final s = second.read(appSettingsProvider);
      expect(s.themeMode, ThemeMode.dark);
      expect(s.autoLockSeconds, 300);
      expect(s.dailyReminder, isTrue);
      expect(s.reminderTime, const TimeOfDay(hour: 7, minute: 30));
      expect(s.csvInternational, isTrue);
      expect(s.lastAutoBackupAt, isNotNull);
      expect(s.lastBackupAt, isNotNull);
    });

    test('CSV international : virgule et point décimal', () {
      CsvExporter.international = true;
      final text = utf8.decode(CsvExporter.encode(const ExportTable(
        name: 't',
        headers: ['Puits', 'Valeur'],
        rows: [
          ['A, B', 1.5],
        ],
      )).skip(3).toList());
      expect(text.split('\n')[1].trim(), '"A, B",1.5');
    });
  });
}
