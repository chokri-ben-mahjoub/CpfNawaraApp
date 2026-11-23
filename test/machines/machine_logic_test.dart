import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/machines/control_chart.dart';
import 'package:puitstrack/core/machines/machine_certificate_pdf.dart';
import 'package:puitstrack/core/machines/machine_history.dart';
import 'package:puitstrack/core/machines/machine_schedule.dart';
import 'package:puitstrack/core/machines/machine_test.dart';

CalPoint p(String std, double ref, double? m, {DateTime? d}) => CalPoint('M1', 'Titrator_Calibration', std, ref, m, d, '');

void main() {
  test('échéance', () {
    final now = DateTime(2026, 11, 23);
    expect(computeDue(null, 30, now).state, DueState.unknown);
    expect(computeDue(DateTime(2026, 11, 20), 30, now).state, DueState.ok);
    expect(computeDue(DateTime(2026, 10, 28), 30, now).state, DueState.soon); // reste 5 j
    expect(computeDue(DateTime(2026, 10, 1), 30, now).state, DueState.overdue);
    expect(computeDue(DateTime(2026, 10, 1), 30, now).daysLeft, -23);
  });

  test('dernière calibration', () {
    final now = DateTime(2026, 11, 23);
    expect(lastCalibrationOf([p('a', 1, null)], now), isNull);
    expect(lastCalibrationOf([p('a', 1, 1)], now), now);
    expect(lastCalibrationOf([p('a', 1, 1, d: DateTime(2026, 1, 5)), p('a', 1, 1, d: DateTime(2026, 2, 5))], now), DateTime(2026, 2, 5));
  });

  test('règles carte de contrôle', () {
    expect(controlViolations([0.5, 0.6, 0.4, 0.5, 0.6, 0.5, 0.4, 0.5], 1), isNotEmpty); // biais
    expect(controlViolations([0.1, -0.1, 0.1, -0.1, 0.1, -0.1, 0.1, -0.1], 1), isEmpty);
    expect(controlViolations([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7], 1).any((s) => s.contains('tendance')), isTrue);
    expect(controlViolations([0.1, 0.1], 1), isEmpty); // < 8 mesures
  });

  test('statuts et hash', () {
    final r = evaluateCalibration([p('s', 100, 100.2), p('s', 100, 105)]).first; // tol 1 %
    expect(r.status, MachineStatus.fault);
    expect(evaluateCalibration([p('s', 100, null)]).first.status, MachineStatus.notTested);
    expect(contentHash('abc'), contentHash('abc'));
    expect(contentHash('abc'), isNot(contentHash('abd')));
  });

  test('certificat PDF généré', () async {
    final pts = [p('s', 100, 100.2), p('s', 100, 100.1)];
    final snap = MachineSnapshot('1', 'M1', 'h', DateTime(2026, 11, 1), DateTime(2026, 11, 1), pts);
    final res = evaluateCalibration(pts).first;
    final due = computeDue(DateTime(2026, 11, 1), 30, DateTime(2026, 11, 23));
    final bytes = await buildMachineCertificatePdf(MachineEntry(snap, res, const MachineSettings(), due, [snap]));
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final alerts = buildMachineAlerts([MachineEntry(snap, res, const MachineSettings(), due, [snap])]);
    expect(alerts, isEmpty);
  });
}
