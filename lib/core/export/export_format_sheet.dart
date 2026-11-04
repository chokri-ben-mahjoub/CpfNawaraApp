import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../platform/app_platform.dart';
import '../theme/app_theme.dart';
import 'download_saver.dart';

enum ExportFormat { excel, csv, pdf, word }

/// Télécharger = enregistrer directement sur le téléphone (dossier
/// Téléchargements) ; Partager = volet de partage natif (WhatsApp, mail...).
enum ExportAction { download, share }

class ExportChoice {
  final ExportFormat format;
  final ExportAction action;
  const ExportChoice(this.format, this.action);
}

const _lastFormatKey = 'export_last_format';

/// Demande le format (Excel ou CSV) et l'action (télécharger ou partager).
/// Le dernier format choisi est pré-sélectionné. Retourne `null` si
/// l'utilisateur ferme la feuille sans choisir.
const _formatKeys = {
  ExportFormat.excel: 'excel',
  ExportFormat.csv: 'csv',
  ExportFormat.pdf: 'pdf',
  ExportFormat.word: 'word',
};

Future<ExportChoice?> chooseExport(BuildContext context, Locale locale) async {
  final prefs = await SharedPreferences.getInstance();
  final savedKey = prefs.getString(_lastFormatKey);
  final initial = _formatKeys.entries.firstWhere((e) => e.value == savedKey, orElse: () => _formatKeys.entries.first).key;
  if (!context.mounted) return null;

  final choice = await showModalBottomSheet<ExportChoice>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => _ExportSheet(locale: locale, initialFormat: initial),
  );
  if (choice != null) {
    await prefs.setString(_lastFormatKey, _formatKeys[choice.format]!);
  }
  return choice;
}

class _ExportSheet extends StatefulWidget {
  final Locale locale;
  final ExportFormat initialFormat;
  const _ExportSheet({required this.locale, required this.initialFormat});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late ExportFormat _format = widget.initialFormat;

  @override
  Widget build(BuildContext context) {
    String s(String key) => tr(widget.locale, key);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s('exportSheetTitle'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(s('exportSheetSubtitle'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _FormatCard(
                    icon: Icons.table_chart_outlined,
                    title: s('exportFormatExcel'),
                    hint: s('exportFormatExcelHint'),
                    selected: _format == ExportFormat.excel,
                    onTap: () => setState(() => _format = ExportFormat.excel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FormatCard(
                    icon: Icons.description_outlined,
                    title: s('exportFormatCsv'),
                    hint: s('exportFormatCsvHint'),
                    selected: _format == ExportFormat.csv,
                    onTap: () => setState(() => _format = ExportFormat.csv),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FormatCard(
                    icon: Icons.picture_as_pdf_outlined,
                    title: s('exportFormatPdf'),
                    hint: s('exportFormatPdfHint'),
                    selected: _format == ExportFormat.pdf,
                    onTap: () => setState(() => _format = ExportFormat.pdf),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FormatCard(
                    icon: Icons.article_outlined,
                    title: s('exportFormatWord'),
                    hint: s('exportFormatWordHint'),
                    selected: _format == ExportFormat.word,
                    onTap: () => setState(() => _format = ExportFormat.word),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (DownloadSaver.isSupported) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(ExportChoice(_format, ExportAction.download)),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(s('exportActionDownload'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  s(isWeb ? 'exportActionDownloadHintWeb' : 'exportActionDownloadHint'),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(ExportChoice(_format, ExportAction.share)),
                icon: const Icon(Icons.ios_share_outlined),
                label: Text(s('exportActionShare'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                s('exportActionShareHint'),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  const _FormatCard({
    required this.icon,
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? accentColor.withValues(alpha: 0.10) : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? accentColor : scheme.outlineVariant, width: selected ? 1.6 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: selected ? accentColor : scheme.onSurfaceVariant, size: 20),
                const Spacer(),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? accentColor : scheme.outline,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 2),
            Text(hint, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
