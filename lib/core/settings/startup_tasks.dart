import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_providers.dart';
import '../backup/backup_service.dart';
import '../data/wells_repository.dart';
import '../export/download_saver.dart';
import '../l10n/app_strings.dart';
import '../notifications/reminder_service.dart';
import '../sync/sync_service.dart';
import 'app_settings.dart';

const _autoBackupSlotKey = 'settings_auto_backup_slot';

/// Tâches lancées à l'ouverture de l'app et à chaque retour au premier plan :
/// écran protégé, rappels de saisie, sauvegarde automatique si elle est due.
/// Toutes sont "best-effort" : un échec ne bloque jamais l'app.
Future<void> onAppForeground(WidgetRef ref) async {
  final settingsController = ref.read(appSettingsProvider.notifier);
  await settingsController.ready;
  final settings = ref.read(appSettingsProvider);
  await DownloadSaver.setSecureScreen(settings.secureScreen);
  await ref.read(wellsControllerProvider.notifier).loaded;
  // Récupère les saisies faites sur les autres appareils (sans bloquer).
  unawaited(ref.read(syncControllerProvider.notifier).syncNow());
  await refreshReminders(ref);
  await runAutoBackupIfDue(ref);
}

/// Reprogramme le rappel quotidien ; le rappel du jour est sauté si toutes
/// les analyses attendues aujourd'hui sont déjà saisies.
Future<void> refreshReminders(WidgetRef ref) async {
  try {
    final settings = ref.read(appSettingsProvider);
    final locale = ref.read(localeProvider);
    final data = ref.read(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    var done = 0;
    var total = 0;
    for (final well in data.wells.where((w) => w.active)) {
      final (d, t) = controller.todayProgress(well.id);
      done += d;
      total += t;
    }
    await ReminderService.reschedule(
      enabled: settings.dailyReminder && ref.read(sessionAuthenticatedProvider),
      time: settings.reminderTime,
      skipToday: total > 0 && done >= total,
      channelName: s('reminderChannelName'),
      title: s('reminderTitle'),
      body: s('reminderBody'),
      // Rappel du jour : un seul message avec le nombre restant à saisir.
      bodyToday: total > done ? fill(s('reminderBodyCount'), {'n': '${total - done}'}) : null,
    );
  } catch (_) {
    // Notifications indisponibles (permission refusée, plateforme...) :
    // sans conséquence sur le reste de l'app.
  }
}

/// Enregistre une sauvegarde dans Téléchargements/PuitsTrack/Sauvegardes si
/// la sauvegarde automatique est activée et que la dernière date d'au moins
/// l'intervalle choisi. Deux fichiers sont utilisés à tour de rôle (A/B) :
/// le précédent reste disponible si le dernier a été pris après une erreur.
Future<bool> runAutoBackupIfDue(WidgetRef ref, {bool force = false}) async {
  final settings = ref.read(appSettingsProvider);
  final interval = settings.autoBackup.interval;
  if (!DownloadSaver.supportsAutoBackup || (interval == null && !force)) return false;
  final last = settings.lastAutoBackupAt;
  if (!force && last != null && DateTime.now().difference(last) < interval!) return false;
  try {
    if (await BackupService.recordCount() == 0) return false;
    final prefs = await SharedPreferences.getInstance();
    final slot = prefs.getString(_autoBackupSlotKey) == 'A' ? 'B' : 'A';
    await DownloadSaver.save(
      fileName: 'puitstrack_auto_$slot.json',
      mimeType: backupMimeType,
      bytes: await BackupService.encode(),
      subFolder: backupFolder,
      overwrite: true,
      requestPermission: false,
    );
    await prefs.setString(_autoBackupSlotKey, slot);
    await ref.read(appSettingsProvider.notifier).markBackupDone(automatic: true);
    return true;
  } catch (_) {
    return false;
  }
}
