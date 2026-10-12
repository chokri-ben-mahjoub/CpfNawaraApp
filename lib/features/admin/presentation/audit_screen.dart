import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/sync/firebase_rest.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/team/team_service.dart';
import '../../../core/widgets/responsive.dart';
import '../../setup/presentation/widgets/team_account_form.dart';
import 'widgets/admin_widgets.dart';
import '../../../core/widgets/app_loader.dart';

/// Libellé traduit d'une table de données (journal d'audit).
String auditTableKey(String table) => switch (table) {
  'wells' => 'auditTableWells',
  'analysis_types' => 'auditTableTypes',
  'analysis_records' => 'auditTableRecords',
  'interventions' => 'auditTableInterventions',
  'sample_points' => 'auditTablePoints',
  'plant_analyses' => 'auditTablePlantAnalyses',
  'plant_thresholds' => 'auditTableThresholds',
  'app_config' => 'auditTableConfig',
  'plant_circuits' => 'auditTableCircuits',
  'plant_schemas' => 'auditTableSchemas',
  'users' => 'auditTableUsers',
  _ => table,
};

String auditActionKey(String action) => switch (action) {
  'save' => 'auditActionSave',
  'delete' => 'auditActionDelete',
  'user_create' => 'auditActionUserCreate',
  'user_update' => 'auditActionUserUpdate',
  'setup' => 'auditActionSetup',
  'user_remove' => 'auditActionUserRemove',
  'invite_create' => 'auditActionInviteCreate',
  'invite_use' => 'auditActionInviteUse',
  _ => action,
};

/// Journal d'audit : qui a modifié quoi et quand (équipe).
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  List<AuditEntry>? _entries;
  Object? _error;
  bool _loading = false;
  String? _user;
  String? _table;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final controller = ref.read(syncControllerProvider.notifier);
    if (controller.team == null || !ref.read(syncControllerProvider).isSignedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await controller.freshSession();
      final cid = ref.read(syncControllerProvider).company?.id;
      if (cid == null) return;
      final entries = await controller.team!.audit(session, cid);
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final sync = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    String t(String key) => tr(locale, key);
    final dateFormat = DateFormat('d MMM yyyy HH:mm', locale.languageCode);

    if (controller.team == null || !sync.isSignedIn || sync.company == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('adminAudit'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              t('adminAuditLocal'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    final all = _entries ?? const <AuditEntry>[];
    final users = {for (final e in all) e.email: e.name.isEmpty ? e.email : e.name};
    final tables = {for (final e in all) e.table}.toList()..sort();
    final query = _search.text.trim().toLowerCase();
    final entries = all
        .where((e) => _user == null || e.email == _user)
        .where((e) => _table == null || e.table == _table)
        .where((e) => query.isEmpty || e.label.toLowerCase().contains(query) || e.docId.toLowerCase().contains(query))
        .toList();
    final problem = _error == null ? null : projectProblemOf(_error!);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('adminAudit')),
        actions: [
          IconButton(tooltip: t('refresh'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: pagePadding(context, top: 8, bottom: 40),
          children: [
            Text(t('auditIntro'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: t('auditSearch'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                DropdownButton<String?>(
                  value: _user,
                  hint: Text(t('auditAllUsers')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(t('auditAllUsers'))),
                    for (final e in users.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _user = v),
                ),
                DropdownButton<String?>(
                  value: _table,
                  hint: Text(t('auditAllTables')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(t('auditAllTables'))),
                    for (final table in tables)
                      DropdownMenuItem<String?>(value: table, child: Text(t(auditTableKey(table)))),
                  ],
                  onChanged: (v) => setState(() => _table = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading && _entries == null)
              const SkeletonList(),
            if (_error != null)
              problem != null && controller.config != null
                  ? ProjectProblemCard(problem: problem, config: controller.config!)
                  : Text(
                      _error is SyncNetworkException ? t('syncOffline') : t('syncErrorServer'),
                      style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
                    ),
            if (_entries != null && entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(t('auditEmpty'), style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ),
            if (entries.isNotEmpty)
              AdminTable<AuditEntry>(
                items: entries,
                columns: [
                  AdminColumn(t('colDate'), (e) => Text(dateFormat.format(e.at))),
                  AdminColumn(
                    t('auditUser'),
                    (e) => Text(e.name.isEmpty ? e.email : e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  AdminColumn(t('auditAction'), (e) => _ActionText(e.action)),
                  AdminColumn(t('auditTable'), (e) => Text(t(auditTableKey(e.table)))),
                  AdminColumn(
                    t('auditDetail'),
                    (e) => ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(e.label, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                card: (context, e) => AdminCard(
                  leading: IconBadge(
                    e.action == 'delete'
                        ? Icons.delete_outline
                        : (e.table == 'users' ? Icons.person_outline : Icons.edit_outlined),
                    color: e.action == 'delete' ? scheme.error : const Color(0xFF1E88E5),
                  ),
                  title: '${e.name.isEmpty ? e.email : e.name} · ${t(auditActionKey(e.action))}',
                  subtitle: '${t(auditTableKey(e.table))} — ${e.label}\n${dateFormat.format(e.at)}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionText extends ConsumerWidget {
  final String action;
  const _ActionText(this.action);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      tr(ref.watch(localeProvider), auditActionKey(action)),
      style: TextStyle(fontWeight: FontWeight.w700, color: action == 'delete' ? scheme.error : null),
    );
  }
}
