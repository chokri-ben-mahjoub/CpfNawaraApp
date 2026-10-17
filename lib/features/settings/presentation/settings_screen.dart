import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_info.dart';
import '../../../core/auth/app_lock.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/data/local_database.dart';
import '../../../core/data/stock_repository.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/download_saver.dart';
import '../../../core/export/share_files.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/intervention.dart';
import '../../../core/models/user_role.dart';
import '../../../core/notifications/reminder_service.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/startup_tasks.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/units/unit_system.dart';
import '../../../core/widgets/filter_pills.dart';
import 'sync_section.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/profile_avatar.dart';

/// Réglages de l'app : profil, apparence, sécurité, sauvegarde, rappels,
/// saisie & export, paramétrage, données et à propos.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    String s(String key) => tr(locale, key);

    return Scaffold(
      appBar: AppBar(title: Text(s('settingsTitle'))),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 32),
        children: [
          const _ProfileSection(),
          const SizedBox(height: 16),
          SectionCard(
            title: s('settingsTeam'),
            icon: Icons.cloud_sync_outlined,
            children: const [SyncSettingsContent()],
          ),
          const SizedBox(height: 16),
          const _AppearanceSection(),
          const SizedBox(height: 16),
          const _SecuritySection(),
          const SizedBox(height: 16),
          const _BackupSection(),
          const SizedBox(height: 16),
          const _ReminderSection(),
          const SizedBox(height: 16),
          const _EntrySection(),
          if (role.canConfigure) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: s('adminTitle'),
              icon: Icons.admin_panel_settings_outlined,
              children: [
                _NavTile(
                  icon: Icons.dashboard_customize_outlined,
                  title: s('adminOpen'),
                  subtitle: s('adminOpenHint'),
                  onTap: () => context.push('/admin'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const _DataSection(),
          const SizedBox(height: 16),
          SectionCard(
            title: s('settingsAbout'),
            icon: Icons.info_outline_rounded,
            children: [
              _NavTile(
                icon: Icons.oil_barrel_outlined,
                title: '${s('appName')} · v$appVersion',
                subtitle: s('settingsAboutBody'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- Profil

class _ProfileSection extends ConsumerWidget {
  const _ProfileSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final profile = ref.watch(profileProvider);
    String s(String key) => tr(locale, key);
    final name = profile?.fullName ?? '';

    return SectionCard(
      title: s('settingsProfile'),
      icon: Icons.person_outline,
      children: [
        Row(
          children: [
            const ProfileAvatar(radius: 28, editable: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? s('accountNoName') : name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    [
                      if ((profile?.serviceKey ?? '').isNotEmpty) s(profile!.serviceKey),
                      if ((profile?.phone ?? '').isNotEmpty) profile!.phone,
                    ].join(' · '),
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: profile == null ? null : () => _editProfile(context, ref), child: Text(s('edit'))),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: scheme.error, padding: EdgeInsets.zero),
            onPressed: () => _resetProfile(context, ref),
            icon: const Icon(Icons.logout, size: 18),
            label: Text(s('logout')),
          ),
        ),
      ],
    );
  }

  Future<void> _resetProfile(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s('logout')),
        content: Text(s('settingsResetProfileBody')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s('logout')),
          ),
        ],
      ),
    );
    if (confirmed == true) await ref.read(authServiceProvider).signOut();
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final profile = ref.read(profileProvider)!;
    final nameController = TextEditingController(text: profile.fullName);
    final phoneController = TextEditingController(text: profile.phone);
    var service = serviceKeys.contains(profile.serviceKey) ? profile.serviceKey : null;
    final formKey = GlobalKey<FormState>();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s('settingsEditProfile'),
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: s('signupNameLabel')),
                  validator: (v) => (v ?? '').trim().length < 2 ? s('signupInvalidName') : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: service,
                  decoration: InputDecoration(labelText: s('signupServiceLabel')),
                  items: [for (final key in serviceKeys) DropdownMenuItem(value: key, child: Text(s(key)))],
                  onChanged: (v) => setSheetState(() => service = v),
                  validator: (v) => v == null ? s('signupInvalidService') : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: s('signupPhoneLabel')),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) Navigator.of(sheetContext).pop(true);
                    },
                    child: Text(s('wellsManageSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true) {
      await ref
          .read(profileProvider.notifier)
          .updateProfile(
            fullName: nameController.text.trim(),
            phone: phoneController.text.trim(),
            serviceKey: service!,
          );
    }
    nameController.dispose();
    phoneController.dispose();
  }
}

