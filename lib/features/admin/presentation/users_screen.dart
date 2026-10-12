import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/sync/firebase_config_provider.dart';
import '../../../core/sync/firebase_rest.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/team/team_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/responsive.dart';
import '../../settings/presentation/sync_section.dart';
import '../../setup/presentation/widgets/team_account_form.dart';
import 'widgets/admin_widgets.dart';

/// Mot de passe provisoire lisible (sans caractères ambigus).
String generateTempPassword([int length = 10]) {
  const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
}

/// Utilisateurs de l'entreprise : membres et rôles, invitations par code
/// (ou QR code), comptes créés directement, désactivation, retrait.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  List<TeamMember>? _members;
  List<Invite>? _invites;
  bool _functions = false;
  Object? _error;
  bool _loading = false;

  String s(String key) => tr(ref.read(localeProvider), key);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final controller = ref.read(syncControllerProvider.notifier);
    final company = ref.read(syncControllerProvider).company;
    if (controller.team == null || company == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await controller.freshSession();
      final team = controller.team!;
      final results = await Future.wait([
        team.listMembers(session, company.id),
        team.listInvites(session, company.id),
        team.functionsAvailable(session),
      ]);
      if (!mounted) return;
      setState(() {
        _members = results[0] as List<TeamMember>;
        _invites = (results[1] as List<Invite>).where((i) => !i.used && !i.expired).toList();
        _functions = results[2] as bool;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({TeamMember? member}) async {
    final changed = await showAdminSheet<bool>(
      context,
      builder: (sheetContext) => _MemberForm(existing: member, functions: _functions),
    );
    if (changed == true) await _load();
  }

  Future<void> _invite() async {
    final invite = await showAdminSheet<Invite>(context, builder: (_) => const _InviteForm());
    if (invite == null || !mounted) return;
    await _load();
    if (mounted) await showInviteDialog(context, invite);
  }

  Future<void> _deleteInvite(Invite invite) async {
    final controller = ref.read(syncControllerProvider.notifier);
    final company = ref.read(syncControllerProvider).company!;
    try {
      final session = await controller.freshSession();
      await controller.team!.deleteInvite(session, company.id, invite.code);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s(teamErrorKey(e)))));
    }
  }

  Future<void> _renameCompany(Company company) async {
    final text = TextEditingController(text: company.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s('companyRename')),
        content: TextField(controller: text, autofocus: true, decoration: InputDecoration(labelText: s('companyNameLabel'))),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(s('cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(text.text.trim()), child: Text(s('wellsManageSave'))),
        ],
      ),
    );
    text.dispose();
    if (name == null || name.length < 2) return;
    final controller = ref.read(syncControllerProvider.notifier);
    try {
      final session = await controller.freshSession();
      await controller.team!.renameCompany(session, company, name);
      await controller.refreshMember();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s(teamErrorKey(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final sync = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    String t(String key) => tr(locale, key);
    final company = sync.company;

    if (controller.team == null || !sync.isSignedIn || company == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('adminUsers'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IconBadge(Icons.groups_2_outlined, size: 64),
                  const SizedBox(height: 16),
                  Text(t('usersLocalTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  const SizedBox(height: 8),
                  Text(t('usersLocalBody'), textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.cloud_sync_outlined),
                    label: Text(t('usersLocalAction')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final members = _members ?? const <TeamMember>[];
    final invites = _invites ?? const <Invite>[];
    final problem = _error == null ? null : projectProblemOf(_error!);
    final dateFormat = DateFormat('d MMM', locale.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('adminUsers')),
        actions: [IconButton(tooltip: t('refresh'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _invite,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(t('inviteAction')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: pagePadding(context, top: 8, bottom: 120),
          children: [
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: const IconBadge(Icons.business_outlined),
                title: Text(company.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                subtitle: Text(
                  _functions ? t('usersFunctionsOn') : t('usersFunctionsOff'),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                trailing: IconButton(
                  tooltip: t('companyRename'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _renameCompany(company),
                ),
              ),
            ),
            if (_loading && _members == null) ...[const SizedBox(height: 16), const SkeletonList()],
            if (_error != null) ...[
              const SizedBox(height: 12),
              if (problem != null && controller.config != null)
                ProjectProblemCard(problem: problem, config: controller.config!)
              else
                Text(
                  _error is SyncNetworkException ? t('syncOffline') : t('syncErrorServer'),
                  style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
                ),
            ],
            if (invites.isNotEmpty) ...[
              AdminSectionTitle('${t('invitesPending')} (${invites.length})'),
              for (final invite in invites) ...[
                AdminCard(
                  leading: const IconBadge(Icons.vpn_key_outlined),
                  title: invite.displayCode,
                  subtitle:
                      '${t(invite.role.labelKey)} · ${invite.email.isEmpty ? t('inviteAnyEmail') : invite.email} · '
                      '${fill(t('inviteUntil'), {'date': dateFormat.format(invite.expiresAt)})}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: t('inviteShow'),
                        icon: const Icon(Icons.qr_code_2_rounded),
                        onPressed: () => showInviteDialog(context, invite),
                      ),
                      IconButton(
                        tooltip: t('inviteDelete'),
                        icon: Icon(Icons.delete_outline, color: scheme.error),
                        onPressed: () => _deleteInvite(invite),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
            if (_members != null) ...[
              AdminSectionTitle(
                '${t('usersMembers')} (${members.length})',
                trailing: TextButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: Text(t('usersAdd')),
                ),
              ),
              AdminTable<TeamMember>(
                items: members,
                onTap: (m) => _openEditor(member: m),
                columns: [
                  AdminColumn(
                    t('signupNameLabel'),
                    (m) => Text(m.name.isEmpty ? '—' : m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  AdminColumn(t('syncEmail'), (m) => Text(m.email)),
                  AdminColumn(t('usersRole'), (m) => RoleChip(role: m.role, active: m.active)),
                  AdminColumn(t('colStatus'), (m) => _StatusText(active: m.active)),
                  AdminColumn(t('signupServiceLabel'), (m) => Text(m.service.isEmpty ? '—' : t(m.service))),
                ],
                card: (context, m) => AdminCard(
                  leading: CircleAvatar(
                    backgroundColor: (m.active ? accentColor : scheme.outline).withValues(alpha: 0.14),
                    child: Text(
                      (m.name.isEmpty ? m.email : m.name).substring(0, 1).toUpperCase(),
                      style: TextStyle(color: m.active ? accentColor : scheme.outline, fontWeight: FontWeight.w800),
                    ),
                  ),
                  title: m.name.isEmpty ? m.email : m.name,
                  subtitle: m.active ? m.email : '${m.email} · ${t('usersInactive')}',
                  trailing: RoleChip(role: m.role, active: m.active),
                  onTap: () => _openEditor(member: m),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusText extends ConsumerWidget {
  final bool active;
  const _StatusText({required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 9, color: active ? Colors.green.shade600 : scheme.outline),
        const SizedBox(width: 6),
        Text(tr(locale, active ? 'usersActive' : 'usersInactive')),
      ],
    );
  }
}

/// Texte d'invitation à envoyer (WhatsApp, e-mail...).
String inviteMessage(Locale locale, Invite invite) =>
    fill(tr(locale, 'inviteMessage'), {'company': invite.companyName, 'code': invite.displayCode});

/// Contenu du QR code d'invitation (le code, et le projet Firebase s'il
/// n'est pas le projet PuitsTrack).
String inviteQrPayload(WidgetRef ref, Invite invite) {
  final notifier = ref.read(firebaseConfigProvider.notifier);
  final config = ref.read(firebaseConfigProvider);
  return jsonEncode({
    'app': 'puitstrack',
    'invite': invite.code,
    if (notifier.isCustom && config != null) ...config.toJson(),
  });
}

/// Code d'invitation à transmettre : en grand, en QR code, à copier ou
/// partager.
Future<void> showInviteDialog(BuildContext context, Invite invite) => showDialog<void>(
  context: context,
  builder: (dialogContext) => Consumer(
    builder: (context, ref, _) {
      final locale = ref.watch(localeProvider);
      String t(String key) => tr(locale, key);
      final message = inviteMessage(locale, invite);
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(t('inviteReadyTitle')),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fill(t('inviteReadyBody'), {'role': t(invite.role.labelKey)}),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 14),
                SelectableText(
                  invite.displayCode,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 3, color: accentColor),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: QrImageView(data: inviteQrPayload(ref, invite), size: 180, backgroundColor: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  fill(t('inviteUntil'), {'date': DateFormat('d MMM yyyy', locale.languageCode).format(invite.expiresAt)}),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(t('inviteCopied'))));
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(t('usersCopyCredentials')),
          ),
          TextButton.icon(
            onPressed: () => Share.share(message),
            icon: const Icon(Icons.share_outlined, size: 18),
            label: Text(t('exportActionShare')),
          ),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(t('ok'))),
        ],
      );
    },
  ),
);

/// Nouvelle invitation : rôle, e-mail imposé (facultatif).
class _InviteForm extends ConsumerStatefulWidget {
  const _InviteForm();

  @override
  ConsumerState<_InviteForm> createState() => _InviteFormState();
}

class _InviteFormState extends ConsumerState<_InviteForm> {
  final _email = TextEditingController();
  UserRole _role = UserRole.operator;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final controller = ref.read(syncControllerProvider.notifier);
    final sync = ref.read(syncControllerProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await controller.freshSession();
      final invite = await controller.team!.createInvite(
        session,
        sync.company!,
        adminName: controller.displayName,
        role: _role,
        email: _email.text,
      );
      if (mounted) Navigator.of(context).pop(invite);
    } catch (e) {
      setState(() => _error = tr(ref.read(localeProvider), teamErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String t(String key) => tr(locale, key);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('inviteAction'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(t('inviteFormHint'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        Text(t('usersRole'), style: const TextStyle(fontWeight: FontWeight.w800)),
        RoleRadioList(value: _role, onChanged: (r) => setState(() => _role = r)),
        const SizedBox(height: 8),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: t('inviteEmailLabel'),
            helperText: t('inviteEmailHint'),
            prefixIcon: const Icon(Icons.alternate_email),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
            onPressed: _busy ? null : _create,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.vpn_key_outlined),
            label: Text(t('inviteCreate'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

/// Choix du rôle (avec description).
class RoleRadioList extends ConsumerWidget {
  final UserRole value;
  final ValueChanged<UserRole> onChanged;
  final bool enabled;
  const RoleRadioList({super.key, required this.value, required this.onChanged, this.enabled = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    String t(String key) => tr(locale, key);
    return RadioGroup<UserRole>(
      groupValue: value,
      onChanged: (v) {
        if (enabled && v != null) onChanged(v);
      },
      child: Column(
        children: [
          for (final role in UserRole.values)
            RadioListTile<UserRole>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: role,
              enabled: enabled,
              title: Text(t(role.labelKey), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t(role.descriptionKey)),
            ),
        ],
      ),
    );
  }
}

/// Création (compte direct) ou modification d'un membre.
class _MemberForm extends ConsumerStatefulWidget {
  final TeamMember? existing;
  final bool functions;
  const _MemberForm({this.existing, required this.functions});

  @override
  ConsumerState<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends ConsumerState<_MemberForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late UserRole _role;
  late bool _active;
  String _service = '';
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _name = TextEditingController(text: m?.name ?? '');
    _email = TextEditingController(text: m?.email ?? '');
    _password = TextEditingController(text: generateTempPassword());
    _role = m?.role ?? UserRole.operator;
    _active = m?.active ?? true;
    _service = m?.service ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String s(String key) => tr(ref.read(localeProvider), key);

  bool get _isSelf => widget.existing?.uid == ref.read(syncControllerProvider).member?.uid;

  Future<T?> _run<T>(Future<T> Function(AuthSession session, TeamService team, String cid) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(syncControllerProvider.notifier);
    try {
      final session = await controller.freshSession();
      return await action(session, controller.team!, ref.read(syncControllerProvider).company!.id);
    } catch (e) {
      setState(() => _error = s(teamErrorKey(e)));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final adminName = ref.read(syncControllerProvider.notifier).displayName;
    final done = await _run((session, team, cid) async {
      if (_isNew) {
        final member = await team.createMember(
          session,
          cid,
          adminName: adminName,
          email: _email.text.trim(),
          password: _password.text,
          name: _name.text.trim(),
          role: _role,
          service: _service,
        );
        if (mounted) await _showCredentials(member.email, _password.text);
      } else {
        await team.updateMember(
          session,
          cid,
          adminName: adminName,
          previousActive: widget.existing!.active,
          member: widget.existing!.copyWith(
            name: _name.text.trim(),
            role: _role,
            active: _active,
            service: _service,
            pending: false,
          ),
        );
      }
      return true;
    });
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _remove() async {
    final member = widget.existing!;
    final ok = await confirmDanger(
      context,
      title: s('usersRemoveTitle'),
      body: fill(s(widget.functions ? 'usersRemoveBodyFull' : 'usersRemoveBody'), {'email': member.email}),
      confirm: s('usersRemove'),
      cancel: s('cancel'),
    );
    if (!ok) return;
    final adminName = ref.read(syncControllerProvider.notifier).displayName;
    final done = await _run((session, team, cid) async {
      await team.removeMember(session, cid, adminName: adminName, member: member);
      return true;
    });
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _setPassword() async {
    final password = generateTempPassword();
    final done = await _run((session, team, cid) async {
      await team.setMemberPassword(session, cid, uid: widget.existing!.uid, password: password);
      return true;
    });
    if (done == true && mounted) await _showCredentials(widget.existing!.email, password);
  }

  Future<void> _showCredentials(String email, String password) async {
    final text = fill(s('usersCredentialsText'), {'email': email, 'password': password});
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s('usersCreatedTitle')),
        content: SelectableText(text),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(s('usersCopyCredentials')),
          ),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(s('ok'))),
        ],
      ),
    );
  }

  Future<void> _resetPassword() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(syncControllerProvider.notifier).sendPasswordReset(widget.existing!.email);
      messenger.showSnackBar(SnackBar(content: Text(fill(s('usersResetSent'), {'email': widget.existing!.email}))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s('syncErrorServer'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String t(String key) => tr(locale, key);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isNew ? t('usersAdd') : t('usersEdit'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 2),
            Text(widget.existing!.email, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: t('signupNameLabel'), prefixIcon: const Icon(Icons.badge_outlined)),
            validator: (v) => (v ?? '').trim().length < 2 ? t('signupInvalidName') : null,
          ),
          if (_isNew) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: t('syncEmail'), prefixIcon: const Icon(Icons.alternate_email)),
              validator: (v) => (v ?? '').trim().contains('@') ? null : t('syncInvalidEmail'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              decoration: InputDecoration(
                labelText: t('usersTempPassword'),
                helperText: t('usersTempPasswordHint'),
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  tooltip: t('usersGenerate'),
                  icon: const Icon(Icons.casino_outlined),
                  onPressed: () => setState(() => _password.text = generateTempPassword()),
                ),
              ),
              validator: (v) => (v ?? '').length < 6 ? t('syncErrorWeakPassword') : null,
            ),
          ],
          const SizedBox(height: 16),
          Text(t('usersRole'), style: const TextStyle(fontWeight: FontWeight.w800)),
          RoleRadioList(value: _role, enabled: !_isSelf, onChanged: (r) => setState(() => _role = r)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: serviceKeys.contains(_service) ? _service : '',
            decoration: InputDecoration(labelText: t('signupServiceLabel'), prefixIcon: const Icon(Icons.groups_outlined)),
            items: [
              DropdownMenuItem(value: '', child: Text(t('settingsServiceNone'))),
              for (final key in serviceKeys) DropdownMenuItem(value: key, child: Text(t(key))),
            ],
            onChanged: (v) => setState(() => _service = v ?? ''),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('usersActive')),
              subtitle: Text(
                t(_active ? 'usersActiveHint' : (widget.functions ? 'usersInactiveHintFull' : 'usersInactiveHint')),
              ),
              value: _active,
              activeTrackColor: accentColor,
              onChanged: _isSelf ? null : (v) => setState(() => _active = v),
            ),
            if (_isSelf) Text(t('usersSelfHint'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _resetPassword,
                  icon: const Icon(Icons.lock_reset_rounded, size: 18),
                  label: Text(t('usersResetPassword')),
                ),
                if (widget.functions && !_isSelf)
                  TextButton.icon(
                    onPressed: _busy ? null : _setPassword,
                    icon: const Icon(Icons.password_rounded, size: 18),
                    label: Text(t('usersSetPassword')),
                  ),
                if (!_isSelf)
                  TextButton.icon(
                    onPressed: _busy ? null : _remove,
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    icon: const Icon(Icons.person_remove_outlined, size: 18),
                    label: Text(t('usersRemove')),
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t(_isNew ? 'usersCreate' : 'wellsManageSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
