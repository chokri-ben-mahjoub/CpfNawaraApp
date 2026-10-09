import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';

enum ExportFormat { excel, csv }

/// Demande à l'utilisateur le format d'export souhaité (Excel ou CSV).
/// Retourne `null` si l'utilisateur ferme la feuille sans choisir.
Future<ExportFormat?> chooseExportFormat(BuildContext context, Locale locale) {
  String s(String key) => tr(locale, key);
  final scheme = Theme.of(context).colorScheme;

  return showModalBottomSheet<ExportFormat>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s('exportChooseFormatTitle'),
              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x1FFF7A33),
                child: Icon(Icons.table_chart_outlined, color: accentColor),
              ),
              title: Text(s('exportFormatExcel'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(s('exportFormatExcelHint'), style: TextStyle(color: scheme.onSurfaceVariant)),
              onTap: () => Navigator.of(sheetContext).pop(ExportFormat.excel),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x1FFF7A33),
                child: Icon(Icons.description_outlined, color: accentColor),
              ),
              title: Text(s('exportFormatCsv'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(s('exportFormatCsvHint'), style: TextStyle(color: scheme.onSurfaceVariant)),
              onTap: () => Navigator.of(sheetContext).pop(ExportFormat.csv),
            ),
          ],
        ),
      ),
    ),
  );
}
