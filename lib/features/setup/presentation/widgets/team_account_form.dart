import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/models/user_role.dart';
import '../../../../core/sync/firebase_config.dart';
import '../../../../core/sync/firebase_config_provider.dart';
import '../../../../core/sync/firebase_rest.dart';
import '../../../../core/sync/sync_service.dart';
import '../../../../core/team/firestore_rules.dart';
import '../../../../core/team/team_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../qr_scan_screen.dart';
import 'firebase_project_picker.dart';

/// Problème de configuration du projet que seule la console Firebase peut
/// régler (une seule fois, par l'éditeur de l'app) : l'app indique quoi
/// faire et ouvre la bonne page.
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

/// Message (clé de traduction) d'une erreur de compte ou d'entreprise.
String teamErrorKey(Object error) => switch (error) {
  InviteException(:final reason) => switch (reason) {
    'expired' => 'inviteErrorExpired',
    'used' => 'inviteErrorUsed',
    'email' => 'inviteErrorEmail',
    _ => 'inviteErrorUnknown',
  },
  ActivationException(:final reason) => reason == 'used' ? 'activationErrorUsed' : 'activationErrorUnknown',
  AlreadyInCompanyException() => 'teamErrorAlreadyInCompany',
  SyncAuthException(:final code) => authErrorKey(code),
  SyncNetworkException() => 'syncOffline',
  FunctionCallException(:final status) when status == 'ALREADY_EXISTS' => 'syncErrorEmailExists',
  _ => 'syncErrorServer',
};

/// Contenu d'un QR code d'invitation : le code, et la configuration du
/// projet Firebase quand l'entreprise utilise son propre projet.
({String code, FirebaseRestConfig? config}) parseInviteQr(String text) {
  FirebaseRestConfig? config;
  var code = '';
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      code = normalizeInviteCode('${decoded['invite'] ?? ''}');
      config = FirebaseRestConfig.fromJson(Map<String, Object?>.from(decoded));
    }
  } catch (_) {
    code = normalizeInviteCode(text);
  }
  return (code: code, config: config);
}

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

/// Ce que fait le formulaire de compte.
enum TeamFormMode {
  /// Nouveau client : crée son entreprise (il en devient l'administrateur).
  create,

  /// Rejoint une entreprise avec un code d'invitation.
  join,

  /// Compte existant (son entreprise est retrouvée automatiquement).
  signIn,
}

/// Formulaire de compte : créer mon entreprise, rejoindre avec un code, ou
/// se connecter. Avec [currentAccount], le compte déjà connecté (sans
/// entreprise) crée ou rejoint une entreprise : ni e-mail ni mot de passe.
class TeamAccountForm extends ConsumerStatefulWidget {
  final TeamFormMode mode;
  final bool currentAccount;
  final String? initialCode;

  /// Appelé après une création / adhésion / connexion réussie.
  final ValueChanged<MemberStatus> onDone;

  const TeamAccountForm({
    super.key,
    required this.mode,
    required this.onDone,
    this.currentAccount = false,
    this.initialCode,
  });

  @override
  ConsumerState<TeamAccountForm> createState() => _TeamAccountFormState();
}

class _TeamAccountFormState extends ConsumerState<TeamAccountForm> {
  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  final _activation = TextEditingController();
  bool _existing = false;
  bool _busy = false;
  bool _obscure = true;
  bool _checkingCode = false;
  Invite? _preview;
  String? _error;
  ProjectProblem? _problem;

