import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/plant/plant_repository.dart';
import '../../../../core/theme/status_style.dart';
import '../../../../core/widgets/modern_widgets.dart';
import '../plant_screen.dart';

/// Carte thermique de l'usine : une ligne par point de prélèvement, une
/// colonne par jour. Vert = dans les seuils, rouge = hors seuil, gris = pas
/// d'analyse. Un clic sur une case ouvre ce jour dans la vue « Liste ».
class PlantHeatmapView extends ConsumerStatefulWidget {
  const PlantHeatmapView({super.key});

  @override
  ConsumerState<PlantHeatmapView> createState() => _PlantHeatmapViewState();
}

class _PlantHeatmapViewState extends ConsumerState<PlantHeatmapView> {
  int _days = 14;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final state = ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = _days - 1; i >= 0; i--) today.subtract(Duration(days: i))];
    final okColor = AppStatus.ok.color(scheme);
    final outColor = AppStatus.out.color(scheme);
    final noneColor = scheme.outlineVariant.withValues(alpha: 0.55);
    const cell = 26.0;
    const gap = 3.0;
    const labelWidth = 118.0;
    const rateWidth = 44.0;
    final gridWidth = _days * (cell + gap);

    Color colorOf(PlantStatus st) => switch (st) {
      PlantStatus.ok => okColor,
      PlantStatus.outOfRange => outColor,
      PlantStatus.missing => noneColor,
    };

    Widget legendDot(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    );

    Widget dayHeader() => Row(
      children: [
        const SizedBox(width: labelWidth),
        for (final d in days)
          SizedBox(
            width: cell + gap,
            child: Column(
              children: [
                Text(
                  DateFormat('E', locale.languageCode).format(d).substring(0, 1).toUpperCase(),
                  style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
                ),
                Text(
                  '${d.day}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: d == today ? FontWeight.w900 : FontWeight.w600,
                    color: d == today ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: rateWidth),
      ],
    );

    final circuits = state.circuits;
    final selectedCircuit = circuits.isEmpty ? null : selectedPlantCircuit(circuits, ref.watch(plantListCircuitProvider));

    var rowIndex = 0;
    final sections = <Widget>[];
    for (final circuit in circuits) {
      if (circuit.id != selectedCircuit?.id) continue;
      final points = controller.pointsOf(circuit).where((p) => p.active).toList();
      if (points.isEmpty) continue;
      for (final point in points) {
        final statuses = [for (final d in days) controller.status(point, d)];
        final analysed = statuses.where((st) => st != PlantStatus.missing).length;
        final outCount = statuses.where((st) => st == PlantStatus.outOfRange).length;
        sections.add(
          FadeSlideIn(
            index: rowIndex++,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        point.code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ),
                  for (var i = 0; i < days.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: gap),
                      child: Tooltip(
                        message:
                            '${point.code} · ${DateFormat('dd/MM/yyyy').format(days[i])} · ${switch (statuses[i]) {
                              PlantStatus.ok => s('heatmapOk'),
                              PlantStatus.outOfRange => s('heatmapOut'),
                              PlantStatus.missing => s('heatmapMissing'),
                            }}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            ref.read(plantDayProvider.notifier).state = days[i];
                            ref.read(plantViewProvider.notifier).state = PlantView.list;
                          },
                          child: Container(
                            width: cell,
                            height: cell,
                            decoration: BoxDecoration(
                              color: colorOf(statuses[i]),
                              borderRadius: BorderRadius.circular(6),
                              border: days[i] == today ? Border.all(color: scheme.primary, width: 1.6) : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: rateWidth,
                    child: Text(
                      '$analysed/$_days',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: outCount > 0 ? outColor : scheme.onSurfaceVariant,
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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s('plantViewHeatmap'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final n in const [7, 14, 30])
                  ChoiceChip(
                    label: Text('$n ${s('daysShort')}'),
                    selected: _days == n,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _days = n),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                legendDot(okColor, s('heatmapOk')),
                legendDot(outColor, s('heatmapOut')),
                legendDot(noneColor, s('heatmapMissing')),
              ],
            ),
            if (circuits.isNotEmpty) ...[
              const SizedBox(height: 10),
              PlantCircuitChips(circuits: circuits),
            ],
            const SizedBox(height: 10),
            if (sections.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(child: Text(s('heatmapEmpty'), style: TextStyle(color: scheme.onSurfaceVariant))),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: labelWidth + gridWidth + rateWidth,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [dayHeader(), ...sections]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
