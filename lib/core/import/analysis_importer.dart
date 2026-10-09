import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../data/wells_repository.dart';
import '../l10n/app_strings.dart';
import '../models/analysis_type.dart';
import '../models/well.dart';
import '../plant/plant_catalog.dart';
import '../plant/plant_repository.dart';
import '../units/unit_system.dart';

/// Tableau brut lu dans un fichier (en-têtes + lignes de texte).
class RawTable {
  final String name;
  final List<String> headers;
  final List<List<String>> rows;
  const RawTable(this.name, this.headers, this.rows);
}

/// Lit un fichier CSV (séparateur `;`, `,` ou tabulation détecté) ou Excel
/// (.xlsx, une table par feuille).
List<RawTable> readTables(String fileName, List<int> bytes) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.xlsx') || lower.endsWith('.xlsm')) return _readXlsx(bytes);
  var text = const Utf8Codec(allowMalformed: true).decode(bytes);
  if (text.startsWith('﻿')) text = text.substring(1);
  final table = readCsv(text, name: fileName);
  return table == null ? const [] : [table];
}

RawTable? readCsv(String text, {String name = 'CSV'}) {
  final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return null;
  final head = lines.first;
  final delimiter = [';', '\t', ','].reduce((a, b) => _count(head, a) >= _count(head, b) ? a : b);
  final rows = _parseCsv(lines.join('\n'), delimiter);
  if (rows.isEmpty) return null;
  return RawTable(name, rows.first.map((h) => h.trim()).toList(), rows.skip(1).toList());
}

int _count(String s, String c) => c.allMatches(s).length;

/// CSV avec champs entre guillemets (guillemets doublés, retours à la ligne).
List<List<String>> _parseCsv(String text, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == delimiter) {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else if (c != '\r') {
      field.write(c);
    }
  }
  row.add(field.toString());
  if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
  return rows;
}

List<RawTable> _readXlsx(List<int> bytes) {
  final excel = Excel.decodeBytes(bytes);
  final tables = <RawTable>[];
  for (final entry in excel.tables.entries) {
    final rows = [
      for (final row in entry.value.rows) [for (final cell in row) _cellText(cell?.value)],
    ].where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
    if (rows.length < 2) continue;
    tables.add(RawTable(entry.key, rows.first.map((h) => h.trim()).toList(), rows.skip(1).toList()));
  }
  return tables;
}

String _cellText(CellValue? value) {
  if (value == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return switch (value) {
    DateCellValue(:final year, :final month, :final day) => '$year-${two(month)}-${two(day)}',
    DateTimeCellValue(:final year, :final month, :final day, :final hour, :final minute) =>
      '$year-${two(month)}-${two(day)} ${two(hour)}:${two(minute)}',
    IntCellValue(:final value) => '$value',
    DoubleCellValue(:final value) => '$value',
    BoolCellValue(:final value) => '$value',
    _ => value.toString(),
  };
}

/// Nom de colonne simplifié (minuscules, sans accents ni ponctuation) pour
/// reconnaître les en-têtes quelle que soit leur écriture.
String normalizeHeader(String text) {
  const accents = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ç': 'c',
    '²': '2',
    '³': '3',
    '₂': '2',
    '₄': '4',
  };
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final ch in lower.split('')) {
    buffer.write(accents[ch] ?? ch);
  }
  // Retire l'unité entre parenthèses ("BSW (%)" -> "bsw").
  return buffer.toString().replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Date lue dans une cellule : ISO (2026-10-09[ 08:30]), jour/mois/année
/// (09/10/2026[ 08:30]) ou numéro de série Excel.
DateTime? parseImportDate(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final iso = DateTime.tryParse(t.replaceFirst(' ', 'T'));
  if (iso != null) return iso;
  final fr = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})(?:[ T](\d{1,2})[:h](\d{2}))?').firstMatch(t);
  if (fr != null) {
    var year = int.parse(fr.group(3)!);
    if (year < 100) year += 2000;
    return DateTime(
      year,
      int.parse(fr.group(2)!),
      int.parse(fr.group(1)!),
      int.tryParse(fr.group(4) ?? '') ?? 0,
      int.tryParse(fr.group(5) ?? '') ?? 0,
    );
  }
  final serial = double.tryParse(t.replaceAll(',', '.'));
  if (serial != null && serial > 20000 && serial < 80000) {
    final base = DateTime(1899, 12, 30);
    final days = serial.floor();
    final minutes = ((serial - days) * 24 * 60).round();
    return base.add(Duration(days: days, minutes: minutes));
  }
  return null;
}

