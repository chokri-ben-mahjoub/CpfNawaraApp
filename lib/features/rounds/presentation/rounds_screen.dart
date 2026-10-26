import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/rounds_repository.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/models/well.dart';
import '../../../core/models/well_round.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';

/// Jour affiché dans l'onglet Tournées.
final roundsDayProvider = StateProvider<DateTime>((ref) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
});

/// Vue de l'onglet : fiches par puits, ou tableau complet du jour.
final roundsTableViewProvider = StateProvider<bool>((ref) => false);

String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String roundValueText(WellRound r, RoundField f, String Function(String) s) {
  if (f.isNumber) {
    final v = r.number(f.key);
    return v == null ? '' : _fmt(v);
  }
  final c = r.choice(f.key);
  return c == null ? '' : s(c);
}

/// Onglet « Tournées » : relevés de l'opérateur de puits du jour (par puits
/// et pour le site), saisie, tableau complet et export.
class RoundsScreen extends ConsumerWidget {
  const RoundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final day = ref.watch(roundsDayProvider);
    final tableView = ref.watch(roundsTableViewProvider);
    final rounds = ref.watch(roundsControllerProvider);
    final wells = ref.watch(wellsControllerProvider).wells.where((w) => w.active).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    String s(String key) => tr(locale, key);

    final today = DateTime.now();
    final isToday = day == DateTime(today.year, today.month, today.day);
    final filled = wells.where((w) => rounds.on(w.id, day).isNotEmpty).length;

    return ListView(
      padding: pagePadding(context, top: 8, bottom: 110),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: s('roundsPrevDay'),
              icon: const Icon(Icons.chevron_left),
              onPressed: () => ref.read(roundsDayProvider.notifier).state = day.subtract(const Duration(days: 1)),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(today.year, today.month, today.day),
                  );
                  if (picked != null) {
                    ref.read(roundsDayProvider.notifier).state = DateTime(picked.year, picked.month, picked.day);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    '${isToday ? '${s('roundsToday')} · ' : ''}${DateFormat('EEE d MMM yyyy', locale.languageCode).format(day)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: s('roundsNextDay'),
              icon: const Icon(Icons.chevron_right),
              onPressed: isToday
                  ? null
                  : () => ref.read(roundsDayProvider.notifier).state = day.add(const Duration(days: 1)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                '$filled / ${wells.length} ${s('roundsWellsDone')}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
              ),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, icon: const Icon(Icons.view_agenda_outlined), label: Text(s('roundsViewCards'))),
                ButtonSegment(value: true, icon: const Icon(Icons.table_chart_outlined), label: Text(s('roundsViewTable'))),
              ],
              selected: {tableView},
              onSelectionChanged: (v) => ref.read(roundsTableViewProvider.notifier).state = v.first,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (tableView)
          _RoundsTable(wells: wells, day: day)
        else ...[
          for (final w in wells) _WellRoundCard(well: w, day: day, canEnter: role.canEnterData),
          _SiteRoundCard(day: day, canEnter: role.canEnterData),
        ],
      ],
    );
  }
}

Color _statusColor(String? status, ColorScheme scheme) => switch (status) {
  'roundOpen' => Colors.green.shade600,
  'roundClosed' => scheme.error,
  _ => scheme.outline,
};

