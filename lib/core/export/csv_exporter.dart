import 'dart:convert';

import 'package:intl/intl.dart';

import 'export_table.dart';

/// Génère le contenu d'un fichier CSV encodé en UTF-8 avec BOM.
///
/// Par défaut au format Excel FR (séparateur `;`, virgule décimale) : Excel
/// l'ouvre directement en colonnes, avec les nombres reconnus comme des
/// nombres. Le format "international" (séparateur `,`, point décimal) se
/// choisit dans les Réglages, pour les tableurs configurés en anglais.
class CsvExporter {
  static final _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  /// Réglage global (voir `AppSettings.csvInternational`).
  static bool international = false;

  static String get _separator => international ? ',' : ';';

  static List<int> encode(ExportTable table) {
    final buffer = StringBuffer();
    buffer.writeln(table.headers.map(_escape).join(_separator));
    for (final row in table.rows) {
      buffer.writeln(row.map((cell) => _escape(_format(cell))).join(_separator));
    }
    // BOM UTF-8 : évite les caractères accentués mal affichés à l'ouverture
    // dans Excel.
    return [0xEF, 0xBB, 0xBF, ...utf8.encode(buffer.toString())];
  }

  static String _format(Object? cell) {
    if (cell == null) return '';
    if (cell is DateOnly) return _dateFormat.format(cell.date);
    if (cell is DateTime) return _dateTimeFormat.format(cell);
    if (cell is int) return cell.toString();
    if (cell is double) {
      if (cell.isNaN || cell.isInfinite) return '';
      if (cell == cell.roundToDouble() && cell.abs() < 1e15) return cell.toInt().toString();
      return international ? cell.toString() : cell.toString().replaceAll('.', ',');
    }
    return cell.toString();
  }

  static String _escape(String value) {
    if (value.contains(_separator) || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