double? parseImportNumber(String text) {
  final t = text.trim().replaceAll(RegExp(r'[\s ]'), '');
  if (t.isEmpty) return null;
  // "1.234,5" (FR) ou "1,234.5" (EN) ou "0,8".
  String normalized;
  if (t.contains(',') && t.contains('.')) {
    normalized = t.lastIndexOf(',') > t.lastIndexOf('.')
        ? t.replaceAll('.', '').replaceAll(',', '.')
        : t.replaceAll(',', '');
  } else {
    normalized = t.replaceAll(',', '.');
  }
  return double.tryParse(normalized);
}

enum ImportKind { wellsLong, wellsWide, plant }

/// Ligne refusée (numéro de ligne du fichier, en comptant l'en-tête).
class ImportIssue {
  final String table;
  final int line;
  final String messageKey;
  final String detail;
  const ImportIssue(this.table, this.line, this.messageKey, [this.detail = '']);
}

class _WellRecord {
  final Well well;
  final AnalysisType type;
  final DateTime at;
  final double value;
  final String service;
  final String operator;
  final String? comment;
  const _WellRecord(this.well, this.type, this.at, this.value, this.service, this.operator, this.comment);
}

class _PlantRecord {
  final SamplePoint point;
  final DateTime day;
  final Map<String, Object?> values;
  final String? comment;
  const _PlantRecord(this.point, this.day, this.values, this.comment);
}

/// Résultat de l'analyse d'un fichier : ce qui sera importé, ce qui est
/// ignoré (doublon) et ce qui est refusé (ligne illisible).
class ImportPlan {
  final List<ImportKind> kinds;
  final List<_WellRecord> _wells;
  final List<_PlantRecord> _plant;
  final int duplicates;
  final List<ImportIssue> issues;

  const ImportPlan._(this.kinds, this._wells, this._plant, this.duplicates, this.issues);

  int get wellRecords => _wells.length;
  int get plantRecords => _plant.length;
  int get total => _wells.length + _plant.length;

  /// Aperçu des premières lignes reconnues.
  List<List<String>> preview(Locale locale, {int max = 8}) => [
    for (final r in _wells.take(max)) [_date(r.at), r.well.code, r.type.label, '${r.value} ${r.type.unit}'.trim()],
    for (final r in _plant.take(max))
      [
        _date(r.day),
        r.point.code,
        tr(locale, r.point.circuit.labelKey),
        r.values.entries.map((e) => '${e.key}=${e.value}').join(', '),
      ],
  ];

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

const _uuid = Uuid();

/// Reconnaît le contenu de tables lues dans un fichier et prépare l'import :
///
/// - **analyses de puits, format long** : Date | Puits | Type | Valeur
///   [| Service | Opérateur | Commentaire] ;
/// - **analyses de puits, format large** : Date | Puits | une colonne par
///   type d'analyse (BSW, Salinité...) ;
/// - **analyses de l'usine** : Date | Point | une colonne par paramètre
///   (densité, BSW, pH...) [| Commentaire].
///
/// Les valeurs sont lues dans les unités affichées (Réglages › Unités),
/// comme celles des exports. Une analyse déjà présente (même puits, type,
/// jour et valeur) n'est pas importée deux fois.
class AnalysisImporter {
  final WellsState wells;
  final PlantState plant;
  final Locale locale;
  final String defaultService;
  final String operatorName;

  AnalysisImporter({
    required this.wells,
    required this.plant,
    required this.locale,
    required this.defaultService,
    required this.operatorName,
  });

  static const _dateHeaders = {'date', 'jour', 'day', 'dateetheure', 'datetime', 'dateheure'};
  static const _wellHeaders = {'puits', 'well', 'codepuits', 'wellcode', 'nompuits'};
  static const _typeHeaders = {
    'type',
    'analyse',
    'analysis',
    'parametre',
    'parameter',
    'typeanalyse',
    'typedanalyse',
    'analysistype',
  };
  static const _valueHeaders = {'valeur', 'value', 'mesure'};
  static const _pointHeaders = {'point', 'codepoint', 'pointdeprelevement', 'samplepoint'};
  static const _serviceHeaders = {'service', 'department'};
  static const _operatorHeaders = {'operateur', 'operator', 'saisipar'};
  static const _commentHeaders = {'commentaire', 'comment', 'remarque', 'note'};

  int _find(List<String> headers, Set<String> names) {
    for (var i = 0; i < headers.length; i++) {
      if (names.contains(normalizeHeader(headers[i]))) return i;
    }
    return -1;
  }

  Well? _well(String text) {
    final n = normalizeHeader(text);
    if (n.isEmpty) return null;
    for (final w in wells.wells) {
      if (normalizeHeader(w.code) == n || normalizeHeader(w.name) == n) return w;
    }
    return null;
  }

