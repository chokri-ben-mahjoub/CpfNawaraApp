import 'package:flutter/material.dart';

import '../models/well.dart';

enum WellStatusFilter { all, active, stopped }

extension WellStatusFilterX on WellStatusFilter {
  String get labelKey {
    switch (this) {
      case WellStatusFilter.all:
        return 'filterStatusAll';
      case WellStatusFilter.active:
        return 'filterStatusActive';
      case WellStatusFilter.stopped:
        return 'filterStatusStopped';
    }
  }

  bool matches(Well well) {
    switch (this) {
      case WellStatusFilter.all:
        return true;
      case WellStatusFilter.active:
        return well.active;
      case WellStatusFilter.stopped:
        return !well.active;
    }
  }
}

enum PeriodPreset { today, days7, days30, days90, year, all, custom }

extension PeriodPresetX on PeriodPreset {
  String get labelKey {
    switch (this) {
      case PeriodPreset.today:
        return 'periodToday';
      case PeriodPreset.days7:
        return 'period7';
      case PeriodPreset.days30:
        return 'period30';
      case PeriodPreset.days90:
        return 'period90';
      case PeriodPreset.year:
        return 'period365';
      case PeriodPreset.all:
        return 'periodAll';
      case PeriodPreset.custom:
        return 'periodCustom';
    }
  }
}

/// Période choisie par l'utilisateur : un préréglage (7 j, 30 j...) ou une
/// plage de dates personnalisée.
class PeriodSelection {
  final PeriodPreset preset;
  final DateTimeRange? custom;

  const PeriodSelection(this.preset, {this.custom});

  static const today = PeriodSelection(PeriodPreset.today);
  static const days7 = PeriodSelection(PeriodPreset.days7);
  static const days30 = PeriodSelection(PeriodPreset.days30);
  static const days90 = PeriodSelection(PeriodPreset.days90);
  static const all = PeriodSelection(PeriodPreset.all);

  /// Plage de jours (début et fin inclus, à minuit) correspondant à la
  /// sélection, la fin étant aujourd'hui pour les préréglages.
  DateTimeRange resolve(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (preset) {
      case PeriodPreset.today:
        return DateTimeRange(start: today, end: today);
      case PeriodPreset.days7:
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case PeriodPreset.days30:
        return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
      case PeriodPreset.days90:
        return DateTimeRange(start: today.subtract(const Duration(days: 89)), end: today);
      case PeriodPreset.year:
        return DateTimeRange(start: today.subtract(const Duration(days: 364)), end: today);
      case PeriodPreset.all:
        return DateTimeRange(start: DateTime(2000), end: today);
      case PeriodPreset.custom:
        final c = custom ?? DateTimeRange(start: today, end: today);
        return DateTimeRange(
          start: DateTime(c.start.year, c.start.month, c.start.day),
          end: DateTime(c.end.year, c.end.month, c.end.day),
        );
    }
  }

  /// Vrai si [t] tombe dans la période (jours entiers inclus).
  bool contains(DateTime t, DateTime now) {
    final range = resolve(now);
    final end = range.end.add(const Duration(days: 1));
    return !t.isBefore(range.start) && t.isBefore(end);
  }

  @override
  bool operator ==(Object other) =>
      other is PeriodSelection && other.preset == preset && other.custom == custom;

  @override
  int get hashCode => Object.hash(preset, custom);
}

/// Filtres de la liste des puits / des statistiques : recherche par nom ou
/// code, champ (zone), statut actif/arrêté et période.
class WellFilter {
  final String query;

  /// Nom du champ/zone, `null` = tous. La chaîne vide désigne les puits
  /// sans groupe.
  final String? group;
  final WellStatusFilter status;
  final PeriodSelection period;

  const WellFilter({
    this.query = '',
    this.group,
    this.status = WellStatusFilter.all,
    this.period = PeriodSelection.today,
  });

  WellFilter copyWith({
    String? query,
    String? Function()? group,
    WellStatusFilter? status,
    PeriodSelection? period,
  }) =>
      WellFilter(
        query: query ?? this.query,
        group: group != null ? group() : this.group,
        status: status ?? this.status,
        period: period ?? this.period,
      );

  bool matches(Well well) {
    if (!status.matches(well)) return false;
    if (group != null && well.group.trim() != group) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return well.name.toLowerCase().contains(q) || well.code.toLowerCase().contains(q);
  }
}
