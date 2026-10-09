import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/analysis/series.dart';
import '../../../../core/models/intervention.dart';
import '../../../../core/widgets/series_chart.dart';

IconData interventionIcon(String typeKey) {
  switch (typeKey) {
    case 'interventionTypeWorkover':
      return Icons.construction;
    case 'interventionTypeStimulation':
      return Icons.science_outlined;
    case 'interventionTypeFracturing':
      return Icons.bolt;
    case 'interventionTypeChokeChange':
      return Icons.tune;
    case 'interventionTypeCleanout':
      return Icons.cleaning_services_outlined;
    case 'interventionTypeWireline':
      return Icons.cable;
    case 'interventionTypePerforation':
      return Icons.blur_on;
    case 'interventionTypeArtificialLift':
      return Icons.publish;
    case 'interventionTypeShutIn':
      return Icons.power_settings_new;
    default:
      return Icons.build_circle_outlined;
  }
}

Color interventionResultColor(String resultKey) {
  switch (resultKey) {
    case 'interventionResultSuccess':
      return Colors.green.shade600;
    case 'interventionResultPartial':
      return Colors.orange.shade700;
    case 'interventionResultFailure':
      return Colors.red.shade600;
    default:
      return Colors.blueGrey.shade400;
  }
}

/// Coût formaté avec sa devise (ex: "45 000 TND"), ou `null` si non saisi.
String? formatCost(Intervention i, Locale locale) {
  if (i.cost == null) return null;
  final format = NumberFormat.decimalPattern(locale.languageCode);
  return '${format.format(i.cost)} ${i.currency}';
}

/// Marqueurs verticaux (une ligne par intervention) à poser sur une courbe
/// temporelle — uniquement ceux compris dans [from]..[to] si fournis.
List<ChartMarker> interventionMarkers(
  List<Intervention> interventions,
  String Function(String) s, {
  DateTime? from,
  DateTime? to,
}) {
  return [
    for (final i in interventions)
      if ((from == null || !i.date.isBefore(dayOf(from))) && (to == null || !i.date.isAfter(to)))
        ChartMarker.at(i.date, label: s(i.typeKey), color: interventionMarkerColor),
  ];
}

/// Ligne d'intervention réutilisée dans la fiche puits et le journal complet.
class InterventionTile extends StatelessWidget {
  final Intervention intervention;
  final Locale locale;
  final String Function(String) s;
  final VoidCallback? onTap;
  final bool showCompare;

  const InterventionTile({
    super.key,
    required this.intervention,
    required this.locale,
    required this.s,
    this.onTap,
    this.showCompare = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resultColor = interventionResultColor(intervention.resultKey);
    final date = DateFormat('d MMM yyyy', locale.languageCode).format(intervention.date);
    final cost = formatCost(intervention, locale);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: interventionMarkerColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(interventionIcon(intervention.typeKey), color: interventionMarkerColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s(intervention.typeKey), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(date, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: resultColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          s(intervention.resultKey),
                          style: TextStyle(color: resultColor, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (cost != null)
                        Text(cost, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  if (intervention.description != null && intervention.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      intervention.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
            if (showCompare)
              IconButton(
                tooltip: s('interventionCompareBeforeAfter'),
                icon: const Icon(Icons.compare_arrows, color: interventionMarkerColor),
                onPressed: () => context.push(
                  '/compare?mode=periods&wellA=${intervention.wellId}&interventionId=${intervention.id}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
