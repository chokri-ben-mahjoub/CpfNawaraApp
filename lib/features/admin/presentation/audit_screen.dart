import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/sync/firebase_rest.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/team/team_service.dart';
import '../../../core/widgets/hero_header.dart';
import 'audit_detail_screen.dart';
import '../../../core/widgets/responsive.dart';
import '../../setup/presentation/widgets/team_account_form.dart';
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
  'plant_params' => 'auditTableParams',
  'plant_profiles' => 'auditTableProfiles',
  'stock_items' => 'auditTableStockItems',
  'stock_movements' => 'auditTableStockMovements',
  'users' => 'auditTableUsers',
  _ => table,
};

String auditActionKey(String action) => switch (action) {
  'save' => 'auditActionSave',
  'save_create' => 'auditActionCreate',
  'save_update' => 'auditActionUpdate',
  'delete' => 'auditActionDelete',
  'user_create' => 'auditActionUserCreate',
  'user_update' => 'auditActionUserUpdate',
  'setup' => 'auditActionSetup',
  'user_remove' => 'auditActionUserRemove',
  'invite_create' => 'auditActionInviteCreate',
  'invite_use' => 'auditActionInviteUse',
  _ => action,
};

/// Action affichée : un enregistrement devient « Création » ou
/// « Modification » quand on le sait.
String auditEffectiveAction(AuditEntry e) =>
    e.action == 'save' && e.op.isNotEmpty ? 'save_${e.op}' : e.action;

/// Page vers laquelle mène une entrée (puits, point de prélèvement, article),
/// ou null (suppression, utilisateur, paramètre...).
String? auditRoute(AuditEntry e) {
  if (e.action == 'delete' || e.refId.isEmpty) return null;
  return switch (e.table) {
    'wells' || 'analysis_records' || 'interventions' => '/wells/${e.refId}',
    'sample_points' ||
    'plant_analyses' ||
    'plant_thresholds' => '/plant/point/${e.refId}',
    'stock_items' || 'stock_movements' => '/stock/${e.refId}',
    _ => null,
  };
}

/// Texte d'audit sans données d'image : toute longue suite base64 devient
/// « image » (les anciennes entrées contiennent encore l'image brute).
String auditSafeText(String text, String Function(String) t) {
  final image = t('auditImageValue');
  return text
      .replaceAll('[image]', image)
      .replaceAll(RegExp(r'data:image/[a-z+]+;base64,[A-Za-z0-9+/=]*'), image)
      .replaceAll(RegExp(r'[A-Za-z0-9+/=]{80,}…?'), image);
}

bool auditIsImageChange(AuditChange c) {
  bool img(String v) =>
      v == '[image]' ||
      v.startsWith('data:image') ||
      RegExp(r'^[A-Za-z0-9+/=]{50,}…?$').hasMatch(v);
  return c.field.endsWith('_b64') ||
      c.field == 'photo' ||
      img(c.before) ||
      img(c.after);
}

String auditFieldLabel(String key, String Function(String) t) {
  final translated = t('auditField_$key');
  if (translated != 'auditField_$key') return translated;
  final spaced = key.replaceAll('_', ' ').trim();
  return spaced.isEmpty ? key : spaced[0].toUpperCase() + spaced.substring(1);
}

Color auditActionColor(String action, ColorScheme scheme) => switch (action) {
  'delete' || 'user_remove' => scheme.error,
  'save_create' ||
  'user_create' ||
  'invite_create' ||
  'setup' => const Color(0xFF2E9E5B),
  'save_update' || 'save' || 'user_update' => const Color(0xFF1E88E5),
  _ => scheme.onSurfaceVariant,
};

IconData auditActionIcon(String action) => switch (action) {
  'delete' || 'user_remove' => Icons.delete_outline_rounded,
  'save_create' ||
  'user_create' ||
  'invite_create' => Icons.add_circle_outline_rounded,
  'invite_use' => Icons.login_rounded,
  'setup' => Icons.rocket_launch_outlined,
  _ => Icons.edit_outlined,
};

