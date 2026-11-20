import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_export_settings.dart';
import 'pdf_style_set.dart';

const _grey = PdfColor.fromInt(0xFF757575);

/// Marque une cellule de [PdfLook.groupedTable] fusionnée avec celle du dessus
/// (le texte de la cellule du haut est centré sur toute la hauteur fusionnée).
class PdfCellContinues {
  const PdfCellContinues();
}

/// Apparence commune des PDF d'après les réglages : couleurs de la palette,
/// style des tableaux (en-tête plein, filets, lignes alternées), marges et
/// filigrane. Utilisée par le rapport usine et par les exports de tableaux.
class PdfLook {
  final PdfExportSettings cfg;
  PdfLook(this.cfg);

  PdfColor get accent => PdfColor.fromInt(cfg.accentArgb);
  PdfColor get header => PdfColor.fromInt(cfg.headerArgb);

  /// Marges de la page, mises à l'échelle des réglages.
  pw.EdgeInsets margin(double left, double top) => pw.EdgeInsets.symmetric(
    horizontal: left * cfg.marginScale,
    vertical: top * cfg.marginScale,
  );

  static pw.Alignment _align(PdfTextAlign a) => switch (a) {
    PdfTextAlign.left => pw.Alignment.centerLeft,
    PdfTextAlign.center => pw.Alignment.center,
    PdfTextAlign.right => pw.Alignment.centerRight,
  };

  /// Style de texte PDF d'après un [PdfTextStyleSpec]. [size] et [color] ne
  /// servent que quand le réglage est « automatique » (null). Helvetica reste
  /// la police du thème par défaut (aucune police explicite), pour que le
  /// rendu par défaut soit strictement inchangé.
  pw.TextStyle textStyle(
    PdfTextStyleSpec s, {
    required double size,
    PdfColor? color,
  }) {
    final argb = s.colorArgb;
    final c = argb == null ? color : PdfColor.fromInt(argb);
    final weight = s.bold ? pw.FontWeight.bold : pw.FontWeight.normal;
    final style = s.italic ? pw.FontStyle.italic : pw.FontStyle.normal;
    return switch (s.family) {
      PdfFontFamily.helvetica => pw.TextStyle(
        fontSize: s.size ?? size,
        fontWeight: weight,
        fontStyle: style,
        color: c,
      ),
      PdfFontFamily.times => pw.TextStyle(
        font: pw.Font.times(),
        fontBold: pw.Font.timesBold(),
        fontItalic: pw.Font.timesItalic(),
        fontBoldItalic: pw.Font.timesBoldItalic(),
        fontSize: s.size ?? size,
        fontWeight: weight,
        fontStyle: style,
        color: c,
      ),
      PdfFontFamily.courier => pw.TextStyle(
        font: pw.Font.courier(),
        fontBold: pw.Font.courierBold(),
        fontItalic: pw.Font.courierOblique(),
        fontBoldItalic: pw.Font.courierBoldOblique(),
        fontSize: s.size ?? size,
        fontWeight: weight,
        fontStyle: style,
        color: c,
      ),
    };
  }

  /// Texte d'en-tête, de pied de page ou secondaire : [size], [color] et
  /// [bold] sont ceux historiques de l'élément, remplacés seulement si le
  /// réglage [s] en impose d'autres (« gras » du réglage = gras partout).
  pw.TextStyle note(
    PdfTextStyleSpec s, {
    required double size,
    PdfColor? color,
    bool bold = false,
  }) => textStyle(
    s.copyWith(bold: s.bold || bold),
    size: size,
    color: color,
  );

  /// Titre (rapport ou tableau) au style [s]. [scale] multiplie la taille
  /// (réglage « taille du texte ») ; l'alignement par défaut (gauche) n'ajoute
  /// aucun conteneur, pour garder le PDF identique à l'historique.
  pw.Widget title(
    String text,
    PdfTextStyleSpec s, {
    required double size,
    PdfColor? color,
    double scale = 1,
  }) {
    final scaled = s.size == null ? s : s.copyWith(size: s.size! * scale);
    final t = pw.Text(
      text,
      style: textStyle(scaled, size: size * scale, color: color),
    );
    if (s.align == PdfTextAlign.left) return t;
    return pw.Align(
      alignment: s.align == PdfTextAlign.center
          ? pw.Alignment.center
          : pw.Alignment.centerRight,
      child: t,
    );
  }

