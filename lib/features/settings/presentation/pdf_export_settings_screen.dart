import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/export/pdf_export_settings.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import 'pdf_page_preview.dart';

/// Page « Exports PDF » : pour chaque famille de PDF (tous les circuits,
/// échantillons CPI, tableaux), tout ce qui s'affiche et où — avec un aperçu
/// de la page qui change en direct à chaque réglage.
class PdfExportSettingsScreen extends ConsumerStatefulWidget {
  const PdfExportSettingsScreen({super.key});

  @override
  ConsumerState<PdfExportSettingsScreen> createState() =>
      _PdfExportSettingsScreenState();
}

class _PdfExportSettingsScreenState
    extends ConsumerState<PdfExportSettingsScreen> {
  PdfReportKind _kind = PdfReportKind.allCircuits;

  /// Circuit précis en cours d'édition (famille « échantillons produits »
  /// seulement) ; `null` = réglages génériques de la famille.
  String? _circuitId;
  PdfExportSettings _cfg = PdfExportSettings.defaults(
    PdfReportKind.allCircuits,
  );
  bool _loaded = false;
  bool _showPreview = true;
  final _header = TextEditingController();
  final _footer = TextEditingController();
  final _title = TextEditingController();
  final _role = TextEditingController();
  final _watermark = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load(_kind);
  }

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    _title.dispose();
    _role.dispose();
    _watermark.dispose();
    super.dispose();
  }

  Future<void> _load(PdfReportKind kind, {String? circuitId}) async {
    final c = await PdfExportSettings.load(kind, circuitId);
    if (!mounted) return;
    setState(() {
      _kind = kind;
      _circuitId = kind == PdfReportKind.samples ? circuitId : null;
      _cfg = c;
      _header.text = c.headerText;
      _footer.text = c.footerText;
      _title.text = c.reportTitle;
      _role.text = c.signatureRole;
      _watermark.text = c.watermark;
      _loaded = true;
    });
  }

  void _update(PdfExportSettings c) {
    setState(() => _cfg = c);
    c.save();
  }

  /// Applique un modèle aux trois familles de PDF d'un coup (même style
  /// partout — tableaux, tous les circuits, échantillons produits), pas
  /// seulement à celle affichée à l'écran. Toujours les réglages génériques
  /// de chaque famille, jamais le style d'un circuit précis en cours
  /// d'édition (sinon « partout » écraserait un seul circuit au lieu de
  /// tous).
  Future<void> _applyPresetEverywhere(PdfPreset preset) async {
    for (final kind in PdfReportKind.values) {
      final base = (kind == _kind && _circuitId == null) ? _cfg : await PdfExportSettings.load(kind);
      final applied = preset.applyTo(base);
      await applied.save();
      if (kind == _kind && _circuitId == null && mounted) setState(() => _cfg = applied);
    }
    if (!mounted) return;
    final locale = ref.read(localeProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(locale, 'pdfPresetAppliedEverywhere'))),
    );
  }

  /// Chaque réglage est déjà enregistré en direct ([_update]) ; ce bouton ne
  /// fait qu'enregistrer une dernière fois (au cas où un champ de texte en
  /// cours de saisie n'aurait pas encore déclenché son `onChanged`) et le
  /// confirme à l'utilisateur, pour qu'il sache que c'est bien pris en
  /// compte avant de quitter l'écran.
  Future<void> _saveNow() async {
    FocusScope.of(context).unfocus();
    await _cfg.save();
    if (!mounted) return;
    final locale = ref.read(localeProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(locale, 'pdfSetSaved'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final operatorName = ref.watch(profileProvider)?.fullName ?? '';
    final scheme = Theme.of(context).colorScheme;

    // Puces qui passent à la ligne (un sélecteur segmenté déborderait de
    // l'écran d'un téléphone).
    const kindIcons = {
      PdfReportKind.allCircuits: Icons.layers_outlined,
      PdfReportKind.samples: Icons.science_outlined,
      PdfReportKind.tables: Icons.table_chart_outlined,
    };
    final kinds = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final kind in PdfReportKind.values)
          ChoiceChip(
            avatar: Icon(kindIcons[kind], size: 18),
            label: Text(s(kind.labelKey)),
            selected: _kind == kind,
            showCheckmark: false,
            onSelected: (_) => _load(kind),
          ),
      ],
    );

    // Style propre à un circuit (famille « échantillons produits »
    // seulement) : « Par défaut » reprend les réglages génériques ci-dessus,
    // chaque circuit personnalisé prend le dessus pour ses propres exports.
    final circuits = ref.watch(plantControllerProvider).circuits;
    final circuitPicker = _kind != PdfReportKind.samples || circuits.isEmpty
        ? null
        : Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.tune, size: 18),
                label: Text(s('pdfCircuitDefault')),
                selected: _circuitId == null,
                showCheckmark: false,
                onSelected: (_) => _load(_kind),
              ),
              for (final circuit in circuits)
                ChoiceChip(
                  avatar: Icon(circuit.icon, size: 18, color: circuit.color),
                  label: Text(s(circuit.labelKey)),
                  selected: _circuitId == circuit.id,
                  showCheckmark: false,
                  onSelected: (_) => _load(_kind, circuitId: circuit.id),
                ),
            ],
          );

    final preview = Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.visibility_outlined,
                size: 18,
                color: accentColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s('pdfLivePreview'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Flexible(
                child: Text(
                  _circuitId == null
                      ? s(_kind.labelKey)
                      : '${s(_kind.labelKey)} · ${s(circuits.firstWhere((c) => c.id == _circuitId, orElse: () => circuits.first).labelKey)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Center(
              child: PdfPagePreview(
                cfg: _cfg,
                s: s,
                operatorName: operatorName,
                circuit: _circuitId == null
                    ? null
                    : circuits.firstWhere((c) => c.id == _circuitId, orElse: () => circuits.first),
              ),
            ),
          ),
        ],
      ),
    );

    final hintKey = switch (_kind) {
      PdfReportKind.allCircuits => 'pdfKindAllHint',
      PdfReportKind.samples => 'pdfKindSamplesHint',
      PdfReportKind.tables => 'pdfKindTablesHint',
    };

    final settings = ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      children: [
        Text(
          s(hintKey),
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
        if (circuitPicker != null) ...[
          const SizedBox(height: 12),
          Text(
            s('pdfCircuitPickerLabel'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 8),
          circuitPicker,
          if (_circuitId != null) ...[
            const SizedBox(height: 6),
            Text(
              s('pdfCircuitOverrideHint'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ],
        const SizedBox(height: 12),
        _presets(context, s),
        const SizedBox(height: 14),
        _card(context, Icons.title, s('pdfSecTexts'), [
          if (_kind.isPlant) ...[
            _field(
              _title,
              s('pdfSetReportTitle'),
              hint: s(
                _kind == PdfReportKind.allCircuits
                    ? 'plantReportTitle'
                    : 'plantSampleReportTitle',
              ),
              helper: s('pdfSetReportTitleHelper'),
              maxLines: 4,
              onChanged: (v) => _update(_cfg.copyWith(reportTitle: v)),
            ),
            _field(
              _role,
              s('pdfSetSignatureRole'),
              hint: s('plantReportRole'),
              helper: s('pdfSetEmptyDefault'),
              onChanged: (v) => _update(_cfg.copyWith(signatureRole: v)),
            ),
          ],
          _field(
            _header,
            s('pdfSetHeaderText'),
            onChanged: (v) => _update(_cfg.copyWith(headerText: v)),
          ),
          _field(
            _footer,
            s('pdfSetFooterText'),
            onChanged: (v) => _update(_cfg.copyWith(footerText: v)),
          ),
        ]),
        _card(context, Icons.event_outlined, s('pdfSetDate'), [
          _chips<PdfDatePlacement>(
            s('pdfSetDatePlacement'),
            _cfg.datePlacement,
            [
              (PdfDatePlacement.header, s('pdfSetPlaceHeader')),
              (PdfDatePlacement.footer, s('pdfSetPlaceFooter')),
              (PdfDatePlacement.top, s('pdfSetPlaceTop')),
              (PdfDatePlacement.hidden, s('pdfSetHidden')),
            ],
            (v) => _update(_cfg.copyWith(datePlacement: v)),
          ),
          _chips<int>(s('pdfSetDateFormat'), _cfg.dateFormat, [
            for (var i = 0; i < PdfExportSettings.dateFormats.length; i++)
              (i, _cfg.copyWith(dateFormat: i, showTime: false).stamp()),
          ], (v) => _update(_cfg.copyWith(dateFormat: v))),
          _switch(
            s('pdfSetShowTime'),
            _cfg.showTime,
            (v) => _update(_cfg.copyWith(showTime: v)),
          ),
        ]),
        _card(context, Icons.vertical_align_top, s('pdfSetHeaderFooter'), [
          _switch(
            s('pdfSetLogo'),
            _cfg.showLogo,
            (v) => _update(_cfg.copyWith(showLogo: v)),
          ),
          _switch(
            s('pdfSetLogoRight'),
            _cfg.logoRight,
            (v) => _update(_cfg.copyWith(logoRight: v)),
          ),
          _switch(
            s('pdfSetAppName'),
            _cfg.showAppName,
            (v) => _update(_cfg.copyWith(showAppName: v)),
          ),
          _switch(
            s('pdfSetTitleShow'),
            _cfg.showTitle,
            (v) => _update(_cfg.copyWith(showTitle: v)),
          ),
          if (_kind.isPlant) ...[
            _switch(
              s('pdfSetReportNumber'),
              _cfg.showReportNumber,
              (v) => _update(_cfg.copyWith(showReportNumber: v)),
            ),
            _switch(
              s('pdfSetCoverPage'),
              _cfg.coverPage,
              (v) => _update(_cfg.copyWith(coverPage: v)),
            ),
          ],
          _switch(
            s('pdfSetOperator'),
            _cfg.showOperator,
            (v) => _update(_cfg.copyWith(showOperator: v)),
          ),
          _switch(
            s('pdfSetPages'),
            _cfg.showPageNumbers,
            (v) => _update(_cfg.copyWith(showPageNumbers: v)),
          ),
        ]),
        _card(context, Icons.dashboard_customize_outlined, s('pdfSecContent'), [
          _chips<PdfChartsPosition>(s('pdfSetChartsPos'), _cfg.charts, [
            (PdfChartsPosition.after, s('pdfSetChartsAfter')),
            (PdfChartsPosition.before, s('pdfSetChartsBefore')),
            (PdfChartsPosition.hidden, s('pdfSetHidden')),
          ], (v) => _update(_cfg.copyWith(charts: v))),
          if (_kind.isPlant) ...[
            _switch(
              s('reportOpt_circuitBadge'),
              _cfg.showCircuitBadge,
              (v) => _update(_cfg.copyWith(showCircuitBadge: v)),
            ),
            _switch(
              s('pdfSetGasBottles'),
              _cfg.showGasBottles,
              (v) => _update(_cfg.copyWith(showGasBottles: v)),
            ),
            _switch(
              s('pdfSetMethods'),
              _cfg.showMethods,
              (v) => _update(_cfg.copyWith(showMethods: v)),
            ),
            _switch(
              s('pdfSetScopeOfWork'),
              _cfg.showScopeOfWork,
              (v) => _update(_cfg.copyWith(showScopeOfWork: v)),
            ),
            _switch(
              s('reportOpt_photo'),
              _cfg.showPhoto,
              (v) => _update(_cfg.copyWith(showPhoto: v)),
            ),
            _switch(
              s('reportOpt_limitColumn'),
              _cfg.showLimit,
              (v) => _update(_cfg.copyWith(showLimit: v)),
            ),
            _switch(
              s('reportOpt_statusColumn'),
              _cfg.showStatus,
              (v) => _update(_cfg.copyWith(showStatus: v)),
            ),
            _switch(
              s('reportOpt_highlightOutOfRange'),
              _cfg.highlightOutOfRange,
              (v) => _update(_cfg.copyWith(highlightOutOfRange: v)),
            ),
            _switch(
              s('reportOpt_outOfRangeComments'),
              _cfg.showOutOfRangeComments,
              (v) => _update(_cfg.copyWith(showOutOfRangeComments: v)),
            ),
            _switch(
              s('reportOpt_details'),
              _cfg.showDetails,
              (v) => _update(_cfg.copyWith(showDetails: v)),
            ),
            _switch(
              s('reportOpt_samplingTime'),
              _cfg.showSamplingTime,
              (v) => _update(_cfg.copyWith(showSamplingTime: v)),
            ),
            _switch(
              s('reportOpt_allAnalyses'),
              _cfg.allAnalyses,
              (v) => _update(_cfg.copyWith(allAnalyses: v)),
            ),
            _switch(
              s('reportOpt_signatureBottom'),
              _cfg.showSignature,
              (v) => _update(_cfg.copyWith(showSignature: v)),
            ),
          ],
        ]),
        _card(context, Icons.palette_outlined, s('pdfSecLook'), [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s('pdfSetColors'), style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < pdfPalettes.length; i++)
                      Tooltip(
                        message: s(pdfPalettes[i].nameKey),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _update(_cfg.copyWith(palette: i)),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(pdfPalettes[i].accent), Color(pdfPalettes[i].header)],
                              ),
                              border: Border.all(
                                color: _cfg.palette == i ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: _cfg.palette == i ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _chips<int>(s('pdfSetTableStyle'), _cfg.tableStyle, [
            (0, s('pdfTableFilled')),
            (1, s('pdfTableLines')),
            (2, s('pdfTableZebra')),
            (3, s('pdfTableOfficial')),
          ], (v) => _update(_cfg.copyWith(tableStyle: v))),
          _chips<int>(s('pdfSetMargins'), _cfg.margins, [
            (0, s('pdfMarginTight')),
            (1, s('pdfSetNormal')),
            (2, s('pdfMarginWide')),
          ], (v) => _update(_cfg.copyWith(margins: v))),
          _field(
            _watermark,
            s('pdfSetWatermark'),
            hint: s('pdfSetWatermarkHint'),
            helper: s('pdfSetEmptyNone'),
            onChanged: (v) => _update(_cfg.copyWith(watermark: v)),
          ),
        ]),
        _card(context, Icons.crop_portrait, s('pdfSetPage'), [
          _chips<PdfOrientation>(s('pdfSetOrientation'), _cfg.orientation, [
            (PdfOrientation.auto, s('pdfSetAuto')),
            (PdfOrientation.portrait, s('pdfSetPortrait')),
            (PdfOrientation.landscape, s('pdfSetLandscape')),
          ], (v) => _update(_cfg.copyWith(orientation: v))),
          _chips<int>(s('pdfSetTextSize'), _cfg.textSize, [
            (0, s('pdfSetSmall')),
            (1, s('pdfSetNormal')),
            (2, s('pdfSetLarge')),
          ], (v) => _update(_cfg.copyWith(textSize: v))),
        ]),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () {
            _header.clear();
            _footer.clear();
            _title.clear();
            _role.clear();
            _watermark.clear();
            _update(PdfExportSettings.defaults(_kind));
          },
          icon: const Icon(Icons.restore),
          label: Text(s('pdfSetReset')),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(s('pdfSetTitle')),
        actions: [
          if (MediaQuery.sizeOf(context).width < 900)
            IconButton(
              tooltip: s(_showPreview ? 'pdfPreviewHide' : 'pdfPreviewShow'),
              icon: Icon(
                _showPreview
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _showPreview = !_showPreview),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 900;
                final header = Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: kinds,
                );
                if (wide) {
                  return Column(
                    children: [
                      header,
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(flex: 5, child: settings),
                            VerticalDivider(
                              width: 1,
                              color: scheme.outlineVariant,
                            ),
                            Expanded(flex: 4, child: preview),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                final previewHeight = math.min(c.maxHeight * 0.42, 380.0);
                return Column(
                  children: [
                    header,
                    if (_showPreview)
                      SizedBox(height: previewHeight, child: preview),
                    Expanded(child: settings),
                  ],
                );
              },
            ),
      bottomNavigationBar: !_loaded
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _saveNow,
                    icon: const Icon(Icons.check),
                    style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
                    label: Text(s('pdfSetSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _card(
    BuildContext context,
    IconData icon,
    String title,
    List<Widget> children,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // Material (et non un simple Container décoré) : les SwitchListTile
    // qu'il contient ont besoin d'une surface pour leurs effets au toucher.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: accentColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  /// Modèles prêts à l'emploi : un geste applique plusieurs réglages d'un coup
  /// (les textes saisis, titre et fonction sont conservés).
  Widget _presets(BuildContext context, String Function(String) s) {
    final scheme = Theme.of(context).colorScheme;
    const icons = {
      PdfPreset.classic: Icons.auto_awesome_mosaic_outlined,
      PdfPreset.minimal: Icons.crop_square,
      PdfPreset.compact: Icons.density_small,
      PdfPreset.detailed: Icons.dashboard_outlined,
      PdfPreset.official: Icons.verified_outlined,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_fix_high, size: 18, color: accentColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                s('pdfPresets'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final preset in PdfPreset.values)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Material(
                    color: scheme.surfaceContainerLowest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: InkWell(
                      customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      onTap: () => _applyPresetEverywhere(preset),
                      child: Container(
                        width: 170,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(icons[preset], size: 18, color: accentColor),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    s(preset.labelKey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s(preset.hintKey),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _switch(String label, bool value, void Function(bool) onChanged) =>
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: onChanged,
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    String? helper,
    int maxLines = 1,
    required void Function(String) onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: maxLines > 1 ? TextInputType.multiline : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    ),
  );

  Widget _chips<T>(
    String label,
    T value,
    List<(T, String)> options,
    void Function(T) onChanged,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final o in options)
              ChoiceChip(
                label: Text(o.$2),
                selected: o.$1 == value,
                onSelected: (_) => onChanged(o.$1),
              ),
          ],
        ),
      ],
    ),
  );
}