// --------------------------------------------------------------- Apparence

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(appSettingsProvider.select((st) => st.themeMode));
    String s(String key) => tr(locale, key);

    return SectionCard(
      title: s('settingsAppearance'),
      icon: Icons.palette_outlined,
      children: [
        _Label(s('settingsAppNameLabel')),
        const SizedBox(height: 8),
        const _AppNameField(),
        const SizedBox(height: 6),
        _Hint(s('settingsAppNameHint')),
        const SizedBox(height: 16),
        _Label(s('settingsTheme')),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(s('themeLight')),
                icon: const Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                label: Text(s('themeAuto')),
                icon: const Icon(Icons.brightness_auto_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text(s('themeDark')),
                icon: const Icon(Icons.dark_mode_outlined),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (set) => ref.read(appSettingsProvider.notifier).setThemeMode(set.first),
          ),
        ),
        const SizedBox(height: 6),
        _Hint(s('themeAutoHint')),
        const SizedBox(height: 16),
        _Label(s('unitsTitle')),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<UnitSystem>(
            showSelectedIcon: false,
            segments: [for (final u in UnitSystem.values) ButtonSegment(value: u, label: Text(s(u.labelKey)))],
            selected: {ref.watch(appSettingsProvider.select((st) => st.unitSystem))},
            onSelectionChanged: (set) async {
              await ref.read(appSettingsProvider.notifier).setUnitSystem(set.first);
              await ref.read(wellsControllerProvider.notifier).reload();
              await ref.read(plantControllerProvider.notifier).reload();
            },
          ),
        ),
        const SizedBox(height: 6),
        _Hint(s('unitsHint')),
        const SizedBox(height: 16),
        _Label(s('languageLabel')),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'fr', label: Text('Français')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {locale.languageCode},
            onSelectionChanged: (set) => ref.read(localeProvider.notifier).setLocale(Locale(set.first)),
          ),
        ),
      ],
    );
  }
}

/// Champ de saisie du nom personnalisé de l'app (Réglages › Apparence) :
/// enregistré sur Entrée ou en quittant le champ, pris en compte
/// immédiatement partout où le nom est affiché.
class _AppNameField extends ConsumerStatefulWidget {
  const _AppNameField();

  @override
  ConsumerState<_AppNameField> createState() => _AppNameFieldState();
}

class _AppNameFieldState extends ConsumerState<_AppNameField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(appNameProvider));
    _focusNode = FocusNode()..addListener(() {
      if (!_focusNode.hasFocus) _save();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _save() {
    final locale = ref.read(localeProvider);
    ref.read(appNameProvider.notifier).setName(_controller.text);
    // Champ vide : redescend sur le nom par défaut, affiché pour confirmer.
    _controller.text = ref.read(appNameProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(locale, 'settingsAppNameSaved'))));
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        hintText: appDisplayName,
        prefixIcon: const Icon(Icons.badge_outlined),
        suffixIcon: IconButton(
          tooltip: tr(locale, 'adminSave'),
          icon: const Icon(Icons.check),
          onPressed: _save,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Sécurité

const _autoLockOptions = [0, 30, 60, 300, 900];

String _autoLockLabel(int seconds, String Function(String) s) {
  if (seconds == 0) return s('autoLockImmediate');
  if (seconds < 60) return '$seconds s';
  return '${seconds ~/ 60} min';
}

class _SecuritySection extends ConsumerWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    String s(String key) => tr(locale, key);

    return SectionCard(
      title: s('settingsSecurity'),
      icon: Icons.lock_outline_rounded,
      children: [
        FutureBuilder<bool>(
          future: BiometricAuth.isAvailable,
          builder: (context, snapshot) {
            final available = snapshot.data ?? false;
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.fingerprint),
              title: Text(s('settingsBiometric')),
              subtitle: Text(available ? s('settingsBiometricHint') : s('settingsBiometricUnavailable')),
              value: settings.biometricEnabled && available,
              activeTrackColor: accentColor,
              onChanged: available ? controller.setBiometricEnabled : null,
            );
          },
        ),
        _NavTile(icon: Icons.pin_outlined, title: s('accountChangePin'), onTap: () => context.push('/pin-setup')),
        _NavTile(
          icon: Icons.timer_outlined,
          title: s('settingsAutoLock'),
          subtitle: s('settingsAutoLockHint'),
          bottom: FilterPill<int>(
            icon: Icons.lock_clock_outlined,
            title: s('settingsAutoLock'),
            options: [for (final sec in _autoLockOptions) PillOption(sec, _autoLockLabel(sec, s))],
            selected: _autoLockOptions.contains(settings.autoLockSeconds) ? settings.autoLockSeconds : 0,
            onSelected: controller.setAutoLockSeconds,
          ),
        ),
        if (DownloadSaver.supportsSecureScreen)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.screenshot_monitor_outlined),
            title: Text(s('settingsSecureScreen')),
            subtitle: Text(s('settingsSecureScreenHint')),
            value: settings.secureScreen,
            activeTrackColor: accentColor,
            onChanged: (v) async {
              await controller.setSecureScreen(v);
              await DownloadSaver.setSecureScreen(v);
            },
          ),
      ],
    );
  }
}

