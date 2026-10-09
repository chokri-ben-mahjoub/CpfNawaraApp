import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/sync/firebase_config.dart';
import '../../../../core/sync/firebase_rest.dart';
import '../../../../core/sync/sync_service.dart';
import '../../../../core/team/firestore_rules.dart';
import '../../../../core/theme/app_theme.dart';
import 'firebase_project_picker.dart';

/// Problème de configuration du projet que seule la console Firebase peut
/// régler (une seule fois) : l'app indique quoi faire et ouvre la bonne page.
enum ProjectProblem { providerDisabled, rulesNotPublished, databaseMissing }

ProjectProblem? projectProblemOf(Object error) {
  if (error is SyncAuthException &&
      (error.code == 'OPERATION_NOT_ALLOWED' ||
          error.code == 'PASSWORD_LOGIN_DISABLED' ||
          error.code == 'CONFIGURATION_NOT_FOUND')) {
    return ProjectProblem.providerDisabled;
  }
  if (error is SyncServerException) {
    if (error.isDatabaseMissing) return ProjectProblem.databaseMissing;
    if (error.isPermissionDenied) return ProjectProblem.rulesNotPublished;
  }
  return null;
}

String authErrorKey(String code) => switch (code) {
  'EMAIL_EXISTS' => 'syncErrorEmailExists',
  'EMAIL_NOT_FOUND' || 'INVALID_PASSWORD' || 'INVALID_LOGIN_CREDENTIALS' => 'syncErrorCredentials',
  'WEAK_PASSWORD' => 'syncErrorWeakPassword',
  'INVALID_EMAIL' => 'syncInvalidEmail',
  'TOO_MANY_ATTEMPTS_TRY_LATER' => 'syncErrorTooMany',
  'OPERATION_NOT_ALLOWED' || 'PASSWORD_LOGIN_DISABLED' || 'CONFIGURATION_NOT_FOUND' => 'syncErrorProviderDisabled',
  'USER_DISABLED' => 'syncErrorUserDisabled',
  _ => 'syncErrorServer',
};

/// Carte "à faire dans la console Firebase" avec le bouton qui ouvre la
/// bonne page (et la copie des règles de sécurité).
class ProjectProblemCard extends ConsumerWidget {
  final ProjectProblem problem;
  final FirebaseRestConfig config;

