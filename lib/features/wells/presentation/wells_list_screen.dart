import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/wells_repository.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/report_tables.dart';
import '../../../core/filters/well_filter.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/well.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/responsive.dart';

/// Filtres de la liste des puits (conservés en changeant d'onglet).
final wellsListFilterProvider = StateProvider<WellFilter>((ref) => const WellFilter());

/// Exporte, pour les puits d'une zone (après filtres), les analyses, la
/// production + ratios et les interventions de la période choisie. Avec la
/// période par défaut ("Aujourd'hui", qui sert surtout à suivre la saisie du
/// jour), tout l'historique est exporté, comme avant l'ajout des filtres.
Future<void> _exportZone(WidgetRef ref, BuildContext context, String zoneLabel, List<Well> wells) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final data = ref.read(wellsControllerProvider);
  final selected = ref.read(wellsListFilterProvider).period;
  final period = selected.preset == PeriodPreset.today ? PeriodSelection.all : selected;
  final now = DateTime.now();
  final range = period.resolve(now);
  final wellIds = wells.map((w) => w.id).toSet();

  await runExport(
    context: context,
    locale: locale,
    baseName: '${zoneLabel}_${period.preset == PeriodPreset.all ? 'tout' : periodLabel(period, s)}',
    shareSubject: '$zoneLabel · ${periodLabel(period, s)}',
    tables: [
      analysesTable(
        data,
        data.records.where((r) => wellIds.contains(r.wellId) && period.contains(r.dateTime, now)).toList(),
        s,
        includeWell: true,
      ),
      productionTable(data, wells, s, from: range.start, to: range.end),
      interventionsTable(
        data,
        data.interventions.where((i) => wellIds.contains(i.wellId) && period.contains(i.date, now)).toList(),
        s,
      ),
    ],
  );
}

class WellsListScreen extends ConsumerStatefulWidget {
  const WellsListScreen({super.key});

  @override
  ConsumerState<WellsListScreen> createState() => _WellsListScreenState();
}

class _WellsListScreenState extends ConsumerState<WellsListScreen> {
  late final TextEditingController _searchController = TextEditingController(
    text: ref.read(wellsListFilterProvider).query,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    final data = ref.watch(wellsControllerProvider);
    final filter = ref.watch(wellsListFilterProvider);
    String s(String key) => tr(locale, key);
    void update(WellFilter f) => ref.read(wellsListFilterProvider.notifier).state = f;

    final filtered = data.wells.where(filter.matches).toList();
    final byGroup = <String, List<Well>>{};
    for (final well in filtered) {
      final key = well.group.trim().isEmpty ? s('statsUnassignedGroup') : well.group.trim();
      (byGroup[key] ??= []).add(well);
    }
    final groupNames = byGroup.keys.toList()..sort();
    for (final list in byGroup.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }

    final hasUnassigned = data.wells.any((w) => w.group.trim().isEmpty);
    final anyFilter =
        filter.query.trim().isNotEmpty ||
        filter.group != null ||
        filter.status != WellStatusFilter.all ||
        filter.period.preset != PeriodPreset.today;
    final now = DateTime.now();

    return Padding(
      padding: pagePadding(context, top: 8, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => update(filter.copyWith(query: v)),
            decoration: InputDecoration(
              hintText: s('wellsSearchHint'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: filter.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        update(filter.copyWith(query: ''));
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterPill<String?>(
                icon: Icons.map_outlined,
                title: s('filterField'),
                options: [
                  PillOption(null, s('filterFieldAll')),
                  for (final g in controller.groups) PillOption(g, g),
                  if (hasUnassigned) PillOption('', s('statsUnassignedGroup')),
                ],
                selected: filter.group,
                active: filter.group != null,
                onSelected: (v) => update(filter.copyWith(group: () => v)),
              ),
              FilterPill<WellStatusFilter>(
                icon: Icons.power_settings_new,
                title: s('filterStatus'),
                options: [for (final st in WellStatusFilter.values) PillOption(st, s(st.labelKey))],
                selected: filter.status,
                active: filter.status != WellStatusFilter.all,
                onSelected: (v) => update(filter.copyWith(status: v)),
              ),
              PeriodPill(
                value: filter.period,
                title: s('filterPeriod'),
                s: s,
                presets: const [
                  PeriodPreset.today,
                  PeriodPreset.days7,
                  PeriodPreset.days30,
                  PeriodPreset.days90,
                  PeriodPreset.year,
                  PeriodPreset.all,
                  PeriodPreset.custom,
                ],
                active: filter.period.preset != PeriodPreset.today,
                onChanged: (p) => update(filter.copyWith(period: p)),
              ),
              if (anyFilter)
                TextButton(
                  onPressed: () {
                    _searchController.clear();
                    update(const WellFilter());
                  },
                  child: Text(s('filterReset')),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${filtered.length} ${s(filtered.length > 1 ? 'wellsCountPlural' : 'wellsCountSingular')}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(s('wellsEmpty'), style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                : ListView(
                    children: [
                      for (final groupName in groupNames) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  groupName,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant),
                                ),
                              ),
                              IconButton(
                                tooltip: s('wellsExportZoneTooltip'),
                                icon: Icon(Icons.download_outlined, size: 18, color: scheme.onSurfaceVariant),
                                onPressed: () => _exportZone(ref, context, groupName, byGroup[groupName]!),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                        // Une colonne sur téléphone, 2 à 3 sur grand écran.
                        ResponsiveWrapGrid(
                          minItemWidth: 340,
                          children: [
                            for (final well in byGroup[groupName]!)
                              _WellCard(
                                well: well,
                                summary: _summary(well, filter.period, data, controller, s, now),
                                onTap: () => context.push('/wells/${well.id}'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Résumé affiché sous chaque puits : progression du jour, ou activité sur
  /// la période filtrée (nombre d'analyses, hors seuil, interventions).
  (String, Color?) _summary(
    Well well,
    PeriodSelection period,
    WellsState data,
    WellsController controller,
    String Function(String) s,
    DateTime now,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (period.preset == PeriodPreset.today) {
      final (done, total) = controller.todayProgress(well.id);
      if (total == 0) return ('', null);
      final color = done == total ? Colors.green.shade600 : accentColor;
      return ('$done/$total ${s('wellsTodaySuffix')}', color);
    }
    var count = 0;
    var outOfRange = 0;
    for (final r in data.records) {
      if (r.wellId != well.id || !period.contains(r.dateTime, now)) continue;
      count++;
      final type = controller.findType(r.typeId);
      if (type != null && type.isOutOfRange(r.value)) outOfRange++;
    }
    final interventions = data.interventions.where((i) => i.wellId == well.id && period.contains(i.date, now)).length;
    final parts = [
      '$count ${s('statsAnalysesCount')}',
      if (outOfRange > 0) '$outOfRange ${s('statsOutOfRangeCount')}',
      if (interventions > 0) '$interventions ${s('interventionsShort')}',
    ];
    return (parts.join(' · '), outOfRange > 0 ? scheme.error : scheme.onSurfaceVariant);
  }
}

class _WellCard extends ConsumerWidget {
  final Well well;
  final (String, Color?) summary;
  final VoidCallback onTap;

  const _WellCard({required this.well, required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (well.active ? accentColor : scheme.outline).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.water_drop_outlined, color: well.active ? accentColor : scheme.outline),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(well.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(well.code, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _StatusChip(
                          label: s(well.active ? 'wellStatusActive' : 'wellStatusStopped'),
                          color: well.active ? Colors.green.shade600 : scheme.outline,
                        ),
                        if (summary.$1.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              summary.$1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: summary.$2, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
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

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