  bool get _create => widget.mode == TeamFormMode.create;
  bool get _join => widget.mode == TeamFormMode.join;
  bool get _signIn => widget.mode == TeamFormMode.signIn;

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(profileProvider)?.fullName ?? '';
    if (widget.initialCode != null) {
      _code.text = formatInviteCode(normalizeInviteCode(widget.initialCode!));
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkCode());
    }
  }

  @override
  void dispose() {
    _company.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    _activation.dispose();
    super.dispose();
  }

  String s(String key) => tr(ref.read(localeProvider), key);

  Future<void> _checkCode() async {
    final code = normalizeInviteCode(_code.text);
    if (!isValidInviteCode(code)) {
      setState(() {
        _preview = null;
        _error = s('inviteErrorFormat');
      });
      return;
    }
    final team = ref.read(syncControllerProvider.notifier).team;
    if (team == null) return;
    setState(() {
      _checkingCode = true;
      _error = null;
    });
    try {
      final preview = await team.previewInvite(code);
      setState(() {
        _preview = preview;
        _error = preview == null
            ? s('inviteErrorUnknown')
            : preview.expired
            ? s('inviteErrorExpired')
            : null;
      });
    } catch (e) {
      setState(() => _error = s(teamErrorKey(e)));
    } finally {
      if (mounted) setState(() => _checkingCode = false);
    }
  }

  Future<void> _scan() async {
    final text = await scanQrCode(context);
    if (text == null || !mounted) return;
    final (:code, :config) = parseInviteQr(text);
    // Entreprise sur son propre projet Firebase : le QR code le configure.
    final current = ref.read(firebaseConfigProvider);
    if (config != null && config != current) {
      await ref.read(firebaseConfigProvider.notifier).set(config);
    }
    _code.text = formatInviteCode(code);
    await _checkCode();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_join && (_preview == null || _preview!.code != normalizeInviteCode(_code.text))) {
      await _checkCode();
      if (_preview == null || _preview!.expired) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _problem = null;
    });
    final controller = ref.read(syncControllerProvider.notifier);
    final email = _email.text.trim();
    final name = _name.text.trim();
    try {
      final MemberStatus status;
      if (widget.currentAccount) {
        status = _create
            ? await controller.createCompanyForCurrent(
                companyName: _company.text.trim(),
                name: name,
                activation: _activation.text,
              )
            : await controller.joinCompanyForCurrent(code: _code.text, name: name);
      } else {
        status = switch (widget.mode) {
          TeamFormMode.create => await controller.createCompany(
            email: email,
            password: _password.text,
            companyName: _company.text.trim(),
            name: name,
            activation: _activation.text,
            existingAccount: _existing,
          ),
          TeamFormMode.join => await controller.joinCompany(
            code: _code.text,
            email: email,
            password: _password.text,
            name: name,
            existingAccount: _existing,
          ),
          TeamFormMode.signIn => await controller.signIn(email, _password.text),
        };
      }
      if (!mounted) return;
      widget.onDone(status);
    } catch (e) {
      final problem = projectProblemOf(e);
      setState(() {
        _problem = problem;
        _error = problem != null
            ? null
            // Propriétaire : le code est facultatif, le plus simple est de
            // le laisser vide.
            : e is ActivationException && _create && isOwnerEmail(_email.text)
            ? s('activationOwnerHint')
            : s(teamErrorKey(e));
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
    } catch (e) {
      setState(() => _error = s(teamErrorKey(e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final config = ref.watch(syncControllerProvider.notifier).config;
    String t(String key) => tr(locale, key);
    final askCredentials = !widget.currentAccount;
    final newAccount = askCredentials && !_signIn && !_existing;
    final preview = _preview;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_create) ...[
            TextFormField(
              controller: _activation,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5),
              decoration: InputDecoration(
                labelText: t('activationCodeLabel'),
                hintText: 'ABCD-EFGH',
                helperText: t('activationCodeHint'),
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.verified_user_outlined),
              ),
              validator: (v) {
                // Propriétaire de PuitsTrack : code facultatif.
                final owner = widget.currentAccount
                    ? ref.read(syncControllerProvider.notifier).isOwner
                    : isOwnerEmail(_email.text);
                if (owner && (v ?? '').trim().isEmpty) return null;
                return isValidInviteCode(normalizeInviteCode(v ?? '')) ? null : t('inviteErrorFormat');
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _company,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t('companyNameLabel'), prefixIcon: const Icon(Icons.business_outlined)),
              validator: (v) => (v ?? '').trim().length < 2 ? t('companyNameInvalid') : null,
            ),
            const SizedBox(height: 12),
          ],
          if (_join) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5),
                    decoration: InputDecoration(
                      labelText: t('inviteCodeLabel'),
                      hintText: 'ABCD-EFGH',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: _checkingCode
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton(
                              tooltip: t('inviteCheck'),
                              icon: const Icon(Icons.arrow_forward_rounded),
                              onPressed: _checkCode,
                            ),
                    ),
                    onFieldSubmitted: (_) => _checkCode(),
                    onChanged: (_) {
                      if (_preview != null) setState(() => _preview = null);
                    },
                    validator: (v) => isValidInviteCode(normalizeInviteCode(v ?? '')) ? null : t('inviteErrorFormat'),
                  ),
                ),
                if (canScanQrCode) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _scan,
                      child: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                  ),
                ],
              ],
            ),
            if (preview != null && !preview.expired) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade600.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified_outlined, color: Colors.green.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        fill(t('invitePreview'), {'company': preview.companyName, 'role': t(preview.role.labelKey)}),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
          if (!_signIn) ...[
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t('signupNameLabel'), prefixIcon: const Icon(Icons.badge_outlined)),
              validator: (v) => (v ?? '').trim().length < 2 ? t('signupInvalidName') : null,
            ),
            const SizedBox(height: 12),
          ],
          if (askCredentials) ...[
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
              autofillHints: [newAccount ? AutofillHints.newPassword : AutofillHints.password],
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
            if (newAccount) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: InputDecoration(labelText: t('syncPasswordConfirm'), prefixIcon: const Icon(Icons.lock_outline)),
                validator: (v) => v == _password.text ? null : t('syncPasswordMismatch'),
              ),
            ],
            if (!_signIn)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _existing,
                activeTrackColor: accentColor,
                title: Text(t('teamExistingAccount')),
                subtitle: Text(t('teamExistingAccountHint')),
                onChanged: _busy ? null : (v) => setState(() => _existing = v),
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
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
                      t(switch (widget.mode) {
                        TeamFormMode.create => 'companyCreateAction',
                        TeamFormMode.join => 'companyJoinAction',
                        TeamFormMode.signIn => 'syncSignIn',
                      }),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          if (_signIn)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: _busy ? null : _resetPassword, child: Text(t('syncForgotPassword'))),
            ),
        ],
      ),
    );
  }
}