// --------------------------------------------------------------- Sauvegarde

class _BackupSection extends ConsumerStatefulWidget {
  const _BackupSection();

  @override
  ConsumerState<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<_BackupSection> {
  bool _busy = false;

  String s(String key) => tr(ref.read(localeProvider), key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final settings = ref.watch(appSettingsProvider);
    String t(String key) => tr(locale, key);

    final last = settings.lastBackupAt;
    final age = last == null ? null : DateTime.now().difference(last).inDays;
    final stale = last == null || age! >= 7;
    final lastLabel = last == null
        ? t('backupNever')
        : '${DateFormat('d MMM yyyy, HH:mm', locale.languageCode).format(last)}'
              ' (${age == 0 ? t('backupToday') : fill(t('backupDaysAgo'), {'n': '$age'})})';

    return SectionCard(
      title: t('settingsBackup'),
      icon: Icons.backup_outlined,
      children: [
        _Hint(t('backupIntro')),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (stale ? scheme.error : Colors.green.shade600).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                stale ? Icons.warning_amber_rounded : Icons.verified_outlined,
                color: stale ? scheme.error : Colors.green.shade600,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${t('backupLast')} : $lastLabel',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (DownloadSaver.isSupported) ...[
          _ActionButton(
            icon: Icons.download_rounded,
            label: t(isAndroid ? 'backupSaveToPhone' : 'backupDownload'),
            busy: _busy,
            filled: true,
            onPressed: _saveToPhone,
          ),
          const SizedBox(height: 8),
        ],
        _ActionButton(icon: Icons.ios_share_outlined, label: t('backupShare'), busy: _busy, onPressed: _share),
        const SizedBox(height: 8),
        _ActionButton(
          icon: Icons.settings_backup_restore,
          label: t('backupRestore'),
          busy: _busy,
          danger: true,
          onPressed: _restore,
        ),
        if (DownloadSaver.supportsAutoBackup) ...[
          const Divider(height: 28),
          _NavTile(
            icon: Icons.autorenew,
            title: t('autoBackupTitle'),
            subtitle: t('autoBackupHint'),
            bottom: FilterPill<AutoBackupFrequency>(
              icon: Icons.event_repeat,
              title: t('autoBackupTitle'),
              options: [for (final f in AutoBackupFrequency.values) PillOption(f, t(f.labelKey))],
              selected: settings.autoBackup,
              active: settings.autoBackup != AutoBackupFrequency.off,
              onSelected: ref.read(appSettingsProvider.notifier).setAutoBackup,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToPhone() => _run(() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await LockGuard.run(
        () async => DownloadSaver.save(
          fileName: BackupService.fileName(DateTime.now()),
          mimeType: backupMimeType,
          bytes: await BackupService.encode(),
          subFolder: backupFolder,
        ),
      );
      await ref.read(appSettingsProvider.notifier).markBackupDone(automatic: false);
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('${s(isWeb ? 'backupDownloaded' : 'backupSaved')}\n${file.fileName}'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s('backupFailed'))));
    }
  });

  Future<void> _share() => _run(() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await shareFiles([
        ShareableFile(BackupService.fileName(DateTime.now()), backupMimeType, await BackupService.encode()),
      ], subject: s('backupShareSubject'));
      if (result.status != ShareResultStatus.dismissed) {
        await ref.read(appSettingsProvider.notifier).markBackupDone(automatic: false);
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s('backupFailed'))));
    }
  });

  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    final locale = ref.read(localeProvider);
    final FilePickerResult? picked;
    try {
      picked = await LockGuard.run(() => FilePicker.platform.pickFiles(type: FileType.any, withData: true));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s('backupErrorNotJson'))));
      return;
    }
    final bytes = picked?.files.single.bytes;
    if (bytes == null || !mounted) return;

    final BackupPayload payload;
    try {
      payload = BackupService.parse(_decodeUtf8(bytes));
    } on InvalidBackupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s(e.messageKey))));
      return;
    }

    final date = payload.exportedAt == null
        ? '—'
        : DateFormat('d MMM yyyy, HH:mm', locale.languageCode).format(payload.exportedAt!);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s('backupRestoreConfirmTitle')),
        content: Text(
          fill(s('backupRestoreConfirmBody'), {
            'date': date,
            'wells': '${payload.count('wells')}',
            'records': '${payload.count('analysis_records')}',
            'interventions': '${payload.count('interventions')}',
          }),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s('backupRestoreConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      try {
        // Filet de sécurité : copie des données actuelles avant de les
        // remplacer (Téléchargements/PuitsTrack/Sauvegardes).
        if (DownloadSaver.supportsAutoBackup && await BackupService.recordCount() > 0) {
          try {
            await DownloadSaver.save(
              fileName: 'puitstrack_avant_restauration.json',
              mimeType: backupMimeType,
              bytes: await BackupService.encode(),
              subFolder: backupFolder,
              overwrite: true,
              requestPermission: false,
            );
          } catch (_) {}
        }
        await BackupService.restore(payload);
        await ref.read(wellsControllerProvider.notifier).reload();
        await ref.read(plantControllerProvider.notifier).reload();
        await ref.read(stockControllerProvider.notifier).reload();
        await refreshReminders(ref);
        messenger.showSnackBar(SnackBar(content: Text(s('backupRestored'))));
      } catch (_) {
        messenger.showSnackBar(SnackBar(content: Text(s('backupRestoreFailed'))));
      }
    });
  }

  static String _decodeUtf8(List<int> bytes) {
    final text = const Utf8Codec(allowMalformed: true).decode(bytes);
    return text.startsWith('﻿') ? text.substring(1) : text;
  }
}

