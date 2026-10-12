import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/sync/firebase_config_provider.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../setup/presentation/widgets/firebase_project_picker.dart';
import '../../setup/presentation/widgets/team_account_form.dart';

/// Icône d'état de la synchronisation (barre du haut), affichée seulement
/// quand un compte est connecté.
class SyncStatusIcon extends ConsumerWidget {
  final VoidCallback onTap;
  const SyncStatusIcon({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final locale = ref.watch(localeProvider);
    if (!sync.isSignedIn) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (sync.phase) {
      SyncPhase.syncing => (Icons.cloud_sync_outlined, accentColor),
      SyncPhase.offline => (Icons.cloud_off_outlined, scheme.onSurfaceVariant),
      SyncPhase.error => (Icons.sync_problem_outlined, scheme.error),
      _ => (Icons.cloud_done_outlined, Colors.green.shade600),
    };
    return IconButton(
      tooltip: tr(locale, syncPhaseLabelKey(sync.phase)),
      icon: Icon(icon, color: color),
      onPressed: onTap,
    );
  }
}

String syncPhaseLabelKey(SyncPhase phase) => switch (phase) {
  SyncPhase.syncing => 'syncStateSyncing',
  SyncPhase.offline => 'syncStateOffline',
  SyncPhase.error => 'syncStateError',
  SyncPhase.idle => 'syncStateIdle',
  SyncPhase.signedOut => 'syncStateSignedOut',
};

/// Petite étiquette de rôle (Admin, Ingénieur...).
class RoleChip extends ConsumerWidget {
  final UserRole role;
  final bool active;
  const RoleChip({super.key, required this.role, this.active = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final color = !active
        ? scheme.outline
        : switch (role) {
            UserRole.admin => accentColor,
            UserRole.engineer => const Color(0xFF1E88E5),
            UserRole.operator => const Color(0xFF2E9E5B),
            UserRole.reader => scheme.onSurfaceVariant,
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(100)),
      child: Text(
        tr(locale, role.labelKey),
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5),
      ),
    );
  }
}

/// Contenu de la section "Équipe et synchronisation" des Réglages.
class SyncSettingsContent extends ConsumerWidget {
  const SyncSettingsContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final config = ref.watch(firebaseConfigProvider);
    final sync = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final hint = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.35);

    if (config == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s('syncIntro'), style: hint),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              onPressed: () => showFirebaseProjectSheet(context),
              icon: const Icon(Icons.cloud_outlined),
              label: Text(s('syncConnectProject'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      );
    }

    if (!sync.isSignedIn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s('syncIntro'), style: hint),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              onPressed: () => showTeamFormSheet(context, TeamFormMode.create),
              icon: const Icon(Icons.add_business_outlined),
              label: Text(s('companyCreateTitle'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => showTeamFormSheet(context, TeamFormMode.join),
              icon: const Icon(Icons.group_add_outlined),
              label: Text(s('companyJoinTitle'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => showTeamFormSheet(context, TeamFormMode.signIn),
            icon: const Icon(Icons.login, size: 18),
            label: Text(s('setupModeSignIn')),
          ),
          if (ref.watch(firebaseConfigProvider.notifier).isCustom)
            Text('${s('setupProject')} : ${config.projectId}', style: hint, textAlign: TextAlign.center),
        ],
      );
    }

    final last = sync.lastSyncAt;
    final when = last == null ? s('syncNever') : DateFormat('d MMM, HH:mm', locale.languageCode).format(last);
    final statusColor = switch (sync.phase) {
      SyncPhase.error => scheme.error,
      SyncPhase.offline => scheme.onSurfaceVariant,
      _ => Colors.green.shade700,
    };
    final member = sync.member;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.account_circle_outlined, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sync.company?.name.isNotEmpty == true ? sync.company!.name : (sync.email ?? ''),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    sync.company?.name.isNotEmpty == true ? (sync.email ?? '') : '',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (member != null) RoleChip(role: member.role, active: member.active),
          ],
        ),
        const SizedBox(height: 10),
        const MemberStatusBanner(),
        if (sync.memberStatus == MemberStatus.active || sync.memberStatus == MemberStatus.unknown)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                if (sync.phase == SyncPhase.syncing)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(
                    sync.phase == SyncPhase.error
                        ? Icons.sync_problem_outlined
                        : sync.phase == SyncPhase.offline
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_done_outlined,
                    color: statusColor,
                    size: 20,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s(syncPhaseLabelKey(sync.phase)),
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: statusColor),
                      ),
                      Text('${s('syncLast')} : $when', style: const TextStyle(fontSize: 12)),
                      if (sync.errorKey != null && sync.phase != SyncPhase.idle)
                        Text(s(sync.errorKey!), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (sync.errorKey == 'syncErrorRules' || sync.errorKey == 'syncErrorDatabase') ...[
          const SizedBox(height: 10),
          ProjectProblemCard(
            problem: sync.errorKey == 'syncErrorRules'
                ? ProjectProblem.rulesNotPublished
                : ProjectProblem.databaseMissing,
            config: config,
          ),
        ],
        const SizedBox(height: 10),
        Text(s('syncAutoHint'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.35)),
        if (controller.isOwner) ...[
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storefront_outlined, color: accentColor),
            title: Text(s('ownerTitle'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(s('ownerEntryHint')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/owner'),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: sync.phase == SyncPhase.syncing ? null : controller.syncNow,
                icon: const Icon(Icons.sync),
                label: Text(s('syncNow')),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Text(s('syncSignOutTitle')),
                    content: Text(s('syncSignOutBody')),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s('cancel'))),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: Text(s('syncSignOut')),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await controller.signOut();
              },
              child: Text(s('syncSignOut')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Choix (ou changement) du projet Firebase depuis les Réglages.
Future<void> showFirebaseProjectSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final locale = ref.watch(localeProvider);
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(locale, 'setupProjectTitle'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(locale, 'setupProjectSubtitle'),
                  style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                FirebaseProjectPicker(
                  onSelected: (config) async {
                    await ref.read(firebaseConfigProvider.notifier).set(config);
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Créer mon entreprise, rejoindre avec un code, ou se connecter.
Future<void> showTeamFormSheet(BuildContext context, TeamFormMode mode) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final locale = ref.watch(localeProvider);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(locale, switch (mode) {
                    TeamFormMode.create => 'companyCreateTitle',
                    TeamFormMode.join => 'companyJoinTitle',
                    TeamFormMode.signIn => 'syncSignIn',
                  }),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(locale, switch (mode) {
                    TeamFormMode.create => 'companyCreateSubtitle',
                    TeamFormMode.join => 'companyJoinSubtitle',
                    TeamFormMode.signIn => 'teamSignInHint',
                  }),
                  style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TeamAccountForm(
                  mode: mode,
                  onDone: (status) {
                    final messenger = ScaffoldMessenger.of(context);
                    final sync = ref.read(syncControllerProvider);
                    Navigator.of(sheetContext).pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          status == MemberStatus.active
                              ? fill(tr(locale, 'companyWelcome'), {'company': sync.company?.name ?? ''})
                              : tr(locale, 'noCompanyTitle'),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
