import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../app_info.dart';
import '../l10n/app_strings.dart';
import '../../features/stock/presentation/stock_screen.dart';

/// Génère le classeur de suivi mensuel du stock, avec la même mise en page
/// que le classeur de référence du laboratoire (bandeau de mise à jour,
/// titre « Laboratory Monthly Consumption », une colonne par mois, achats
/// en vert, stock de départ en orange, statut coloré) : une feuille par
/// zone (Chimique, ARO, Wells, CPF, Laboratoire...).
///
/// Limite de la librairie `excel` (pure Dart, sans rendu Office) : elle ne
/// sait pas insérer d'image, donc le logo de l'entreprise ne peut pas être
/// reproduit ici — seul le bandeau de titre coloré l'est.
class StockMonthlyExcel {
  static List<int>? encode({
    required List<StockTableSection> sections,
    required int year,
    required String Function(String) s,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;

    final titleStyle = CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('#1C3B57'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final updateBannerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.yellow,
      horizontalAlign: HorizontalAlign.Left,
    );
    final sectionTitleStyle = CellStyle(
      bold: true,
      fontSize: 13,
      backgroundColorHex: ExcelColor.amber,
      horizontalAlign: HorizontalAlign.Center,
    );
    final headerStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.grey200, textWrapping: TextWrapping.WrapText);
    final openingHeaderStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#FBD9B5'),
      textWrapping: TextWrapping.WrapText,
    );
    final purchasedHeaderStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1E7D45'),
      fontColorHex: ExcelColor.white,
      textWrapping: TextWrapping.WrapText,
    );
    final numberStyle = CellStyle(numberFormat: NumFormat.standard_0);
    final goodStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#C6EFCE'),
      fontColorHex: ExcelColor.fromHexString('#1E7D45'),
      horizontalAlign: HorizontalAlign.Center,
    );
    final badStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#FFC7CE'),
      fontColorHex: ExcelColor.fromHexString('#9C0006'),
      horizontalAlign: HorizontalAlign.Center,
    );

    const colCount = 21; // A..U
    final updateLabel = fill(s('stockInventoryUpdateLabel'), {'date': DateFormat('dd/MM/yyyy').format(DateTime.now())});
    final workbookTitle = fill(s('stockMonthlyWorkbookTitle'), {'y': '$year'});

    final usedNames = <String>{};
    for (var sIdx = 0; sIdx < sections.length; sIdx++) {
      final section = sections[sIdx];
      final sheetName = _uniqueSheetName(
        section.zone.isEmpty ? s('stockZoneUnclassified') : section.zone,
        usedNames,
      );
      if (sIdx == 0) excel.rename(defaultSheet, sheetName);
      final sheet = excel[sheetName];

      // Ligne 1 : bandeau titre (tient lieu de logo, non reproductible — la
      // librairie `excel` ne sait pas insérer d'image).
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), CellIndex.indexByColumnRow(columnIndex: colCount - 1, rowIndex: 0));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), TextCellValue(appDisplayName), cellStyle: titleStyle);
      sheet.setRowHeight(0, 28);

      // Ligne 3 : bandeau jaune « Mise à jour inventaire : ... ».
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2), CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 2));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2), TextCellValue(updateLabel), cellStyle: updateBannerStyle);

      // Ligne 5 : titre « Suivi mensuel de consommation {year} » au-dessus
      // des colonnes mensuelles.
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 4), CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: 4));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 4), TextCellValue(workbookTitle), cellStyle: sectionTitleStyle);

      // Ligne 6 : en-têtes de colonnes.
      final headers = [
        s('stockColZone'),
        s('stockColDescription'),
        s('stockPackagingLabel'),
        fill(s('stockColOpening'), {'y': '$year'}),
        for (final key in _monthHeaderKeys) '${s(key)}-${(year % 100).toString().padLeft(2, '0')}',
        fill(s('stockColMonthTotal'), {'y': '$year'}),
        fill(s('stockColPurchased'), {'y': '$year'}),
        s('stockUnitLabel'),
        s('stockColRemaining'),
        s('stockColStatus'),
      ];
      for (var c = 0; c < headers.length; c++) {
        final style = c == 3 ? openingHeaderStyle : (c == 17 ? purchasedHeaderStyle : headerStyle);
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 5), TextCellValue(headers[c]), cellStyle: style);
      }
      sheet.setRowHeight(5, 32);

      // Lignes 7+ : une ligne par article.
      var r = 6;
      for (final row in section.rows) {
        final item = row.item;
        final zoneLabel = section.zone.isEmpty ? s('stockZoneUnclassified') : section.zone;
        final cells = <CellValue?>[
          TextCellValue(zoneLabel),
          TextCellValue(item.name),
          TextCellValue(item.packaging),
          DoubleCellValue(row.opening),
          for (final v in row.monthly) DoubleCellValue(v),
          DoubleCellValue(row.consumption),
          DoubleCellValue(row.purchased),
          TextCellValue(item.unit),
          DoubleCellValue(row.remaining),
        ];
        for (var c = 0; c < cells.length; c++) {
          final value = cells[c];
          if (value == null) continue;
          sheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
            value,
            cellStyle: value is DoubleCellValue ? numberStyle : null,
          );
        }
        final isGood = !item.isLow;
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: cells.length, rowIndex: r),
          TextCellValue(isGood ? s('stockStatusGoodShort') : s('stockStatusBadShort')),
          cellStyle: isGood ? goodStyle : badStyle,
        );
        r++;
      }

      const widths = [16.0, 28.0, 12.0, 14.0, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 14.0, 14.0, 8.0, 16.0, 10.0];
      for (var c = 0; c < widths.length; c++) {
        sheet.setColumnWidth(c, widths[c].toDouble());
      }
    }

    return excel.encode();
  }

  static String _uniqueSheetName(String raw, Set<String> used) {
    var name = raw.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    if (name.isEmpty) name = 'Feuille';
    if (name.length > 31) name = name.substring(0, 31);
    var candidate = name;
    var i = 2;
    while (used.contains(candidate)) {
      final suffix = ' ($i)';
      candidate = '${name.substring(0, (31 - suffix.length).clamp(0, name.length))}$suffix';
      i++;
    }
    used.add(candidate);
    return candidate;
  }
}

/// Dupliqué de `stock_screen.dart` (clé privée là-bas) : les 12 en-têtes de
/// mois, index 0 = janvier ... 11 = décembre.
const _monthHeaderKeys = [
  'stockMonthJan', 'stockMonthFeb', 'stockMonthMar', 'stockMonthApr',
  'stockMonthMay', 'stockMonthJun', 'stockMonthJul', 'stockMonthAug',
  'stockMonthSep', 'stockMonthOct', 'stockMonthNov', 'stockMonthDec',
];