  /// Tableau de texte au style choisi.
  pw.Widget table({
    required List<String> headers,
    required List<List<Object>> data,
    required double fontSize,
    pw.EdgeInsets cellPadding = const pw.EdgeInsets.symmetric(
      horizontal: 5,
      vertical: 5,
    ),
    pw.Alignment cellAlignment = pw.Alignment.centerLeft,
    Map<int, pw.Alignment>? cellAlignments,
    Map<int, pw.TableColumnWidth>? columnWidths,
    Set<(int, int)> highlight = const {},
  }) {
    // 0 en-tête plein, 1 filets (lignes horizontales, sans quadrillage), 2
    // lignes alternées, 3 officiel (quadrillage complet, en-tête sans fond,
    // comme un rapport de laboratoire imprimé).
    final st = cfg.style;
    final customBg = st.table.headerBgArgb;
    final filled =
        cfg.tableStyle == 0 || cfg.tableStyle == 2 || customBg != null;
    final bg = customBg == null ? header : PdfColor.fromInt(customBg);
    final line = PdfColor.fromInt(st.table.borderArgb);
    final lineWidth = st.table.borderWidth;
    final pad = (st.table.padH == null && st.table.padV == null)
        ? cellPadding
        : pw.EdgeInsets.symmetric(
            horizontal: st.table.padH ?? cellPadding.left,
            vertical: st.table.padV ?? cellPadding.top,
          );
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: textStyle(
        st.columnHeader,
        size: fontSize,
        color: filled ? PdfColors.white : header,
      ),
      headerAlignment: _align(st.columnHeader.align),
      headerDecoration: filled
          ? pw.BoxDecoration(color: bg)
          : (cfg.tableStyle == 3
                ? null
                : pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: accent, width: 1.4),
                    ),
                  )),
      headerPadding: pad,
      cellStyle: textStyle(st.cell, size: fontSize),
      cellPadding: pad,
      // Alignement imposé par l'appelant (colonnes numériques...) prioritaire.
      cellAlignment: cellAlignment == pw.Alignment.centerLeft
          ? _align(st.cell.align)
          : cellAlignment,
      cellAlignments: cellAlignments,
      columnWidths: columnWidths,
      cellDecoration: highlight.isEmpty
          ? null
          : (index, data, rowNum) => highlight.contains((rowNum, index))
              ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFFC7C7))
              : const pw.BoxDecoration(),
      border: cfg.tableStyle == 1
          ? pw.TableBorder(
              horizontalInside: pw.BorderSide(color: line, width: lineWidth),
            )
          : pw.TableBorder.all(color: line, width: lineWidth),
      oddRowDecoration: cfg.tableStyle == 2
          ? pw.BoxDecoration(
              color: PdfColor.fromInt(
                (cfg.accentArgb & 0x00FFFFFF) | 0x14000000,
              ),
            )
          : null,
    );
  }

  /// Tableau à première colonne fusionnée par groupe (comme un rapport de
  /// laboratoire : une cellule « heure de prélèvement » en face de toutes les
  /// lignes d'une même analyse). Chaque élément de [groups] est le libellé
  /// fusionné + les lignes du groupe (sans cette première colonne). La lib PDF
  /// ne gère pas les `rowspan` : les bordures sont donc dessinées cellule par
  /// cellule (haut du groupe, bas du groupe) et le libellé est placé sur la
  /// ligne centrale du groupe.
  List<pw.Widget> groupedTable({
    required List<String> headers,
    required List<(String, List<List<Object>>)> groups,
    required double fontSize,
    Map<int, pw.Alignment>? cellAlignments,
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) {
    final st = cfg.style;
        // Rendu « rapport de laboratoire » : en-tête sans fond, texte noir, quadrillage complet.
            final lineColor = PdfColor.fromInt(st.table.borderArgb);
    final side = pw.BorderSide(color: lineColor, width: st.table.borderWidth);
    final none = pw.BorderSide.none;
    final pad = (st.table.padH == null && st.table.padV == null)
        ? const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5)
        : pw.EdgeInsets.symmetric(
            horizontal: st.table.padH ?? 5,
            vertical: st.table.padV ?? 5,
          );
        final cellStyle = textStyle(st.cell, size: fontSize);
    final headerStyle = textStyle(
      st.columnHeader,
      size: fontSize,
      color: PdfColors.black,
    );

    pw.Widget cell(
      Object? content, {
      required pw.Alignment align,
      required pw.TextStyle style,
      required pw.Border border,
      PdfColor? fill,
    }) => pw.Container(
      padding: pad,
      alignment: align,
      decoration: pw.BoxDecoration(color: fill, border: border),
      child: content is pw.Widget
          ? content
          : (content == null || '$content'.isEmpty
                ? null
                : pw.Text('$content', style: style)),
    );

    final rows = <pw.TableRow>[
      pw.TableRow(
        children: [
          for (var c = 0; c < headers.length; c++)
            cell(
              headers[c],
              align: c == 0
                  ? pw.Alignment.center
                  : _align(st.columnHeader.align),
              style: headerStyle,
              border: pw.Border.all(color: lineColor, width: st.table.borderWidth),
              fill: null,
            ),
        ],
      ),
    ];
    final oddFill = PdfColor.fromInt(
      (cfg.accentArgb & 0x00FFFFFF) | 0x14000000,
    );
    // Un bloc par groupe (analyse) : un groupe n'est jamais coupé entre deux
    // pages, il passe en entier sur la page suivante.
    final blocks = <List<pw.TableRow>>[];
    for (var g = 0; g < groups.length; g++) {
      final groupRows = <pw.TableRow>[];
      blocks.add(groupRows);
      final (label, lines) = groups[g];
      final mid = (lines.length - 1) ~/ 2;
      final fill = cfg.tableStyle == 2 && g.isOdd ? oddFill : null;
      for (var r = 0; r < lines.length; r++) {
        final first = r == 0, last = r == lines.length - 1;
        groupRows.add(
          pw.TableRow(
            children: [
              cell(
                r == mid ? label : '',
                align: pw.Alignment.center,
                style: textStyle(st.cell.copyWith(bold: true), size: fontSize),
                border: pw.Border(
                  left: side,
                  right: side,
                  top: first ? side : none,
                  bottom: last ? side : none,
                ),
                fill: fill,
              ),
              for (var c = 0; c < lines[r].length; c++)
                () {
                  final cont = lines[r][c] is PdfCellContinues;
                  var start = r;
                  while (start > 0 && lines[start][c] is PdfCellContinues) {
                    start--;
                  }
                  var end = r;
                  while (end + 1 < lines.length && lines[end + 1][c] is PdfCellContinues) {
                    end++;
                  }
                  final spanned = cont || (end > r);
                  final show = spanned ? r == start + (end - start) ~/ 2 : true;
                  return cell(
                    show ? lines[start][c] : '',
                    align: cellAlignments?[c + 1] ?? _align(st.cell.align),
                    style: cellStyle,
                    border: spanned
                        ? pw.Border(
                            left: side,
                            right: side,
                            top: r == start ? side : none,
                            bottom: r == end ? side : none,
                          )
                        : pw.Border.all(color: lineColor, width: st.table.borderWidth),
                    fill: fill,
                  );
                }(),
            ],
          ),
        );
      }
    }
    pw.Widget tableOf(List<pw.TableRow> rs) => pw.Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
      children: rs,
    );
    // En-tête collé au premier groupe. Un groupe très long (plus d'une page)
    // reste dans un tableau qui peut se couper, sinon la page ne le contiendrait pas.
    const maxUnsplit = 35;
    final widgets = <pw.Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final rs = [if (i == 0) ...rows, ...blocks[i]];
      final t = tableOf(rs);
      widgets.add(rs.length <= maxUnsplit ? pw.Container(child: t) : t);
    }
    // Widgets de premier niveau distincts : la mise en page peut changer de
    // page entre deux groupes (jamais au milieu d'un groupe).
    return widgets.isEmpty ? [tableOf(rows)] : widgets;
  }

  /// Fond de page : filigrane en diagonale (position/taille/angle historiques,
  /// ou ceux choisis à la souris si le filigrane a été déplacé), ou rien.
  pw.Widget Function(pw.Context)? get background {
    final text = cfg.watermark.trim();
    if (text.isEmpty) return null;
    final layout = cfg.style.watermarkLayout;
    final fontSize = 64 * (layout?.scale ?? 1.0);
    final angle = (layout?.angleDeg ?? -35.5) * 3.14159265 / 180;
    final textWidget = pw.Opacity(
      opacity: 0.12,
      child: pw.Text(
        text.toUpperCase(),
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: pw.FontWeight.bold,
          color: _grey,
        ),
      ),
    );
    return (context) => pw.FullPage(
      ignoreMargins: true,
      child: layout == null
          ? pw.Center(
              child: pw.Transform.rotate(angle: angle, child: textWidget),
            )
          : pw.Align(
              alignment: pw.Alignment(layout.dx * 2 - 1, 1 - layout.dy * 2),
              child: pw.Transform.rotate(angle: angle, child: textWidget),
            ),
    );
  }
}
