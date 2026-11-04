import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../l10n/app_strings.dart';
import '../platform/app_platform.dart';
import 'csv_exporter.dart';
import 'download_saver.dart';
import 'excel_exporter.dart';
import 'export_format_sheet.dart';
import 'export_table.dart';
import 'pdf_chart.dart';
import 'pdf_table_exporter.dart';
import 'share_files.dart';
import 'word_exporter.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const _csvMime = 'text/csv';
const _pdfMime = 'application/pdf';
const _docxMime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

class _GeneratedFile {
  final String name;
  final String mime;
  final List<int> bytes;
  const _GeneratedFile(this.name, this.mime, this.bytes);
}

/// Point d'entrée unique de tous les exports de l'app : vérifie qu'il y a
/// quelque chose à exporter, demande le format (Excel/CSV) et l'action
/// (télécharger sur le téléphone ou partager), génère le(s) fichier(s) puis
/// informe l'utilisateur du résultat.
///
/// En Excel, chaque [ExportTable] devient une feuille du même classeur ; en
/// CSV (un seul tableau par fichier), un fichier est généré par tableau.
/// [charts] : courbes ajoutées en tête du PDF (ignorées en Excel/CSV, qui ne
/// peuvent pas en afficher).
Future<void> runExport({
  required BuildContext context,
  required Locale locale,
  required String baseName,
  required List<ExportTable> tables,
  List<PdfReportChart> charts = const [],
  String? shareSubject,
}) async {
  String s(String key) => tr(locale, key);
  final messenger = ScaffoldMessenger.of(context);
  final nonEmpty = tables.where((t) => !t.isEmpty).toList();

  if (nonEmpty.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(s('exportEmpty'))));
    return;
  }

  final choice = await chooseExport(context, locale);
  if (choice == null || !context.mounted) return;
  await exportWithChoice(
    context: context,
    locale: locale,
    choice: choice,
    baseName: baseName,
    tables: nonEmpty,
    charts: charts,
    shareSubject: shareSubject,
  );
}

/// Génère et livre l'export (Excel, CSV ou PDF de tableaux) pour un [choice]
/// déjà fait — pour les écrans qui proposent le format eux-mêmes (ex: le
/// rapport usine, dont le PDF a sa propre mise en page).
Future<void> exportWithChoice({
  required BuildContext context,
  required Locale locale,
  required ExportChoice choice,
  required String baseName,
  required List<ExportTable> tables,
  List<PdfReportChart> charts = const [],
  String? shareSubject,
}) async {
  String s(String key) => tr(locale, key);
  final messenger = ScaffoldMessenger.of(context);
  final nonEmpty = tables.where((t) => !t.isEmpty).toList();
  if (nonEmpty.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(s('exportEmpty'))));
    return;
  }

  messenger.showSnackBar(SnackBar(content: Text(s('exportStarted')), duration: const Duration(seconds: 1)));
  final safeBase = _safeFileName(baseName);
  final suffix = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  try {
    final files = <_GeneratedFile>[];
    switch (choice.format) {
      case ExportFormat.excel:
        final bytes = ExcelExporter.encode(nonEmpty);
        if (bytes == null) throw StateError('excel encode failed');
        files.add(_GeneratedFile('${safeBase}_$suffix.xlsx', _xlsxMime, bytes));
      case ExportFormat.csv:
        for (final table in nonEmpty) {
          final name = nonEmpty.length == 1
              ? '${safeBase}_$suffix.csv'
              : '${safeBase}_${_safeFileName(table.name)}_$suffix.csv';
          files.add(_GeneratedFile(name, _csvMime, CsvExporter.encode(table)));
        }
      case ExportFormat.pdf:
        final bytes = await PdfTableExporter.encode(nonEmpty, title: baseName, charts: charts);
        files.add(_GeneratedFile('${safeBase}_$suffix.pdf', _pdfMime, bytes));
      case ExportFormat.word:
        final bytes = WordExporter.encode(nonEmpty, title: baseName);
        files.add(_GeneratedFile('${safeBase}_$suffix.docx', _docxMime, bytes));
    }

    if (choice.action == ExportAction.download && DownloadSaver.isSupported) {
      final saved = <SavedDownload>[];
      for (final file in files) {
        saved.add(await DownloadSaver.save(fileName: file.name, mimeType: file.mime, bytes: file.bytes));
      }
      // Web : le navigateur a téléchargé le fichier lui-même (pas de dossier
      // PuitsTrack ni de bouton "Ouvrir").
      final one = isWeb ? 'exportDownloadedOne' : 'exportSavedOne';
      final many = isWeb ? 'exportDownloadedMany' : 'exportSavedMany';
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(saved.length == 1 ? '${s(one)}\n${saved.first.fileName}' : '${saved.length} ${s(many)}'),
          action: DownloadSaver.canOpen
              ? SnackBarAction(
                  label: s('exportOpen'),
                  onPressed: () async {
                    final opened = await DownloadSaver.open(saved.first);
                    if (!opened) {
                      messenger.showSnackBar(SnackBar(content: Text(s('exportNoAppToOpen'))));
                    }
                  },
                )
              : null,
        ),
      );
      return;
    }

    messenger.hideCurrentSnackBar();
    await shareFiles([
      for (final file in files) ShareableFile(file.name, file.mime, file.bytes),
    ], subject: shareSubject ?? baseName);
  } on PlatformException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(e.code == 'permission_denied' ? s('exportPermissionDenied') : s('exportError'))),
    );
  } catch (_) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(s('exportError'))));
  }
}

/// Fichier déjà généré (ex: rapport PDF) : propose "Télécharger" ou
/// "Partager", puis informe l'utilisateur du résultat.
Future<void> saveOrShareFile({
  required BuildContext context,
  required Locale locale,
  required String baseName,
  required String extension,
  required String mimeType,
  required List<int> bytes,
  String? shareSubject,
}) async {
  String s(String key) => tr(locale, key);
  final messenger = ScaffoldMessenger.of(context);
  final download = await showModalBottomSheet<bool>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s('exportSheetTitle'),
              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (DownloadSaver.isSupported) ...[
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(s('exportActionDownload'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                icon: const Icon(Icons.ios_share_outlined),
                label: Text(s('exportActionShare'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (download == null) return;
  final suffix = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
  final name = '${_safeFileName(baseName)}_$suffix.$extension';
  try {
    if (download && DownloadSaver.isSupported) {
      final saved = await DownloadSaver.save(fileName: name, mimeType: mimeType, bytes: bytes);
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('${s(isWeb ? 'exportDownloadedOne' : 'exportSavedOne')}\n${saved.fileName}'),
          action: DownloadSaver.canOpen
              ? SnackBarAction(
                  label: s('exportOpen'),
                  onPressed: () async {
                    if (!await DownloadSaver.open(saved)) {
                      messenger.showSnackBar(SnackBar(content: Text(s('exportNoAppToOpen'))));
                    }
                  },
                )
              : null,
        ),
      );
    } else {
      await shareFiles([ShareableFile(name, mimeType, bytes)], subject: shareSubject ?? baseName);
    }
  } on PlatformException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(e.code == 'permission_denied' ? s('exportPermissionDenied') : s('exportError'))),
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(s('exportError'))));
  }
}

String _safeFileName(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').replaceAll(RegExp(r'_+'), '_');
  final trimmed = cleaned.replaceAll(RegExp(r'^_|_$'), '');
  return trimmed.isEmpty ? 'export' : trimmed;
}