/// Traçabilité : qui a modifié quoi et quand (équipe), avec le détail
/// « avant → après », des filtres, un export et un lien vers l'élément.
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
  String? _action;
  String _period = 'all';
  DateTimeRange? _range;
  int _limit = 300;
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
    if (controller.team == null || !ref.read(syncControllerProvider).isSignedIn)
      return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await controller.freshSession();
      final cid = ref.read(syncControllerProvider).company?.id;
      if (cid == null) return;
      final entries = await controller.team!.audit(session, cid, limit: _limit);
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Bornes [début, fin[ de la période choisie (null = pas de borne).
  (DateTime?, DateTime?) _bounds() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      'today' => (today, null),
      '7d' => (today.subtract(const Duration(days: 6)), null),
      '30d' => (today.subtract(const Duration(days: 29)), null),
      'custom' when _range != null => (
        DateTime(_range!.start.year, _range!.start.month, _range!.start.day),
        DateTime(
          _range!.end.year,
          _range!.end.month,
          _range!.end.day,
        ).add(const Duration(days: 1)),
      ),
      _ => (null, null),
    };
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() {
        _range = picked;
        _period = 'custom';
      });
    }
  }

  void _resetFilters() => setState(() {
    _user = null;
    _table = null;
    _action = null;
    _period = 'all';
    _range = null;
    _search.clear();
  });

  List<AuditEntry> _filtered(List<AuditEntry> all) {
    final query = _search.text.trim().toLowerCase();
    final (from, to) = _bounds();
    return all
        .where((e) => _user == null || e.email == _user)
        .where((e) => _table == null || e.table == _table)
        .where((e) => _action == null || auditEffectiveAction(e) == _action)
        .where((e) => from == null || !e.at.isBefore(from))
        .where((e) => to == null || e.at.isBefore(to))
        .where(
          (e) =>
              query.isEmpty ||
              e.label.toLowerCase().contains(query) ||
              e.docId.toLowerCase().contains(query) ||
              e.name.toLowerCase().contains(query) ||
              e.email.toLowerCase().contains(query) ||
              e.changes.any(
                (c) =>
                    c.before.toLowerCase().contains(query) ||
                    c.after.toLowerCase().contains(query),
              ),
        )
        .toList();
  }

  Future<void> _export(List<AuditEntry> entries) async {
    final locale = ref.read(localeProvider);
    String t(String key) => tr(locale, key);
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    String changesText(AuditEntry e) => e.changes
        .map(
          (c) => auditIsImageChange(c)
              ? '${auditFieldLabel(c.field, t)}: ${t('auditImageChanged')}'
              : '${auditFieldLabel(c.field, t)}: ${c.before.isEmpty ? '—' : c.before} → ${c.after.isEmpty ? '—' : c.after}',
        )
        .join(' ; ');
    await runExport(
      context: context,
      locale: locale,
      baseName: 'tracabilite',
      shareSubject: t('adminAudit'),
      tables: [
        ExportTable(
          name: t('adminAudit'),
          headers: [
            t('colDate'),
            t('auditUser'),
            t('auditAction'),
            t('auditTable'),
            t('auditDetail'),
            t('auditChanges'),
          ],
          rows: [
            for (final e in entries)
              [
                dateFormat.format(e.at),
                e.name.isEmpty ? e.email : e.name,
                t(auditActionKey(auditEffectiveAction(e))),
                t(auditTableKey(e.table)),
                auditSafeText(e.label, t),
                changesText(e),
              ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final sync = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    String t(String key) => tr(locale, key);

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
    final users = {
      for (final e in all) e.email: e.name.isEmpty ? e.email : e.name,
    };
    final tables = {for (final e in all) e.table}.toList()..sort();
    final actions = {for (final e in all) auditEffectiveAction(e)}.toList()
      ..sort();
    final entries = _filtered(all);
    final filtered =
        _user != null ||
        _table != null ||
        _action != null ||
        _period != 'all' ||
        _search.text.trim().isNotEmpty;
    final problem = _error == null ? null : projectProblemOf(_error!);
    final shortDate = DateFormat('d MMM', locale.languageCode);

    // Regroupement par jour.
    final byDay = <DateTime, List<AuditEntry>>{};
    for (final e in entries) {
      byDay
          .putIfAbsent(DateTime(e.at.year, e.at.month, e.at.day), () => [])
          .add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final today = DateTime.now();
    String dayLabel(DateTime d) {
      final diff = DateTime(
        today.year,
        today.month,
        today.day,
      ).difference(d).inDays;
      if (diff == 0) return t('auditPeriod_today');
      if (diff == 1) return t('auditYesterday');
      return DateFormat('EEEE d MMMM yyyy', locale.languageCode).format(d);
    }

    final creations = all
        .where((e) => auditEffectiveAction(e) == 'save_create')
        .length;
    final deletions = all.where((e) => e.action == 'delete').length;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('adminAudit')),
        actions: [
          IconButton(
            tooltip: t('auditExport'),
            onPressed: entries.isEmpty ? null : () => _export(entries),
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: t('refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: pagePadding(context, top: 8, bottom: 40),
          children: [
            HeroHeader(
              icon: Icons.history_rounded,
              title: t('adminAudit'),
              subtitle: t('auditIntro'),
              pillLabel: filtered
                  ? fill(t('auditCount'), {
                      'n': '${entries.length}',
                      'total': '${all.length}',
                    })
                  : null,
              pillColor: const Color(0xFF1E88E5),
              stats: [
                HeroStat(value: '${all.length}', label: t('auditStatEntries')),
                HeroStat(value: '${users.length}', label: t('auditStatUsers')),
                HeroStat(value: '$creations', label: t('auditStatCreated')),
                HeroStat(
                  value: '$deletions',
                  label: t('auditStatDeleted'),
                  valueColor: deletions > 0 ? const Color(0xFFFF8A80) : null,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: t('auditSearch'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in const ['all', 'today', '7d', '30d'])
                          ChoiceChip(
                            label: Text(t('auditPeriod_$p')),
                            selected: _period == p,
                            onSelected: (_) => setState(() => _period = p),
                          ),
                        ChoiceChip(
                          avatar: const Icon(Icons.date_range, size: 18),
                          label: Text(
                            _period == 'custom' && _range != null
                                ? '${shortDate.format(_range!.start)} → ${shortDate.format(_range!.end)}'
                                : t('auditPeriod_custom'),
                          ),
                          selected: _period == 'custom',
                          onSelected: (_) => _pickRange(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<String?>(
                          value: _user,
                          hint: Text(t('auditAllUsers')),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(t('auditAllUsers')),
                            ),
                            for (final e in users.entries)
                              DropdownMenuItem<String?>(
                                value: e.key,
                                child: Text(e.value),
                              ),
                          ],
                          onChanged: (v) => setState(() => _user = v),
                        ),
                        DropdownButton<String?>(
                          value: _action,
                          hint: Text(t('auditAllActions')),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(t('auditAllActions')),
                            ),
                            for (final a in actions)
                              DropdownMenuItem<String?>(
                                value: a,
                                child: Text(t(auditActionKey(a))),
                              ),
                          ],
                          onChanged: (v) => setState(() => _action = v),
                        ),
                        DropdownButton<String?>(
                          value: _table,
                          hint: Text(t('auditAllTables')),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(t('auditAllTables')),
                            ),
                            for (final table in tables)
                              DropdownMenuItem<String?>(
                                value: table,
                                child: Text(t(auditTableKey(table))),
                              ),
                          ],
                          onChanged: (v) => setState(() => _table = v),
                        ),
                        if (filtered)
                          TextButton.icon(
                            onPressed: _resetFilters,
                            icon: const Icon(
                              Icons.filter_alt_off_outlined,
                              size: 18,
                            ),
                            label: Text(t('auditResetFilters')),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading && _entries == null) const SkeletonList(),
            if (_error != null)
              problem != null && controller.config != null
                  ? ProjectProblemCard(
                      problem: problem,
                      config: controller.config!,
                    )
                  : Text(
                      _error is SyncNetworkException
                          ? t('syncOffline')
                          : t('syncErrorServer'),
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            if (_entries != null && entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    t('auditEmpty'),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            for (final day in days) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                child: Row(
                  children: [
                    Text(
                      dayLabel(day),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '${byDay[day]!.length}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final e in byDay[day]!)
                _AuditCard(entry: e, t: t, locale: locale, all: all),
            ],
            if (_entries != null && all.length >= _limit)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () {
                            _limit += 500;
                            _load();
                          },
                    icon: const Icon(Icons.expand_more),
                    label: Text(t('auditLoadMore')),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Carte d'une entrée : avatar, action, élément, heure ; dépliable pour voir
/// le détail « avant → après ».
class _AuditCard extends StatelessWidget {
  final AuditEntry entry;
  final String Function(String) t;
  final Locale locale;
  final List<AuditEntry> all;
  const _AuditCard({
    required this.entry,
    required this.t,
    required this.locale,
    required this.all,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = entry;
    final action = auditEffectiveAction(e);
    final color = auditActionColor(action, scheme);
    final who = e.name.isEmpty ? e.email : e.name;
    final initials = who.trim().isEmpty
        ? '?'
        : who
              .trim()
              .split(RegExp(r'[\s@.]+'))
              .where((p) => p.isNotEmpty)
              .take(2)
              .map((p) => p[0].toUpperCase())
              .join();
    final route = auditRoute(e);
    final time = DateFormat('HH:mm', locale.languageCode).format(e.at);

    final header = Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.95),
                color.withValues(alpha: 0.65),
              ],
            ),
          ),
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      who,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(auditActionIcon(action), size: 13, color: color),
                        const SizedBox(width: 4),
                        Text(
                          t(auditActionKey(action)),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${t(auditTableKey(e.table))} · ${auditSafeText(e.label, t)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              time,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (route != null)
              IconButton(
                tooltip: t('auditOpen'),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.open_in_new_rounded,
                  size: 19,
                  color: scheme.primary,
                ),
                onPressed: () => context.push(route),
              ),
          ],
        ),
      ],
    );

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push('/admin/audit/detail', extra: AuditDetailArgs(e, all)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              if (e.changes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 54, top: 6),
                  child: Text(
                    fill(t('auditChangedFields'), {'n': '${e.changes.length}'}),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
