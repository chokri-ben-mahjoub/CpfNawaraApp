import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/sync/firebase_config.dart';
import '../../../core/sync/firebase_config_provider.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../auth/presentation/widgets/language_switch.dart';
import 'widgets/firebase_project_picker.dart';
import 'widgets/team_account_form.dart';

enum _Step { mode, project, account, waiting }

/// Installation (premier lancement) : mode équipe (projet Firebase + compte,
/// le premier compte devient administrateur) ou mode personnel (local, sans
/// compte). Tout se configure ici, sans ouvrir la console Firebase — sauf
/// les réglages que seule la console permet, signalés au bon moment.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late _Step _step;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    final sync = ref.read(syncControllerProvider);
    _step = sync.isSignedIn ? _Step.waiting : _Step.mode;
    if (sync.isSignedIn && sync.memberStatus == MemberStatus.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else if (sync.isSignedIn) {
      // Compte déjà connecté (app fermée pendant l'installation) : relit sa
      // fiche d'équipe.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(syncControllerProvider.notifier).refreshMember().catchError((_) => MemberStatus.unknown),
      );
    }
  }

  /// Compte actif : crée le profil local à partir de la fiche d'équipe (le
  /// routeur enchaîne sur le code à 4 chiffres).
  Future<void> _finish() async {
    if (_finishing) return;
    final member = ref.read(syncControllerProvider).member;
    if (member == null) return;
    _finishing = true;
    await ref
        .read(authServiceProvider)
        .createProfile(
          fullName: member.name.isEmpty ? member.email.split('@').first : member.name,
          phone: '',
          serviceKey: member.service,
        );
  }

  Future<void> _selectProject(FirebaseRestConfig config) async {
    await ref.read(firebaseConfigProvider.notifier).set(config);
    if (mounted) setState(() => _step = _Step.account);
  }

  void _onAccountDone(MemberStatus status) {
    if (status == MemberStatus.active) {
      final member = ref.read(syncControllerProvider).member;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(ref.read(localeProvider), member?.role == UserRole.admin ? 'setupAdminCreated' : 'syncConnected'),
          ),
        ),
      );
      _finish();
    } else {
      setState(() => _step = _Step.waiting);
    }
  }

  Future<void> _cancelAccount() async {
    await ref.read(syncControllerProvider.notifier).signOut();
    if (mounted) setState(() => _step = _Step.account);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final config = ref.watch(firebaseConfigProvider);
    String s(String key) => tr(locale, key);

    ref.listen(syncControllerProvider, (previous, next) {
      if (next.memberStatus == MemberStatus.active && _step == _Step.waiting) _finish();
    });

    final (titleKey, subtitleKey) = switch (_step) {
      _Step.mode => ('setupTitle', 'setupSubtitle'),
      _Step.project => ('setupProjectTitle', 'setupProjectSubtitle'),
      _Step.account => ('setupAccountTitle', 'setupAccountSubtitle'),
      _Step.waiting =>
        ref.watch(syncControllerProvider).memberStatus == MemberStatus.unknown
            ? ('setupCheckingTitle', 'setupCheckingSubtitle')
            : ('setupWaitingTitle', 'setupWaitingSubtitle'),
    };

    Widget body;
    switch (_step) {
      case _Step.mode:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModeCard(
              icon: Icons.groups_2_outlined,
              title: s('setupModeTeam'),
              body: s('setupModeTeamBody'),
              recommended: true,
              onTap: () => setState(() => _step = config == null ? _Step.project : _Step.account),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              icon: Icons.phone_android_outlined,
              title: s('setupModeLocal'),
              body: s('setupModeLocalBody'),
              onTap: () => context.go('/setup-profile'),
            ),
          ],
        );
      case _Step.project:
        body = FirebaseProjectPicker(onSelected: _selectProject);
      case _Step.account:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (config != null)
              _ProjectChip(projectId: config.projectId, onChange: () => setState(() => _step = _Step.project)),
            const SizedBox(height: 14),
            TeamAccountForm(createAccount: true, onDone: _onAccountDone),
          ],
        );
      case _Step.waiting:
        final sync = ref.watch(syncControllerProvider);
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(sync.email ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const MemberStatusBanner(),
            if (sync.memberStatus == MemberStatus.unknown) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(syncControllerProvider.notifier).refreshMember().catchError((_) => MemberStatus.unknown),
                icon: const Icon(Icons.refresh),
                label: Text(s('memberCheckAgain')),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(onPressed: _cancelAccount, child: Text(s('setupUseAnotherAccount'))),
          ],
        );
    }

    return Scaffold(
      body: NarrowSafeArea(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Row(
              children: [
                if (_step != _Step.mode && _step != _Step.waiting)
                  IconButton(
                    tooltip: s('back'),
                    onPressed: () => setState(
                      () =>
                          _step = _step == _Step.account && config != null ? _Step.mode : _Step.values[_step.index - 1],
                    ),
                    icon: const Icon(Icons.arrow_back),
                  ),
                const Spacer(),
                const LanguageSwitch(),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  switch (_step) {
                    _Step.mode => Icons.rocket_launch_outlined,
                    _Step.project => Icons.cloud_outlined,
                    _Step.account => Icons.admin_panel_settings_outlined,
                    _Step.waiting => Icons.hourglass_top_rounded,
                  },
                  color: accentColor,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(s(titleKey), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              s(subtitleKey),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 22),
            body,
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool recommended;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: recommended ? accentColor.withValues(alpha: 0.08) : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: recommended ? accentColor.withValues(alpha: 0.6) : scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accentColor, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(body, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.4)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectChip extends ConsumerWidget {
  final String projectId;
  final VoidCallback onChange;
  const _ProjectChip({required this.projectId, required this.onChange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_outlined, size: 20, color: accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${tr(locale, 'setupProject')} : $projectId',
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onChange, child: Text(tr(locale, 'setupChangeProject'))),
        ],
      ),
    );
  }
}