  AnalysisType? _type(String text) {
    final n = normalizeHeader(text);
    if (n.isEmpty) return null;
    for (final t in wells.analysisTypes) {
      if (normalizeHeader(t.label) == n || normalizeHeader(t.id) == n) return t;
    }
    return null;
  }

  /// Service : clé ou libellé traduit (ex: "Laboratoire").
  String? _service(String text) {
    final n = normalizeHeader(text);
    if (n.isEmpty) return null;
    for (final key in serviceKeys) {
      if (normalizeHeader(key) == n) return key;
      for (final code in supportedLocales) {
        if (normalizeHeader(tr(code, key)) == n) return key;
      }
    }
    return null;
  }

  SamplePoint? _point(String text) {
    final n = normalizeHeader(text);
    for (final p in plant.points) {
      if (normalizeHeader(p.code) == n || normalizeHeader(p.id) == n) return p;
    }
    return null;
  }

  PlantParam? _param(SamplePoint point, String header) {
    final n = normalizeHeader(header);
    for (final p in point.params) {
      if (normalizeHeader(p.key) == n) return p;
      for (final code in supportedLocales) {
        if (normalizeHeader(tr(code, p.labelKey)) == n) return p;
      }
    }
    return null;
  }

  String? _choice(PlantParam param, String text) {
    final n = normalizeHeader(text);
    for (final c in param.choices) {
      if (normalizeHeader(c) == n) return c;
      for (final code in supportedLocales) {
        if (normalizeHeader(tr(code, c)) == n) return c;
      }
    }
    return null;
  }

  ImportPlan analyze(List<RawTable> tables) {
    final kinds = <ImportKind>[];
    final wellRecords = <_WellRecord>[];
    final plantRecords = <_PlantRecord>[];
    final issues = <ImportIssue>[];
    var duplicates = 0;

    // Analyses déjà présentes (doublons) : puits|type|jour|valeur.
    final existing = <String>{
      for (final r in wells.records) '${r.wellId}|${r.typeId}|${_dayKey(r.dateTime)}|${_round(r.value)}',
    };

    for (final table in tables) {
      final h = table.headers;
      final dateCol = _find(h, _dateHeaders);
      final pointCol = _find(h, _pointHeaders);
      final wellCol = _find(h, _wellHeaders);
      final typeCol = _find(h, _typeHeaders);
      final valueCol = _find(h, _valueHeaders);
      final serviceCol = _find(h, _serviceHeaders);
      final operatorCol = _find(h, _operatorHeaders);
      final commentCol = _find(h, _commentHeaders);
      String cell(List<String> row, int col) => col >= 0 && col < row.length ? row[col].trim() : '';

      if (dateCol < 0) {
        issues.add(ImportIssue(table.name, 1, 'importNoDateColumn'));
        continue;
      }

      if (pointCol >= 0) {
        kinds.add(ImportKind.plant);
        for (var i = 0; i < table.rows.length; i++) {
          final row = table.rows[i];
          final line = i + 2;
          final date = parseImportDate(cell(row, dateCol));
          final point = _point(cell(row, pointCol));
          if (date == null) {
            issues.add(ImportIssue(table.name, line, 'importBadDate', cell(row, dateCol)));
            continue;
          }
          if (point == null) {
            issues.add(ImportIssue(table.name, line, 'importUnknownPoint', cell(row, pointCol)));
            continue;
          }
          final values = <String, Object?>{};
          for (var c = 0; c < h.length; c++) {
            if (c == dateCol || c == pointCol || c == commentCol || c == operatorCol) continue;
            final text = cell(row, c);
            if (text.isEmpty) continue;
            final param = _param(point, h[c]);
            if (param == null) continue;
            if (param.isNumeric) {
              final v = parseImportNumber(text);
              if (v == null) {
                issues.add(ImportIssue(table.name, line, 'importBadValue', '${h[c]} : $text'));
              } else {
                values[param.key] = v;
              }
            } else {
              final choice = _choice(param, text);
              if (choice != null) values[param.key] = choice;
            }
          }
          if (values.isEmpty) {
            issues.add(ImportIssue(table.name, line, 'importNoValue'));
            continue;
          }
          plantRecords.add(
            _PlantRecord(
              point,
              DateTime(date.year, date.month, date.day),
              values,
              cell(row, commentCol).isEmpty ? null : cell(row, commentCol),
            ),
          );
        }
        continue;
      }

      if (wellCol < 0) {
        issues.add(ImportIssue(table.name, 1, 'importNoWellColumn'));
        continue;
      }

      final long = typeCol >= 0 && valueCol >= 0;
      kinds.add(long ? ImportKind.wellsLong : ImportKind.wellsWide);
      // Format large : colonnes reconnues comme types d'analyse.
      final typeColumns = <int, AnalysisType>{};
      if (!long) {
        for (var c = 0; c < h.length; c++) {
          if ({dateCol, wellCol, serviceCol, operatorCol, commentCol}.contains(c)) continue;
          final type = _type(h[c]);
          if (type != null) typeColumns[c] = type;
        }
        if (typeColumns.isEmpty) {
          issues.add(ImportIssue(table.name, 1, 'importNoTypeColumn'));
          continue;
        }
      }

      for (var i = 0; i < table.rows.length; i++) {
        final row = table.rows[i];
        final line = i + 2;
        final date = parseImportDate(cell(row, dateCol));
        final well = _well(cell(row, wellCol));
        if (date == null) {
          issues.add(ImportIssue(table.name, line, 'importBadDate', cell(row, dateCol)));
          continue;
        }
        if (well == null) {
          issues.add(ImportIssue(table.name, line, 'importUnknownWell', cell(row, wellCol)));
          continue;
        }
        // Sans heure dans le fichier : saisie notée à midi.
        final at = date.hour == 0 && date.minute == 0 ? DateTime(date.year, date.month, date.day, 12) : date;
        final service = _service(cell(row, serviceCol)) ?? defaultService;
        final operator = cell(row, operatorCol).isEmpty ? operatorName : cell(row, operatorCol);
        final comment = cell(row, commentCol).isEmpty ? null : cell(row, commentCol);

        final entries = long
            ? <(AnalysisType?, String, String)>[(_type(cell(row, typeCol)), cell(row, typeCol), cell(row, valueCol))]
            : [for (final e in typeColumns.entries) (e.value, h[e.key], cell(row, e.key))];
        for (final (type, typeText, valueText) in entries) {
          if (valueText.isEmpty) continue;
          if (type == null) {
            issues.add(ImportIssue(table.name, line, 'importUnknownType', typeText));
            continue;
          }
          final value = parseImportNumber(valueText);
          if (value == null) {
            issues.add(ImportIssue(table.name, line, 'importBadValue', '$typeText : $valueText'));
            continue;
          }
          final key = '${well.id}|${type.id}|${_dayKey(at)}|${_round(value)}';
          if (!existing.add(key)) {
            duplicates++;
            continue;
          }
          wellRecords.add(_WellRecord(well, type, at, value, service, operator, comment));
        }
      }
    }
    return ImportPlan._(kinds, wellRecords, plantRecords, duplicates, issues);
  }

