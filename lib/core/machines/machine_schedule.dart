import 'dart:math' as math;

/// Périodicité de recalibration par défaut (jours).
const defaultCalibrationIntervalDays = 30;

enum DueState { ok, soon, overdue, unknown }

class DueInfo {
  final DateTime? last, due;
  final int? daysLeft; // négatif = en retard
  final DueState state;
  const DueInfo(this.last, this.due, this.daysLeft, this.state);

  String get label => switch (state) {
        DueState.unknown => 'Jamais calibrée',
        DueState.overdue => 'En retard de ${-daysLeft!} j',
        DueState.soon => daysLeft == 0 ? "À refaire aujourd'hui" : 'À refaire dans $daysLeft j',
        DueState.ok => 'Prochaine dans $daysLeft j',
      };
}

/// Échéance = dernière calibration + périodicité. « Bientôt » quand il reste
/// au plus max(3 jours, 20 % de la périodicité). Comparaison par jour calendaire.
DueInfo computeDue(DateTime? last, int intervalDays, DateTime now) {
  if (last == null) return const DueInfo(null, null, null, DueState.unknown);
  final day = DateTime(last.year, last.month, last.day);
  final due = day.add(Duration(days: intervalDays));
  final today = DateTime(now.year, now.month, now.day);
  final left = due.difference(today).inDays;
  final soon = math.max(3, (intervalDays * 0.2).round());
  final state = left < 0 ? DueState.overdue : (left <= soon ? DueState.soon : DueState.ok);
  return DueInfo(day, due, left, state);
}

enum AlertLevel { critical, warning, info }

class MachineAlert {
  final String machine;
  final AlertLevel level;
  final String title, body;
  const MachineAlert(this.machine, this.level, this.title, this.body);

  /// Clé stable pour ne notifier qu'une fois la même alerte.
  String get key => '$machine|$title';
}