// ------------------------------------------------------------------ Rappels

class _ReminderSection extends ConsumerWidget {
  const _ReminderSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final settings = ref.watch(appSettingsProvider);
    String s(String key) => tr(locale, key);
    if (!ReminderService.isSupported) return const SizedBox.shrink();

    Future<void> apply(bool enabled, TimeOfDay time) async {
      await ref.read(appSettingsProvider.notifier).setDailyReminder(enabled, time: time);
      await refreshReminders(ref);
    }

    return SectionCard(
      title: s('settingsReminders'),
      icon: Icons.notifications_active_outlined,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s('reminderDaily')),
          subtitle: Text(s('reminderDailyHint')),
          value: settings.dailyReminder,
          activeTrackColor: accentColor,
          onChanged: (v) async {
            if (v) {
              final granted = await ReminderService.requestPermission(s('reminderChannelName'));
              if (!granted) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('reminderPermissionDenied'))));
                }
                return;
              }
            }
            await apply(v, settings.reminderTime);
          },
        ),
        _NavTile(
          icon: Icons.schedule,
          title: s('reminderTime'),
          trailing: Text(
            settings.reminderTime.format(context),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: settings.dailyReminder ? accentColor : Theme.of(context).colorScheme.outline,
            ),
          ),
          onTap: settings.dailyReminder
              ? () async {
                  final picked = await showTimePicker(context: context, initialTime: settings.reminderTime);
                  if (picked != null) await apply(true, picked);
                }
              : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- Saisie & export

class _EntrySection extends ConsumerWidget {
  const _EntrySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    String s(String key) => tr(locale, key);

