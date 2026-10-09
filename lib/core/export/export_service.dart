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
import 'share_files.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const _csvMime = 'text/csv';

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
Future<void> runExport({
  required BuildContext context,
  required Locale locale,
  required String baseName,
  required List<ExportTable> tables,
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
  if (choice == null) return;

  messenger.showSnackBar(SnackBar(content: Text(s('exportStarted')), duration: const Duration(seconds: 1)));
  final safeBase = _safeFileName(baseName);
  final suffix = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  try {
    final files = <_GeneratedFile>[];
    if (choice.format == ExportFormat.excel) {
      final bytes = ExcelExporter.encode(nonEmpty);
      if (bytes == null) throw StateError('excel encode failed');
      files.add(_GeneratedFile('${safeBase}_$suffix.xlsx', _xlsxMime, bytes));
    } else {
      for (final table in nonEmpty) {
        final name = nonEmpty.length == 1
            ? '${safeBase}_$suffix.csv'
            : '${safeBase}_${_safeFileName(table.name)}_$suffix.csv';
        files.add(_GeneratedFile(name, _csvMime, CsvExporter.encode(table)));
      }
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
          content: Text(
            saved.length == 1 ? '${s(one)}\n${saved.first.fileName}' : '${saved.length} ${s(many)}',
          ),
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
    await shareFiles(
      [for (final file in files) ShareableFile(file.name, file.mime, file.bytes)],
      subject: shareSubject ?? baseName,
    );
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

String _safeFileName(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').replaceAll(RegExp(r'_+'), '_');
  final trimmed = cleaned.replaceAll(RegExp(r'^_|_$'), '');
  return trimmed.isEmpty ? 'export' : trimmed;
}