  /// Écrit le plan dans la base locale (une seule transaction) ; les
  /// contrôleurs doivent ensuite être relus.
  static Future<void> apply(ImportPlan plan) async {
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      for (final r in plan._wells) {
        await txn.insert(
          'analysis_records',
          LocalDatabase.stamp({
            'id': _uuid.v4(),
            'well_id': r.well.id,
            'type_id': r.type.id,
            'value': _toSi(r.type, r.value),
            'service_key': r.service,
            'operator_name': r.operator,
            'operator_id': null,
            'comment': r.comment,
            'recorded_at': r.at.toIso8601String(),
          }),
        );
      }
      for (final r in plan._plant) {
        final id = plantAnalysisId(r.point.id, r.day);
        final existing = (await txn.query('plant_analyses', where: 'id = ?', whereArgs: [id])).firstOrNull;
        final merged = <String, Object?>{};
        if (existing != null) {
          try {
            merged.addAll(Map<String, Object?>.from(jsonDecode(existing['values_json'] as String) as Map));
          } catch (_) {}
        }
        for (final e in r.values.entries) {
          final param = plantParamByKey(e.key, profile: r.point.profile);
          merged[e.key] = e.value is num && param != null ? param.toSi((e.value as num).toDouble()) : e.value;
        }
        await txn.insert(
          'plant_analyses',
          LocalDatabase.stamp({
            'id': id,
            'point_id': r.point.id,
            'analysis_date': plantDateKey(r.day),
            'values_json': jsonEncode(merged),
            'source': 'plantSourceImport',
            'operator_name': existing?['operator_name'] ?? '',
            'comment': r.comment ?? existing?['comment'],
            'recorded_at': DateTime.now().toIso8601String(),
          }),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    LocalDatabase.instance.notifyChange();
  }

  /// Même conversion que la saisie (voir WellsController).
  static double _toSi(AnalysisType type, double value) => Units.toSi(value, type.storedUnit);

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static String _round(double v) => v.toStringAsPrecision(6);
}
