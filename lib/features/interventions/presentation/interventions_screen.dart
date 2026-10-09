import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/report_tables.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/widgets/series_chart.dart';
import '../../../core/widgets/responsive.dart';
import 'intervention_form_sheet.dart';
import 'widgets/intervention_ui.dart';

/// Journal complet des interventions d'un puits : date, type, coût,
/// résultat — avec total des coûts et export.
class InterventionsScreen extends ConsumerWidget {
  final String wellId;
  const InterventionsScreen({super.key, required this.wellId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final well = controller.findWell(wellId);
    if (well == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(s('wellsEmpty'))));
    }
    final interventions = controller.interventionsForWell(wellId);

    final totals = <String, double>{};
    for (final i in interventions) {
      if (i.cost != null) totals[i.currency] = (totals[i.currency] ?? 0) + i.cost!;
    }
    final number = NumberFormat.decimalPattern(locale.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text('${s('interventionsTitle')} · ${well.name}'),
        actions: [
          IconButton(
            tooltip: s('exportTooltip'),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => runExport(
              context: context,
              locale: locale,
              baseName: '${well.code}_interventions',
              tables: [interventionsTable(data, interventions, s)],
              shareSubject: '${s('interventionsTitle')} · ${well.name}',
            ),
          ),
        ],
      ),
      floatingActionButton: role.canEnterData
          ? FloatingActionButton.extended(
              onPressed: () => showInterventionForm(context, wellId: wellId),
              icon: const Icon(Icons.add),
              label: Text(s('interventionAdd')),
            )
          : null,
      body: interventions.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.construction, size: 48, color: scheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      s('interventionsEmpty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: pagePadding(context, top: 8, bottom: 120),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SummaryValue(
                            label: s('interventionsCount'),
                            value: '${interventions.length}',
                          ),
                        ),
                        Expanded(
                          child: _SummaryValue(
                            label: s('interventionsTotalCost'),
                            value: totals.isEmpty
                                ? '—'
                                : totals.entries.map((e) => '${number.format(e.value)} ${e.key}').join('\n'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < interventions.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                        InterventionTile(
                          intervention: interventions[i],
                          locale: locale,
                          s: s,
                          onTap: role.canEnterData
                              ? () => showInterventionForm(context, wellId: wellId, existing: interventions[i])
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: interventionMarkerColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        s('interventionsMarkersHint'),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ],
    );
  }
}
