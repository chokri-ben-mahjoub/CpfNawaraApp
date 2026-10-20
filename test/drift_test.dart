import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/analysis/drift_detector.dart';

void main() {
  test('dérive : valeur très éloignée de la moyenne récente', () {
    final d = detectDrift([10, 10.2, 9.8, 10.1, 9.9, 10, 20])!;
    expect(d.isUp, isTrue);
    expect(d.percent, closeTo(100, 2));
  });

  test('pas de dérive : valeur normale ou historique trop court', () {
    expect(detectDrift([10, 10.2, 9.8, 10.1, 9.9, 10, 10.3]), isNull);
    expect(detectDrift([10, 10, 30]), isNull);
  });

  test('série constante : seuil minimal de 5 % de la moyenne', () {
    expect(detectDrift([10, 10, 10, 10, 10, 10, 10.4]), isNull);
    expect(detectDrift([10, 10, 10, 10, 10, 10, 12]), isNotNull);
  });
}
