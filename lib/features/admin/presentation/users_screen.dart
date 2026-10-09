import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/sync/firebase_rest.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/team/team_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../settings/presentation/sync_section.dart';
import '../../setup/presentation/widgets/team_account_form.dart';
import 'widgets/admin_widgets.dart';
import '../../../core/widgets/app_loader.dart';

/// Mot de passe provisoire lisible (sans caractères ambigus).
String generateTempPassword([int length = 10]) {
  const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
}

/// Utilisateurs et rôles de l'équipe (documents `users/{uid}`).
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  List<TeamMember>? _members;
  Object? _error;
  bool _loading = false;

  String s(String key) => tr(ref.read(localeProvider), key);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final sync = ref.read(syncControllerProvider.notifier);
    if (sync.team == null || !ref.read(syncControllerProvider).isSignedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await sync.freshSession();
      final members = await sync.team!.listMembers(session);
      if (mounted) setState(() => _members = members);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({TeamMember? member, bool approve = false}) async {
    final changed = await showAdminSheet<bool>(
      context,
      builder: (sheetContext) => _MemberForm(existing: member, approve: approve),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final sync = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    String t(String key) => tr(locale, key);

    if (controller.team == null || !sync.isSignedIn) {
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
                  Text(
                    t('usersLocalBody'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
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
    final pending = members.where((m) => m.pending && !m.active).toList();
    final others = members.where((m) => !(m.pending && !m.active)).toList();
    final problem = _error == null ? null : projectProblemOf(_error!);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('adminUsers')),
        actions: [
          IconButton(tooltip: t('refresh'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(t('usersAdd')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: pagePadding(context, top: 8, bottom: 120),
          children: [
            if (_loading && _members == null)
              const SkeletonList(),
            if (_error != null) ...[
              if (problem != null && controller.config != null)
                ProjectProblemCard(problem: problem, config: controller.config!)
              else
                Text(
                  _error is SyncNetworkException ? t('syncOffline') : t('syncErrorServer'),
                  style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
                ),
            ],
            if (pending.isNotEmpty) ...[
              AdminSectionTitle('${t('usersPending')} (${pending.length})'),
              for (final m in pending) ...[
                AdminCard(
                  leading: const IconBadge(Icons.hourglass_top_rounded),
                  title: m.name.isEmpty ? m.email : m.name,
                  subtitle: m.email,
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
                    onPressed: () => _openEditor(member: m, approve: true),
                    child: Text(t('usersApprove')),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
            if (_members != null) ...[
              AdminSectionTitle('${t('usersMembers')} (${others.length})'),
              AdminTable<TeamMember>(
                items: others,
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

/// Création, modification ou validation d'un membre.
class _MemberForm extends ConsumerStatefulWidget {
  final TeamMember? existing;
  final bool approve;
  const _MemberForm({this.existing, this.approve = false});

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
    _role = widget.approve ? UserRole.operator : (m?.role ?? UserRole.operator);
    _active = widget.approve ? true : (m?.active ?? true);
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(syncControllerProvider.notifier);
    final team = controller.team!;
    final adminName = ref.read(syncControllerProvider).member?.name ?? '';
    try {
      final session = await controller.freshSession();
      if (_isNew) {
        final member = await team.createMember(
          session,
          adminName: adminName,
          email: _email.text.trim(),
          password: _password.text,
          name: _name.text.trim(),
          role: _role,
          service: _service,
        );
        if (!mounted) return;
        await _showCredentials(member.email, _password.text);
      } else {
        await team.updateMember(
          session,
          adminName: adminName,
          member: widget.existing!.copyWith(
            name: _name.text.trim(),
            role: _role,
            active: _active,
            service: _service,
            pending: false,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on SyncAuthException catch (e) {
      setState(() => _error = s(authErrorKey(e.code)));
    } on SyncNetworkException {
      setState(() => _error = s('syncOffline'));
    } catch (_) {
      setState(() => _error = s('syncErrorServer'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      await ref.read(syncControllerProvider.notifier).team!.sendPasswordReset(widget.existing!.email);
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
    final title = _isNew ? t('usersAdd') : (widget.approve ? t('usersApproveTitle') : t('usersEdit'));

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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
          const SizedBox(height: 8),
          RadioGroup<UserRole>(
            groupValue: _role,
            onChanged: (v) {
              if (!_isSelf) setState(() => _role = v ?? _role);
            },
            child: Column(
              children: [
                for (final role in UserRole.values)
                  RadioListTile<UserRole>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: role,
                    enabled: !_isSelf,
                    title: Text(t(role.labelKey), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(t(role.descriptionKey)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: serviceKeys.contains(_service) ? _service : '',
            decoration: InputDecoration(
              labelText: t('signupServiceLabel'),
              prefixIcon: const Icon(Icons.groups_outlined),
            ),
            items: [
              DropdownMenuItem(value: '', child: Text(t('settingsServiceNone'))),
              for (final key in serviceKeys) DropdownMenuItem(value: key, child: Text(t(key))),
            ],
            onChanged: (v) => setState(() => _service = v ?? ''),
          ),
          if (!_isNew && !widget.approve) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('usersActive')),
              subtitle: Text(t(_active ? 'usersActiveHint' : 'usersInactiveHint')),
              value: _active,
              activeTrackColor: accentColor,
              onChanged: _isSelf ? null : (v) => setState(() => _active = v),
            ),
            if (_isSelf) Text(t('usersSelfHint'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _busy ? null : _resetPassword,
                icon: const Icon(Icons.lock_reset_rounded, size: 18),
                label: Text(t('usersResetPassword')),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      t(_isNew ? 'usersCreate' : (widget.approve ? 'usersApprove' : 'wellsManageSave')),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          if (widget.approve) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _active = false);
                      final controller = ref.read(syncControllerProvider.notifier);
                      try {
                        final session = await controller.freshSession();
                        await controller.team!.updateMember(
                          session,
                          adminName: ref.read(syncControllerProvider).member?.name ?? '',
                          member: widget.existing!.copyWith(active: false, pending: false, role: UserRole.reader),
                        );
                        if (context.mounted) Navigator.of(context).pop(true);
                      } catch (_) {
                        setState(() => _error = s('syncErrorServer'));
                      }
                    },
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              child: Text(t('usersRefuse')),
            ),
          ],
        ],
      ),
    );
  }
}
