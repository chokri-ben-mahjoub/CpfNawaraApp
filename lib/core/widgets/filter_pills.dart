import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../filters/well_filter.dart';
import '../theme/app_theme.dart';

/// Option d'un [FilterPill] : valeur + libellé affiché.
class PillOption<T> {
  final T value;
  final String label;
  const PillOption(this.value, this.label);
}

class _Picked<T> {
  final T value;
  const _Picked(this.value);
}

/// Filtre compact "Libellé : valeur ▾" ouvrant une liste de choix en bas
/// d'écran — plus confortable au doigt qu'un menu déroulant, et accepte une
/// valeur `null` (ex: "Tous les champs").
class FilterPill<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<PillOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// Mis en évidence quand le filtre n'est pas sur sa valeur par défaut.
  final bool active;

  const FilterPill({
    super.key,
    required this.icon,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final current = options.where((o) => o.value == selected).map((o) => o.label).firstOrNull ?? '';
    return _PillShell(
      icon: icon,
      label: current,
      active: active,
      onTap: () async {
        final picked = await showModalBottomSheet<_Picked<T>>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (sheetContext) => _OptionsSheet<T>(title: title, options: options, selected: selected),
        );
        if (picked != null) onSelected(picked.value);
      },
    );
  }
}

class _OptionsSheet<T> extends StatelessWidget {
  final String title;
  final List<PillOption<T>> options;
  final T selected;

  const _OptionsSheet({required this.title, required this.options, required this.selected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final option in options)
                    ListTile(
                      title: Text(
                        option.label,
                        style: TextStyle(fontWeight: option.value == selected ? FontWeight.w700 : FontWeight.w500),
                      ),
                      trailing: option.value == selected ? const Icon(Icons.check, color: accentColor) : null,
                      onTap: () => Navigator.of(context).pop(_Picked<T>(option.value)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillShell extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PillShell({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? accentColor : scheme.onSurfaceVariant;
    return Material(
      color: active ? accentColor.withValues(alpha: 0.12) : scheme.surfaceContainerLow,
      shape: StadiumBorder(side: BorderSide(color: active ? accentColor : scheme.outlineVariant)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Libellé d'une période (préréglage traduit, ou "01/09 – 30/09/2026").
String periodLabel(PeriodSelection period, String Function(String) s) {
  if (period.preset == PeriodPreset.custom && period.custom != null) {
    return formatRange(period.custom!);
  }
  return s(period.preset.labelKey);
}

String formatRange(DateTimeRange range) {
  final sameYear = range.start.year == range.end.year;
  final start = DateFormat(sameYear ? 'dd/MM' : 'dd/MM/yy').format(range.start);
  final end = DateFormat('dd/MM/yy').format(range.end);
  return '$start – $end';
}

/// Sélecteur de période : préréglages + "Personnalisée..." (calendrier).
class PeriodPill extends StatelessWidget {
  final PeriodSelection value;
  final ValueChanged<PeriodSelection> onChanged;
  final List<PeriodPreset> presets;
  final String title;
  final String Function(String) s;

  /// Mis en évidence quand la période diffère de celle par défaut.
  final bool active;

  const PeriodPill({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    required this.s,
    this.presets = const [
      PeriodPreset.days7,
      PeriodPreset.days30,
      PeriodPreset.days90,
      PeriodPreset.year,
      PeriodPreset.all,
      PeriodPreset.custom,
    ],
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return _PillShell(
      icon: Icons.date_range_outlined,
      label: periodLabel(value, s),
      active: active,
      onTap: () async {
        final picked = await showModalBottomSheet<_Picked<PeriodPreset>>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (sheetContext) => _OptionsSheet<PeriodPreset>(
            title: title,
            options: [for (final p in presets) PillOption(p, s(p.labelKey))],
            selected: value.preset,
          ),
        );
        if (picked == null || !context.mounted) return;
        if (picked.value != PeriodPreset.custom) {
          onChanged(PeriodSelection(picked.value));
          return;
        }
        final range = await pickDateRange(context, initial: value.custom);
        if (range != null) onChanged(PeriodSelection(PeriodPreset.custom, custom: range));
      },
    );
  }
}

/// Calendrier de sélection d'une plage de dates (jusqu'à aujourd'hui).
Future<DateTimeRange?> pickDateRange(BuildContext context, {DateTimeRange? initial}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: today,
    initialDateRange: initial ?? DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today),
  );
}
