import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import 'export_table.dart';

/// Génère un document Word (.docx) minimal : un titre, puis un tableau
/// bordé par [ExportTable] (en-tête en gras sur fond gris clair).
///
/// Construit à la main (le paquet `pdf` n'a pas d'équivalent OOXML) : un
/// .docx est une archive zip contenant quelques fichiers XML. On ne génère
/// que le strict nécessaire (pas de styles.xml) pour rester robuste — tout
/// le formatage est en direct (gras, bordures) plutôt que via des styles
/// nommés, qui déclencheraient un message de réparation dans Word s'ils
/// n'étaient pas définis.
class WordExporter {
  static final _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  static List<int> encode(List<ExportTable> tables, {String? title}) {
    final body = StringBuffer();
    if (title != null && title.trim().isNotEmpty) {
      body.write(_titlePara(title));
    }
    final multi = tables.length > 1;
    for (final table in tables) {
      if (multi) body.write(_headingPara(table.name));
      body.write(_table(table));
    }
    body.write('<w:sectPr/>');

    final document =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body</w:body></w:document>';

    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml', _contentTypes);
    add('_rels/.rels', _rootRels);
    add('word/document.xml', document);

    return ZipEncoder().encode(archive) ?? const [];
  }

  static String _titlePara(String text) =>
      '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
      '<w:r><w:rPr><w:b/><w:sz w:val="32"/></w:rPr>'
      '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>'
      '<w:p/>';

  static String _headingPara(String text) =>
      '<w:p><w:r><w:rPr><w:b/><w:sz w:val="24"/></w:rPr>'
      '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>';

  static String _table(ExportTable table) {
    final buffer = StringBuffer(
      '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>'
      '<w:tblBorders>'
      '<w:top w:val="single" w:sz="4" w:color="999999"/>'
      '<w:left w:val="single" w:sz="4" w:color="999999"/>'
      '<w:bottom w:val="single" w:sz="4" w:color="999999"/>'
      '<w:right w:val="single" w:sz="4" w:color="999999"/>'
      '<w:insideH w:val="single" w:sz="4" w:color="999999"/>'
      '<w:insideV w:val="single" w:sz="4" w:color="999999"/>'
      '</w:tblBorders></w:tblPr>',
    );
    buffer.write(_row(table.headers, bold: true, shaded: true));
    for (final row in table.rows) {
      buffer.write(_row(row.map(_format).toList(), bold: false, shaded: false));
    }
    buffer.write('</w:tbl><w:p/>');
    return buffer.toString();
  }

  static String _row(List<Object?> cells, {required bool bold, required bool shaded}) {
    final buffer = StringBuffer('<w:tr>');
    for (final cell in cells) {
      final text = cell is String ? cell : _format(cell);
      final shade = shaded ? '<w:shd w:val="clear" w:fill="D9E2F3"/>' : '';
      final runProps = bold ? '<w:rPr><w:b/></w:rPr>' : '';
      buffer.write(
        '<w:tc><w:tcPr>$shade</w:tcPr>'
        '<w:p><w:r>$runProps<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>'
        '</w:tc>',
      );
    }
    buffer.write('</w:tr>');
    return buffer.toString();
  }

  static String _format(Object? cell) {
    if (cell == null) return '';
    if (cell is DateOnly) return _dateFormat.format(cell.date);
    if (cell is DateTime) return _dateTimeFormat.format(cell);
    if (cell is int) return cell.toString();
    if (cell is double) {
      if (cell.isNaN || cell.isInfinite) return '';
      if (cell == cell.roundToDouble() && cell.abs() < 1e15) return cell.toInt().toString();
      return cell.toString();
    }
    return cell.toString();
  }

  static String _esc(String value) =>
      value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  static const _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';

  static const _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';
}
