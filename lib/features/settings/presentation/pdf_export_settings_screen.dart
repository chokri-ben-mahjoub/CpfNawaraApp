import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/export/pdf_export_settings.dart';
import '../../../core/l10n/app_strings.dart';

/// Page « Exports PDF » : ce qui s'affiche dans tous les PDF et où (courbes,
/// date et heure, en-tête, pied de page, orientation, taille du texte).
class PdfExportSettingsScreen extends ConsumerStatefulWidget {
  const PdfExportSettingsScreen({super.key});

  @override
  ConsumerState<PdfExportSettingsScreen> createState() => _PdfExportSettingsScreenState();
}

class _PdfExportSettingsScreenState extends ConsumerState<PdfExportSettingsScreen> {
  PdfExportSettings _cfg = const PdfExportSettings();
  bool _loaded = false;
  final _header = TextEditingController();
  final _footer = TextEditingController();

  @override
  void initState() {
    super.initState();
    PdfExportSettings.load().then((c) {
      if (!mounted) return;
      setState(() {
        _cfg = c;
        _header.text = c.headerText;
        _footer.text = c.footerText;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  void _update(PdfExportSettings c) {
    setState(() => _cfg = c);
    c.save();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final now = DateTime.now();

    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
    );

    Widget choice<T>(String label, T value, List<(T, String)> options, void Function(T) onChanged) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final o in options)
                ChoiceChip(label: Text(o.$2), selected: o.$1 == value, onSelected: (_) => onChanged(o.$1)),
            ],
          ),
        ],
      ),
    );

    Widget toggle(String label, bool value, void Function(bool) onChanged) => SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );

    return Scaffold(
      appBar: AppBar(title: Text(s('pdfSetTitle'))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Text(s('pdfSetIntro'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                title(s('pdfSetCharts')),
                choice<PdfChartsPosition>(s('pdfSetChartsPos'), _cfg.charts, [
                  (PdfChartsPosition.after, s('pdfSetChartsAfter')),
                  (PdfChartsPosition.before, s('pdfSetChartsBefore')),
                  (PdfChartsPosition.hidden, s('pdfSetHidden')),
                ], (v) => _update(_cfg.copyWith(charts: v))),
                title(s('pdfSetDate')),
                choice<PdfDatePlacement>(s('pdfSetDatePlacement'), _cfg.datePlacement, [
                  (PdfDatePlacement.header, s('pdfSetPlaceHeader')),
                  (PdfDatePlacement.footer, s('pdfSetPlaceFooter')),
                  (PdfDatePlacement.top, s('pdfSetPlaceTop')),
                  (PdfDatePlacement.hidden, s('pdfSetHidden')),
                ], (v) => _update(_cfg.copyWith(datePlacement: v))),
                choice<int>(s('pdfSetDateFormat'), _cfg.dateFormat, [
                  for (var i = 0; i < PdfExportSettings.dateFormats.length; i++)
                    (i, _cfg.copyWith(dateFormat: i, showTime: false).stamp(now)),
                ], (v) => _update(_cfg.copyWith(dateFormat: v))),
                toggle(s('pdfSetShowTime'), _cfg.showTime, (v) => _update(_cfg.copyWith(showTime: v))),
                Text('${s('pdfSetPreview')} : ${_cfg.stamp(now)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                title(s('pdfSetHeaderFooter')),
                toggle(s('pdfSetLogo'), _cfg.showLogo, (v) => _update(_cfg.copyWith(showLogo: v))),
                toggle(s('pdfSetAppName'), _cfg.showAppName, (v) => _update(_cfg.copyWith(showAppName: v))),
                toggle(s('pdfSetTitleShow'), _cfg.showTitle, (v) => _update(_cfg.copyWith(showTitle: v))),
                toggle(s('pdfSetOperator'), _cfg.showOperator, (v) => _update(_cfg.copyWith(showOperator: v))),
                toggle(s('pdfSetPages'), _cfg.showPageNumbers, (v) => _update(_cfg.copyWith(showPageNumbers: v))),
                const SizedBox(height: 8),
                TextField(
                  controller: _header,
                  decoration: InputDecoration(labelText: s('pdfSetHeaderText'), border: const OutlineInputBorder()),
                  onChanged: (v) => _update(_cfg.copyWith(headerText: v)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _footer,
                  decoration: InputDecoration(labelText: s('pdfSetFooterText'), border: const OutlineInputBorder()),
                  onChanged: (v) => _update(_cfg.copyWith(footerText: v)),
                ),
                title(s('pdfSetPage')),
                choice<PdfOrientation>(s('pdfSetOrientation'), _cfg.orientation, [
                  (PdfOrientation.auto, s('pdfSetAuto')),
                  (PdfOrientation.portrait, s('pdfSetPortrait')),
                  (PdfOrientation.landscape, s('pdfSetLandscape')),
                ], (v) => _update(_cfg.copyWith(orientation: v))),
                choice<int>(s('pdfSetTextSize'), _cfg.textSize, [
                  (0, s('pdfSetSmall')),
                  (1, s('pdfSetNormal')),
                  (2, s('pdfSetLarge')),
                ], (v) => _update(_cfg.copyWith(textSize: v))),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    _header.clear();
                    _footer.clear();
                    _update(const PdfExportSettings());
                  },
                  icon: const Icon(Icons.restore),
                  label: Text(s('pdfSetReset')),
                ),
              ],
            ),
    );
  }
}
