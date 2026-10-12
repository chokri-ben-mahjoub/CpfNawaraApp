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

enum _Step { mode, create, join, signIn, status, project }

/// Installation (premier lancement), sans aucune configuration :
/// - créer mon entreprise (nouveau client, qui en devient l'administrateur) ;
/// - rejoindre mon entreprise avec le code (ou QR code) d'invitation ;
/// - se connecter à un compte existant ;
/// - ou utiliser l'app sans compte, sur cet appareil.
/// Un projet Firebase personnalisé reste possible (Options avancées).
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
    _step = sync.isSignedIn ? _Step.status : _Step.mode;
    if (sync.isSignedIn && sync.memberStatus == MemberStatus.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else if (sync.isSignedIn) {
      // Compte déjà connecté (app fermée pendant l'installation) : relit son
      // adhésion.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(syncControllerProvider.notifier).refreshMember().catchError((_) => MemberStatus.unknown),
      );
    }
  }

  /// Compte actif : crée le profil local à partir de la fiche du membre (le
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

  void _onDone(MemberStatus status) {
    if (status == MemberStatus.active) {
      final sync = ref.read(syncControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fill(tr(ref.read(localeProvider), sync.member?.role == UserRole.admin ? 'companyWelcomeAdmin' : 'companyWelcome'), {
              'company': sync.company?.name ?? '',
            }),
          ),
        ),
      );
      _finish();
    } else {
      setState(() => _step = _Step.status);
    }
  }

  Future<void> _useAnotherAccount() async {
    await ref.read(syncControllerProvider.notifier).signOut();
    if (mounted) setState(() => _step = _Step.mode);
  }

  Future<void> _selectProject(FirebaseRestConfig config) async {
    await ref.read(firebaseConfigProvider.notifier).set(config);
    if (mounted) setState(() => _step = _Step.mode);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final config = ref.watch(firebaseConfigProvider);
    final customProject = ref.watch(firebaseConfigProvider.notifier).isCustom;
    String s(String key) => tr(locale, key);

    ref.listen(syncControllerProvider, (previous, next) {
      if (next.memberStatus == MemberStatus.active && _step == _Step.status) _finish();
    });

    final (titleKey, subtitleKey, icon) = switch (_step) {
      _Step.mode => ('setupTitle', 'setupSubtitle', Icons.rocket_launch_outlined),
      _Step.create => ('companyCreateTitle', 'companyCreateSubtitle', Icons.add_business_outlined),
      _Step.join => ('companyJoinTitle', 'companyJoinSubtitle', Icons.group_add_outlined),
      _Step.signIn => ('syncSignIn', 'teamSignInHint', Icons.login_rounded),
      _Step.status => ('setupStatusTitle', 'setupStatusSubtitle', Icons.business_outlined),
      _Step.project => ('setupProjectTitle', 'setupProjectSubtitle', Icons.cloud_outlined),
    };

    final Widget body = switch (_step) {
      _Step.mode => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModeCard(
            icon: Icons.add_business_outlined,
            title: s('companyCreateTitle'),
            body: s('setupModeCreateBody'),
            highlighted: true,
            onTap: () => setState(() => _step = _Step.create),
          ),
          const SizedBox(height: 10),
          _ModeCard(
            icon: Icons.group_add_outlined,
            title: s('companyJoinTitle'),
            body: s('setupModeJoinBody'),
            onTap: () => setState(() => _step = _Step.join),
          ),
          const SizedBox(height: 10),
          _ModeCard(
            icon: Icons.login_rounded,
            title: s('setupModeSignIn'),
            body: s('setupModeSignInBody'),
            onTap: () => setState(() => _step = _Step.signIn),
          ),
          const SizedBox(height: 10),
          _ModeCard(
            icon: Icons.phone_android_outlined,
            title: s('setupModeLocal'),
            body: s('setupModeLocalBody'),
            onTap: () => context.go('/setup-profile'),
          ),
          const SizedBox(height: 18),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _step = _Step.project),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(
                customProject && config != null
                    ? '${s('setupAdvanced')} · ${config.projectId}'
                    : s('setupAdvanced'),
              ),
            ),
          ),
        ],
      ),
      _Step.create => TeamAccountForm(mode: TeamFormMode.create, onDone: _onDone),
      _Step.join => TeamAccountForm(mode: TeamFormMode.join, onDone: _onDone),
      _Step.signIn => TeamAccountForm(mode: TeamFormMode.signIn, onDone: _onDone),
      _Step.status => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(ref.watch(syncControllerProvider).email ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (ref.watch(syncControllerProvider).memberStatus == MemberStatus.unknown)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else ...[
            NoCompanyOrStatus(onDone: _onDone),
          ],
          const SizedBox(height: 16),
          TextButton(onPressed: _useAnotherAccount, child: Text(s('setupUseAnotherAccount'))),
        ],
      ),
      _Step.project => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s('setupAdvancedBody'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
          const SizedBox(height: 14),
          FirebaseProjectPicker(onSelected: _selectProject),
        ],
      ),
    };

    return Scaffold(
      body: NarrowSafeArea(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Row(
              children: [
                if (_step != _Step.mode && _step != _Step.status)
                  IconButton(
                    tooltip: s('back'),
                    onPressed: () => setState(() => _step = _Step.mode),
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
                child: Icon(icon, color: accentColor, size: 26),
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

/// Compte connecté : choix d'une entreprise s'il n'en a pas, sinon état de
/// son adhésion (désactivé, retiré...).
class NoCompanyOrStatus extends ConsumerWidget {
  final ValueChanged<MemberStatus> onDone;
  const NoCompanyOrStatus({super.key, required this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider.select((s) => s.memberStatus));
    return status == MemberStatus.noCompany ? NoCompanyPanel(onDone: onDone) : const MemberStatusBanner();
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool highlighted;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: highlighted ? accentColor.withValues(alpha: 0.08) : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: highlighted ? accentColor.withValues(alpha: 0.6) : scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accentColor, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const SizedBox(height: 3),
                    Text(body, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.4)),
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