class _WellRoundCard extends ConsumerWidget {
  final Well well;
  final DateTime day;
  final bool canEnter;
  const _WellRoundCard({required this.well, required this.day, required this.canEnter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final rounds = ref.watch(roundsControllerProvider).on(well.id, day);
    String s(String key) => tr(locale, key);
    final last = rounds.isEmpty ? null : rounds.last;
    final status = last?.choice('well_status');
    final color = _statusColor(status, scheme);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${well.name} · ${well.code}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
                  child: Text(
                    status == null ? s('roundNotDone') : s(status),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final r in rounds)
                  ActionChip(
                    avatar: Icon(r.photo == null ? Icons.schedule : Icons.photo_camera_outlined, size: 16),
                    label: Text(r.time),
                    onPressed: () => context.push('/rounds/entry?wellId=${well.id}&date=${_key(day)}&roundId=${r.id}'),
                  ),
                if (canEnter)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(s(rounds.isEmpty ? 'roundsEnter' : 'roundsAddAnother')),
                    backgroundColor: accentColor.withValues(alpha: 0.14),
                    onPressed: () => context.push('/rounds/entry?wellId=${well.id}&date=${_key(day)}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _SiteRoundCard extends ConsumerWidget {
  final DateTime day;
  final bool canEnter;
  const _SiteRoundCard({required this.day, required this.canEnter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final rounds = ref.watch(roundsControllerProvider).on(siteRoundId, day);
    String s(String key) => tr(locale, key);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.apartment_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(s('roundsSite'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final r in rounds)
                  ActionChip(
                    avatar: Icon(r.photo == null ? Icons.schedule : Icons.photo_camera_outlined, size: 16),
                    label: Text(r.time),
                    onPressed: () => context.push('/rounds/entry?wellId=&date=${_key(day)}&roundId=${r.id}'),
                  ),
                if (canEnter)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(s(rounds.isEmpty ? 'roundsEnter' : 'roundsAddAnother')),
                    backgroundColor: accentColor.withValues(alpha: 0.14),
                    onPressed: () => context.push('/rounds/entry?wellId=&date=${_key(day)}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tableau du jour, comme la feuille de tournée : une ligne par puits et par
/// heure, une colonne par paramètre ; puis les relevés du site.
class _RoundsTable extends ConsumerWidget {
  final List<Well> wells;
  final DateTime day;
  const _RoundsTable({required this.wells, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final state = ref.watch(roundsControllerProvider);
    String s(String key) => tr(locale, key);
    final names = {for (final w in wells) w.id: w.name};
    final wellRounds = [for (final r in state.allOn(day)) if (!r.isSite && names.containsKey(r.wellId)) r];
    final site = state.on(siteRoundId, day);

    if (wellRounds.isEmpty && site.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text(s('roundsNothing'), style: TextStyle(color: scheme.onSurfaceVariant))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wellRounds.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              headingRowHeight: 64,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 44,
              columns: [
                DataColumn(label: Text(s('roundsColWell'))),
                DataColumn(label: Text(s('roundsColTime'))),
                for (final f in wellRoundFields)
                  DataColumn(
                    label: SizedBox(
                      width: 78,
                      child: Text(
                        f.unit.isEmpty ? s(f.labelKey) : '${s(f.labelKey)} (${f.unit})',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
              rows: [
                for (final r in wellRounds)
                  DataRow(
                    cells: [
                      DataCell(Text(names[r.wellId] ?? '', style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(Text(r.time)),
                      for (final f in wellRoundFields)
                        DataCell(
                          Text(
                            roundValueText(r, f, s),
                            style: f.isNumber
                                ? null
                                : TextStyle(color: _statusColor(r.choice(f.key), scheme), fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        if (site.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(s('roundsSite'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 6),
          for (final r in site)
            for (final f in siteRoundFields)
              if (roundValueText(r, f, s).isNotEmpty)
                ListTile(
                  dense: true,
                  title: Text(s(f.labelKey)),
                  trailing: Text(
                    '${roundValueText(r, f, s)} ${f.unit}'.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(r.time),
                ),
        ],
      ],
    );
  }
}

/// Exporte les tournées du jour affiché (PDF / Excel / CSV) : le tableau des
/// puits et celui du site.
Future<void> exportRounds(WidgetRef ref, BuildContext context) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final day = ref.read(roundsDayProvider);
  final state = ref.read(roundsControllerProvider);
  final wells = {for (final w in ref.read(wellsControllerProvider).wells) w.id: w.name};
  final all = state.allOn(day);

  await runExport(
    context: context,
    locale: locale,
    baseName: 'tournee_${_key(day)}',
    tables: [
      ExportTable(
        name: '${s('roundsTitle')} ${DateFormat('dd/MM/yyyy').format(day)}',
        headers: [
          s('roundsColWell'),
          s('roundsColTime'),
          for (final f in wellRoundFields) f.unit.isEmpty ? s(f.labelKey) : '${s(f.labelKey)} (${f.unit})',
          s('roundsColOperator'),
        ],
        rows: [
          for (final r in all)
            if (!r.isSite)
              [
                wells[r.wellId] ?? r.wellId,
                r.time,
                for (final f in wellRoundFields) f.isNumber ? r.number(f.key) : roundValueText(r, f, s),
                r.operatorName,
              ],
        ],
      ),
      ExportTable(
        name: s('roundsSite'),
        headers: [s('roundsColTime'), for (final f in siteRoundFields) f.unit.isEmpty ? s(f.labelKey) : '${s(f.labelKey)} (${f.unit})'],
        rows: [
          for (final r in all)
            if (r.isSite) [r.time, for (final f in siteRoundFields) f.isNumber ? r.number(f.key) : roundValueText(r, f, s)],
        ],
      ),
    ],
  );
}
