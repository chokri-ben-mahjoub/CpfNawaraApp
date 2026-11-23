import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/machines/machine_test.dart';

void main() {
  test('classeurs de calibration réels', () {
    final dir = Directory(r'C:\Users\benmahjoub.chokri\Desktop\Nouveau dossier');
    if (!dir.existsSync()) return;
    final pts = <CalPoint>[];
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.xlsx'))) {
      final d = parseCalibrationFile(f.uri.pathSegments.last, f.readAsBytesSync());
      pts.addAll(d.points);
      for (final w in d.warnings) { print('WARN $w'); }
    }
    for (final m in evaluateCalibration(pts)) {
      print('${m.machine} => ${m.status.label} (${m.measured}/${m.total}, ko ${m.failed})');
      for (final sh in m.sheets) {
        for (final s in sh.standards) { print('    ${sh.sheet} | ${s.standard} | ${s.status.label} | ${s.reason}'); }
      }
    }
    expect(pts, isNotEmpty);
  });
}