/// Compte connecté qui n'appartient (plus) à aucune entreprise, ou dont
/// l'accès est suspendu : explication et actions possibles.
class MemberStatusBanner extends ConsumerStatefulWidget {
  const MemberStatusBanner({super.key});

  @override
  ConsumerState<MemberStatusBanner> createState() => _MemberStatusBannerState();
}

class _MemberStatusBannerState extends ConsumerState<MemberStatusBanner> {
  bool _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      await ref.read(syncControllerProvider.notifier).refreshMember();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr(ref.read(localeProvider), 'syncErrorServer'))));
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
    String s(String key) => tr(locale, key);
    final status = sync.memberStatus;
    if (!sync.isSignedIn || status == MemberStatus.active || status == MemberStatus.unknown) {
      return const SizedBox.shrink();
    }
    if (status == MemberStatus.noCompany) return const NoCompanyPanel();
    final (icon, titleKey, bodyKey) = switch (status) {
      MemberStatus.pending => (Icons.hourglass_top_rounded, 'memberPendingTitle', 'memberPendingBody'),
      MemberStatus.inactive => (Icons.block_rounded, 'memberInactiveTitle', 'memberInactiveBody'),
      _ => (Icons.person_off_outlined, 'memberRemovedTitle', 'memberRemovedBody'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s(titleKey), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(s(bodyKey), style: const TextStyle(fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _check,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: Text(s('memberCheckAgain')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compte sans entreprise : créer la sienne ou en rejoindre une.
class NoCompanyPanel extends ConsumerWidget {
  /// Appelé une fois l'entreprise créée ou rejointe.
  final ValueChanged<MemberStatus>? onDone;
  const NoCompanyPanel({super.key, this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);

    Future<void> open(TeamFormMode mode) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s(mode == TeamFormMode.create ? 'companyCreateTitle' : 'companyJoinTitle'),
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              TeamAccountForm(
                mode: mode,
                currentAccount: true,
                onDone: (status) {
                  Navigator.of(sheetContext).pop();
                  onDone?.call(status);
                },
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.business_outlined, color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s('noCompanyTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(s('noCompanyBody'), style: const TextStyle(fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
                onPressed: () => open(TeamFormMode.create),
                icon: const Icon(Icons.add_business_outlined, size: 18),
                label: Text(s('companyCreateTitle')),
              ),
              OutlinedButton.icon(
                onPressed: () => open(TeamFormMode.join),
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: Text(s('companyJoinTitle')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Libellé du rôle d'un membre (utilisé dans les aperçus d'invitation).
String roleLabel(Locale locale, UserRole role) => tr(locale, role.labelKey);
