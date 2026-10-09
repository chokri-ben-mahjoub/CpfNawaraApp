import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/analysis/decline.dart';
import '../../../../core/analysis/metrics.dart';
import '../../../../core/analysis/production_metrics.dart';
import '../../../../core/analysis/series.dart';
import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/wells_repository.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/models/production_types.dart';
import '../../../../core/models/user_role.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../../core/widgets/series_chart.dart';
import '../../../analysis/presentation/decline_screen.dart';
import '../../../analysis/presentation/ratio_trend_screen.dart';
import '../../../interventions/presentation/intervention_form_sheet.dart';
import '../../../interventions/presentation/widgets/intervention_ui.dart';

/// Carte "Indicateurs calculés" de la fiche puits : GOR, WOR, GLR et PI,
/// calculés automatiquement à partir des débits (et de Pr/Pwf pour le PI).
class RatiosCard extends ConsumerWidget {
  final String wellId;
  const RatiosCard({super.key, required this.wellId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final well = controller.findWell(wellId);
    if (well == null || controller.findType(oilFlowTypeId) == null) return const SizedBox.shrink();
    final options = metricOptions(data, s);
    final metrics = ProductionMetrics.fromRecords(
      data.records.where((r) => r.wellId == wellId).toList(),
      reservoirPressure: well.reservoirPressure,
    );
    final dateFormat = DateFormat('d MMM', locale.languageCode);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s('ratiosTitle'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(s('ratiosSubtitle'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: isWideLayout(context) ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                for (final ratio in DerivedRatio.values)
                  _RatioTile(
                    label: s(ratio.labelKey),
                    unit: findMetric(options, MetricOption.ratioKey(ratio))?.unit ?? '',
                    latest: metrics.latest(ratio).$1,
                    previous: metrics.latest(ratio).$2,
                    dateFormat: dateFormat,
                    emptyLabel: ratio == DerivedRatio.pi && well.reservoirPressure == null ? s('piNeedsPr') : s('wellDetailNoValue'),
                    onTap: () => context.push('/wells/$wellId/ratio/${ratio.storageKey}'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.speed, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${s('reservoirPressureLabel')} : '
                    '${well.reservoirPressure == null ? s('notSet') : '${formatNumber(well.reservoirPressure!)} bar'}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                  ),
                ),
                if (role.canConfigure)
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => editReservoirPressure(context, ref, wellId),
                    child: Text(s(well.reservoirPressure == null ? 'set' : 'edit')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RatioTile extends StatelessWidget {
  final String label;
  final String unit;
  final SeriesPoint? latest;
  final SeriesPoint? previous;
  final DateFormat dateFormat;
  final String emptyLabel;
  final VoidCallback onTap;

  const _RatioTile({
    required this.label,
    required this.unit,
    required this.latest,
    required this.previous,
    required this.dateFormat,
    required this.emptyLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delta = latest == null || previous == null ? null : percentChange(previous!.v, latest!.v);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const Spacer(),
                if (delta != null)
                  Icon(
                    delta > 0.5
                        ? Icons.arrow_upward
                        : delta < -0.5
                            ? Icons.arrow_downward
                            : Icons.arrow_forward,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
            const Spacer(),
            Text(
              latest == null ? emptyLabel : formatNumber(latest!.v),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: latest == null ? 11.5 : 18,
                fontWeight: latest == null ? FontWeight.w500 : FontWeight.w800,
                color: latest == null ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
            if (latest != null)
              Text(
                '$unit · ${dateFormat.format(latest!.t)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// Carte "Déclin" de la fiche puits : taux de déclin effectif calculé
/// automatiquement (huile, sinon gaz) — ouvre la courbe de déclin complète.
class DeclineCard extends ConsumerWidget {
  final String wellId;
  const DeclineCard({super.key, required this.wellId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final data = ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final fluids = declineFluids.where((id) => controller.findType(id) != null).toList();
    if (fluids.isEmpty) return const SizedBox.shrink();

    final results = {for (final id in fluids) id: declineFor(data, wellId, id, DeclineWindow.auto)};

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/wells/$wellId/decline'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s('declineTitle'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 4),
              Text(s('declineCardSubtitle'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 12),
              for (final id in fluids)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: fluidColor(id), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(controller.findType(id)!.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(width: 8),
                      // Flexible : reste lisible (retour à la ligne) avec une
                      // grande taille de texte système.
                      Expanded(child: _declineValue(results[id]!.fit, s, scheme)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _declineValue(DeclineFit? fit, String Function(String) s, ColorScheme scheme) {
    if (fit == null) {
      return Text(
        s('declineNotEnoughShort'),
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      );
    }
    final declining = fit.isDeclining;
    final color = declining ? scheme.error : Colors.green.shade700;
    return Text(
      '${declining ? '−' : '+'}${fit.effectiveAnnualPct.abs().toStringAsFixed(1)} % / ${s('yearShort')}  ·  R² ${fit.r2.toStringAsFixed(2)}',
      textAlign: TextAlign.right,
      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color),
    );
  }
}

/// Section "Interventions" de la fiche puits : 3 dernières + accès au journal.
class InterventionsSection extends ConsumerWidget {
  final String wellId;
  const InterventionsSection({super.key, required this.wellId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    ref.watch(wellsControllerProvider);
    final controller = ref.read(wellsControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final interventions = controller.interventionsForWell(wellId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s('interventionsTitle'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (role.canEnterData)
              IconButton(
                tooltip: s('interventionAdd'),
                icon: const Icon(Icons.add_circle_outline, color: accentColor),
                onPressed: () => showInterventionForm(context, wellId: wellId),
              ),
            if (interventions.isNotEmpty)
              TextButton(
                onPressed: () => context.push('/wells/$wellId/interventions'),
                child: Text(s('seeAll')),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (interventions.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.construction, color: interventionMarkerColor),
              title: Text(s('interventionsEmptyShort'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              onTap: role.canEnterData ? () => showInterventionForm(context, wellId: wellId) : null,
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < interventions.length && i < 3; i++) ...[
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
      ],
    );
  }
}
