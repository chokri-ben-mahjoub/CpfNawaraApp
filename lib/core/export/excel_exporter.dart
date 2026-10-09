import 'package:excel/excel.dart';

import 'export_table.dart';

/// Génère un classeur Excel (.xlsx) : une feuille par [ExportTable], en-tête
/// en gras, nombres et dates exportés comme de vraies valeurs (triables,
/// filtrables, utilisables dans des formules).
class ExcelExporter {
  static List<int>? encode(List<ExportTable> tables) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;
    final headerStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.grey100);
    // "General" plutôt que le "0.00" par défaut de la librairie : garde toutes
    // les décimales utiles (ex: BSW 0,005) sans en inventer.
    final numberStyle = CellStyle(numberFormat: NumFormat.standard_0);

    final usedNames = <String>{};
    for (var t = 0; t < tables.length; t++) {
      final table = tables[t];
      final sheetName = _uniqueSheetName(table.name, usedNames);
      if (t == 0) {
        excel.rename(defaultSheet, sheetName);
      }
      final sheet = excel[sheetName];

      for (var c = 0; c < table.headers.length; c++) {
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
          TextCellValue(table.headers[c]),
          cellStyle: headerStyle,
        );
      }
      for (var r = 0; r < table.rows.length; r++) {
        final row = table.rows[r];
        for (var c = 0; c < row.length; c++) {
          final value = _cellValue(row[c]);
          if (value == null) continue;
          sheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
            value,
            cellStyle: value is DoubleCellValue ? numberStyle : null,
          );
        }
      }
      for (var c = 0; c < table.headers.length; c++) {
        sheet.setColumnWidth(c, _columnWidth(table, c));
      }
    }

    return excel.encode();
  }

  static CellValue? _cellValue(Object? cell) {
    if (cell == null) return null;
    if (cell is DateOnly) {
      return DateCellValue(year: cell.date.year, month: cell.date.month, day: cell.date.day);
    }
    if (cell is DateTime) {
      return DateTimeCellValue(
        year: cell.year,
        month: cell.month,
        day: cell.day,
        hour: cell.hour,
        minute: cell.minute,
      );
    }
    if (cell is int) return IntCellValue(cell);
    if (cell is double) {
      if (cell.isNaN || cell.isInfinite) return null;
      return DoubleCellValue(cell);
    }
    return TextCellValue(cell.toString());
  }

  /// Largeur approximative d'une colonne d'après son contenu le plus long.
  static double _columnWidth(ExportTable table, int column) {
    var longest = table.headers[column].length;
    for (final row in table.rows.take(200)) {
      if (column >= row.length) continue;
      final cell = row[column];
      final length = cell is DateTime
          ? 16
          : cell is DateOnly
              ? 10
              : (cell?.toString().length ?? 0);
      if (length > longest) longest = length;
    }
    return (longest + 2).clamp(8, 50).toDouble();
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
