import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/export/pdf_export_settings.dart';
import 'package:puitstrack/core/export/pdf_style_set.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les défauts reproduisent le style historique', () {
    const d = PdfStyleSet.defaults;
    expect(d.reportTitle.size, 16);
    expect(d.reportTitle.bold, isTrue);
    expect(d.reportTitle.colorArgb, 0xFF0B1E2D);
    expect(d.tableTitle.size, 12);
    expect(d.columnHeader.size, isNull);
    expect(d.table.borderArgb, 0xFFBDBDBD);
    expect(d.table.borderWidth, 0.5);
    expect(d.table.spaceBeforeTable, 16);
    expect(d.table.spaceAfterTitle, 6);
    expect(d.isDefault, isTrue);
  });

  test('aller-retour JSON', () {
    final s = PdfStyleSet.defaults.copyWith(
      reportTitle: const PdfTextStyleSpec(
        family: PdfFontFamily.times,
        size: 20,
        italic: true,
        colorArgb: 0xFF112233,
        align: PdfTextAlign.center,
      ),
      table: const PdfTableStyleSpec(headerBgArgb: 0xFF445566, borderWidth: 1, padH: 4, padV: 6),
    );
    final back = PdfStyleSet.decode(s.encode());
    expect(back, s);
    expect(back.isDefault, isFalse);
  });

  test('données absentes ou corrompues → défauts', () {
    expect(PdfStyleSet.decode(null), PdfStyleSet.defaults);
    expect(PdfStyleSet.decode('{pas du json'), PdfStyleSet.defaults);
    expect(PdfStyleSet.decode('[1,2]'), PdfStyleSet.defaults);
    final odd = PdfStyleSet.decode('{"reportTitle":{"size":9999,"family":42},"table":{"borderWidth":-3}}');
    expect(odd.reportTitle.family, PdfFontFamily.helvetica);
    expect(odd.table.borderWidth, 0.5);
  });

  test('persistance, restauration et appliquer à tous', () async {
    SharedPreferences.setMockInitialValues({});
    final custom = PdfStyleSet.defaults.copyWith(tableTitle: const PdfTextStyleSpec(size: 14, bold: true));
    await PdfExportSettings.defaults(PdfReportKind.tables).copyWith(style: custom).save();
    expect((await PdfExportSettings.load()).style, custom);
    // Les autres familles ne sont pas touchées.
    expect((await PdfExportSettings.load(PdfReportKind.allCircuits)).style.isDefault, isTrue);

    await PdfExportSettings.applyStyleToAll(custom);
    for (final k in PdfReportKind.values) {
      expect((await PdfExportSettings.load(k)).style, custom);
    }

    final reset = await (await PdfExportSettings.load()).resetStyle();
    expect(reset.style.isDefault, isTrue);
    expect((await PdfExportSettings.load()).style.isDefault, isTrue);
  });
}
