import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:puitstrack/core/export/pdf_export_settings.dart';

void main() {
  test('désactiver gaz / Scope of Work sur la famille vaut aussi pour un circuit', () async {
    SharedPreferences.setMockInitialValues({});
    const kind = PdfReportKind.samples;
    // Un circuit enregistré quand les options étaient activées (copie figée).
    final on = (await PdfExportSettings.load(kind, 'c1')).copyWith(showGasBottles: true, showScopeOfWork: true);
    await on.save();
    // L'utilisateur désactive depuis l'écran de la famille.
    final generic = (await PdfExportSettings.load(kind)).copyWith(showGasBottles: false, showScopeOfWork: false);
    await generic.save();
    final circuit = await PdfExportSettings.load(kind, 'c1');
    expect(circuit.showGasBottles, isFalse);
    expect(circuit.showScopeOfWork, isFalse);
  });
}