    return SectionCard(
      title: s('settingsEntryExport'),
      icon: Icons.edit_note,
      children: [
        _NavTile(
          icon: Icons.groups_outlined,
          title: s('settingsDefaultService'),
          subtitle: s('settingsDefaultServiceHint'),
          bottom: FilterPill<String>(
            icon: Icons.badge_outlined,
            title: s('settingsDefaultService'),
            options: [
              PillOption(defaultServiceFromProfile, s('settingsServiceFromProfile')),
              PillOption(defaultServiceNone, s('settingsServiceNone')),
              for (final key in serviceKeys) PillOption(key, s(key)),
            ],
            selected: settings.defaultService,
            onSelected: controller.setDefaultService,
          ),
        ),
        _NavTile(
          icon: Icons.payments_outlined,
          title: s('settingsDefaultCurrency'),
          subtitle: s('settingsDefaultCurrencyHint'),
          bottom: FilterPill<String>(
            icon: Icons.currency_exchange,
            title: s('settingsDefaultCurrency'),
            options: [for (final c in interventionCurrencies) PillOption(c, c)],
            selected: settings.defaultCurrency,
            onSelected: controller.setDefaultCurrency,
          ),
        ),
        _NavTile(
          icon: Icons.description_outlined,
          title: s('settingsCsvFormat'),
          subtitle: s(settings.csvInternational ? 'csvFormatIntlHint' : 'csvFormatFrHint'),
          bottom: FilterPill<bool>(
            icon: Icons.table_rows_outlined,
            title: s('settingsCsvFormat'),
            options: [PillOption(false, s('csvFormatFr')), PillOption(true, s('csvFormatIntl'))],
            selected: settings.csvInternational,
            onSelected: controller.setCsvInternational,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Données

class _DataSection extends ConsumerWidget {
  const _DataSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final data = ref.watch(wellsControllerProvider);
    String s(String key) => tr(locale, key);
    final number = NumberFormat.decimalPattern(locale.languageCode);

    return SectionCard(
      title: s('settingsData'),
      icon: Icons.storage_outlined,
      children: [
        _Hint(s(isWeb ? 'settingsDataHintWeb' : (isDesktop ? 'settingsDataHintDesktop' : 'settingsDataHint'))),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Counter(label: s('navWells'), value: number.format(data.wells.length)),
            ),
            Expanded(
              child: _Counter(label: s('exportSheetAnalyses'), value: number.format(data.records.length)),
            ),
            Expanded(
              child: _Counter(label: s('interventionsTitle'), value: number.format(data.interventions.length)),
            ),
          ],
        ),
        if (!isWeb) ...[
          const SizedBox(height: 10),
          FutureBuilder<int>(
            future: () async {
              final path = await LocalDatabase.instance.path;
              final file = File(path);
              return await file.exists() ? await file.length() : 0;
            }(),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              final size = bytes == null
                  ? '…'
                  : bytes < 1024 * 1024
                  ? '${(bytes / 1024).toStringAsFixed(0)} Ko'
                  : '${(bytes / 1024 / 1024).toStringAsFixed(1)} Mo';
              return _Hint('${s('settingsDbSize')} : $size');
            },
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ Widgets

/// Bloc de réglages (titre + icône + contenu), repris du style de
/// mobile-locations.
class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const SectionCard({super.key, required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Material (et non un Container décoré) : les interrupteurs et lignes
    // cliquables y dessinent leur effet de toucher.
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18, color: accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Contrôle affiché sous le texte (ex: liste de choix), pour garder de la
  /// place au libellé sur un écran étroit.
  final Widget? bottom;
  final VoidCallback? onTap;

  const _NavTile({required this.icon, required this.title, this.subtitle, this.trailing, this.bottom, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Row(
      children: [
        Icon(icon, color: scheme.onSurfaceVariant, size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              if (bottom != null) ...[const SizedBox(height: 8), bottom!],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        if (trailing == null && onTap != null) Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      ],
    );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: content),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final bool filled;
  final bool danger;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
    this.filled = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = Text(label, style: const TextStyle(fontWeight: FontWeight.w700));
    final iconWidget = busy
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(icon);
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: filled
          ? FilledButton.icon(
              onPressed: busy ? null : onPressed,
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              icon: iconWidget,
              label: child,
            )
          : OutlinedButton.icon(
              onPressed: busy ? null : onPressed,
              style: danger
                  ? OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
                    )
                  : null,
              icon: iconWidget,
              label: child,
            ),
    );
  }
}

class _Counter extends StatelessWidget {
  final String label;
  final String value;
  const _Counter({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13));
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35));
}
