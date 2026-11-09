import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/export/pdf_style_set.dart';
import 'package:puitstrack/features/settings/presentation/pdf_style_editor.dart';

void main() {
  testWidgets('éditeur de style : modifier, restaurer, appliquer à tous', (t) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var style = PdfStyleSet.defaults;
    var resets = 0, applies = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: PdfStyleEditor(
                style: style,
                s: (k) => k,
                onChanged: (v) => setState(() => style = v),
                onReset: () => resets++,
                onApplyAll: () => applies++,
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('pdfStyleReportTitle'));
    await t.pumpAndSettle();
    await t.tap(find.text('Courier').first);
    await t.pumpAndSettle();
    expect(style.reportTitle.family, PdfFontFamily.courier);
    await t.tap(find.text('pdfStyleItalic').first);
    await t.pumpAndSettle();
    expect(style.reportTitle.italic, isTrue);
    await t.tap(find.text('pdfStyleCenter').first);
    await t.pumpAndSettle();
    expect(style.reportTitle.align, PdfTextAlign.center);

    await t.tap(find.text('pdfStyleFrame'));
    await t.pumpAndSettle();
    await t.tap(find.text('pdfStyleReset'));
    await t.tap(find.text('pdfStyleApplyAll'));
    expect((resets, applies), (1, 1));
    expect(t.takeException(), isNull);
  });
}