  const ProjectProblemCard({super.key, required this.problem, required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final (titleKey, bodyKey, page) = switch (problem) {
      ProjectProblem.providerDisabled => ('problemProviderTitle', 'problemProviderBody', 'authentication/providers'),
      ProjectProblem.rulesNotPublished => ('problemRulesTitle', 'problemRulesBody', 'firestore/rules'),
      ProjectProblem.databaseMissing => ('problemDatabaseTitle', 'problemDatabaseBody', 'firestore'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.build_circle_outlined, color: scheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s(titleKey), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(s(bodyKey), style: const TextStyle(fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (problem == ProjectProblem.rulesNotPublished)
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(const ClipboardData(text: firestoreRules));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('rulesCopied'))));
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(s('rulesCopy')),
                ),
              FilledButton.icon(
                onPressed: () => openExternalLink(config.consoleUrl(page)),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(s('problemOpenConsole')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Création du compte (premier compte = administrateur) ou connexion.
class TeamAccountForm extends ConsumerStatefulWidget {
  final bool createAccount;

  /// Appelé après une création / connexion réussie.
  final ValueChanged<MemberStatus> onDone;

  const TeamAccountForm({super.key, required this.createAccount, required this.onDone});

  @override
  ConsumerState<TeamAccountForm> createState() => _TeamAccountFormState();
}

class _TeamAccountFormState extends ConsumerState<TeamAccountForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late bool _create = widget.createAccount;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  ProjectProblem? _problem;

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(profileProvider)?.fullName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String s(String key) => tr(ref.read(localeProvider), key);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _problem = null;
    });
    final controller = ref.read(syncControllerProvider.notifier);
    final email = _email.text.trim();
    try {
      final status = _create
          ? await controller.createAccount(email, _password.text, name: _name.text.trim())
          : await controller.signIn(email, _password.text);
      if (!mounted) return;
      widget.onDone(status);
    } catch (e) {
      final problem = projectProblemOf(e);
      setState(() {
        _problem = problem;
        _error = problem != null
            ? null
            : e is SyncAuthException
            ? s(authErrorKey(e.code))
            : e is SyncNetworkException
            ? s('syncOffline')
            : s('syncErrorServer');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = s('syncInvalidEmail'));
      return;
    }
    try {
      await ref.read(syncControllerProvider.notifier).sendPasswordReset(email);
      setState(() => _error = null);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('syncResetSent'))));
    } on SyncAuthException catch (e) {
      setState(() => _error = s(authErrorKey(e.code)));
    } on SyncNetworkException {
      setState(() => _error = s('syncOffline'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final config = ref.watch(syncControllerProvider.notifier).config;
    String t(String key) => tr(locale, key);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, label: Text(t('syncCreateAccount'))),
              ButtonSegment(value: false, label: Text(t('syncSignIn'))),
            ],
            selected: {_create},
            onSelectionChanged: _busy ? null : (v) => setState(() => _create = v.first),
          ),
          const SizedBox(height: 8),
          Text(
            t(_create ? 'teamCreateHint' : 'teamSignInHint'),
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 14),
          if (_create) ...[
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: t('signupNameLabel'),
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
              validator: (v) => (v ?? '').trim().length < 2 ? t('signupInvalidName') : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(labelText: t('syncEmail'), prefixIcon: const Icon(Icons.alternate_email)),
            validator: (v) => (v ?? '').trim().contains('@') ? null : t('syncInvalidEmail'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
            decoration: InputDecoration(
              labelText: t('syncPassword'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v ?? '').length < 6 ? t('syncErrorWeakPassword') : null,
          ),
          if (_create) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: t('syncPasswordConfirm'),
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              validator: (v) => v == _password.text ? null : t('syncPasswordMismatch'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
            ),
          ],
          if (_problem != null && config != null) ...[
            const SizedBox(height: 12),
            ProjectProblemCard(problem: _problem!, config: config),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      t(_create ? 'syncCreateAccount' : 'syncSignIn'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          if (!_create)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: _busy ? null : _resetPassword, child: Text(t('syncForgotPassword'))),
            ),
        ],
      ),
    );
  }
}

/// Message d'attente / de refus selon l'état du compte dans l'équipe, avec
/// le bouton pour vérifier à nouveau (ou demander l'accès).
class MemberStatusBanner extends ConsumerStatefulWidget {
  const MemberStatusBanner({super.key});

  @override
  ConsumerState<MemberStatusBanner> createState() => _MemberStatusBannerState();
}

class _MemberStatusBannerState extends ConsumerState<MemberStatusBanner> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(ref.read(localeProvider), 'syncErrorServer'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final sync = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final status = sync.memberStatus;
    if (!sync.isSignedIn || status == MemberStatus.active || status == MemberStatus.unknown) {
      return const SizedBox.shrink();
    }
    final (icon, titleKey, bodyKey) = switch (status) {
      MemberStatus.pending => (Icons.hourglass_top_rounded, 'memberPendingTitle', 'memberPendingBody'),
      MemberStatus.inactive => (Icons.block_rounded, 'memberInactiveTitle', 'memberInactiveBody'),
      _ => (Icons.person_off_outlined, 'memberMissingTitle', 'memberMissingBody'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (status == MemberStatus.pending ? accentColor : scheme.error).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: status == MemberStatus.pending ? accentColor : scheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s(titleKey), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(s(bodyKey), style: const TextStyle(fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == MemberStatus.missing)
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => controller.requestAccess(
                            ref.read(profileProvider)?.fullName.isNotEmpty == true
                                ? ref.read(profileProvider)!.fullName
                                : (sync.email ?? '').split('@').first,
                          ),
                        ),
                  icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                  label: Text(s('memberRequestAccess')),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(() async => controller.refreshMember()),
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: Text(s('memberCheckAgain')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
