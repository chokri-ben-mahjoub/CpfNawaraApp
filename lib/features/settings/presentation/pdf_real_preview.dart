import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/export/export_table.dart';
import '../../../core/export/pdf_export_settings.dart';
import '../../../core/export/pdf_table_exporter.dart';
import '../../../core/plant/plant_sample.dart';
import '../../plant/plant_report.dart';

/// Aperçu du vrai PDF, généré par le code d'export réel avec des données
/// d'exemple et les réglages en cours d'édition ([cfg], même non encore
/// enregistrés). Regénéré peu après le dernier changement (debounce).
class PdfRealPreview extends StatefulWidget {
  final PdfExportSettings cfg;
  final String title;
  final String Function(String) s;
  final String languageCode;

  /// Données d'exemple par défaut : deux tableaux, dont un large (beaucoup de
  /// colonnes) pour voir l'effet des tailles et marges.
  static List<ExportTable> defaultSample() => [
    const ExportTable(
      name: 'Exemple',
      headers: ['Point', 'Date', 'pH', 'Débit', 'Statut'],
      rows: [
        ['P-101', '12/11/2026', 7.1, 120, 'OK'],
        ['P-102', '12/11/2026', 6.8, 95, 'OK'],
        ['P-103', '12/11/2026', 8.4, 150, 'Hors seuil'],
        ['P-104', '12/11/2026', 7.0, 110, 'OK'],
      ],
    ),
    const ExportTable(
      name: 'Résumé',
      headers: ['Paramètre', 'Min', 'Moyenne', 'Max'],
      rows: [
        ['pH', 6.8, 7.3, 8.4],
        ['Débit', 95, 118, 150],
      ],
    ),
  ];

  const PdfRealPreview({super.key, required this.cfg, required this.title, required this.s, required this.languageCode});

  @override
  State<PdfRealPreview> createState() => _PdfRealPreviewState();
}

class _PdfRealPreviewState extends State<PdfRealPreview> {
  Timer? _debounce;
  Uint8List? _bytes;
  Object? _error;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _schedule(immediate: true);
  }

  @override
  void didUpdateWidget(PdfRealPreview old) {
    super.didUpdateWidget(old);
    if (old.cfg != widget.cfg || old.cfg.style != widget.cfg.style) _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(immediate ? Duration.zero : const Duration(milliseconds: 300), _render);
  }

  Future<void> _render() async {
    final gen = ++_gen;
    try {
      final cfg = widget.cfg;
      final Uint8List bytes;
      if (cfg.kind.isPlant) {
        // Vrai rapport usine, sur des données d'exemple (aucune donnée réelle).
        final day = DateTime.now();
        final plant = samplePlantForPreview(day);
        final all = plant.circuits;
        final one = all.where((c) => c.id == cfg.circuitId);
        final everything = cfg.kind == PdfReportKind.allCircuits;
        bytes = await buildPlantDailyReport(
          controller: plant.controller,
          day: day,
          circuits: everything ? all : [one.isEmpty ? all.first : one.first],
          s: widget.s,
          languageCode: widget.languageCode,
          operatorName: 'Opérateur',
          reportNumber: '1/26',
          allCircuits: everything,
          settings: cfg,
        );
      } else {
        bytes = await PdfTableExporter.encode(PdfRealPreview.defaultSample(), title: widget.title, operatorName: 'Opérateur', settings: cfg);
      }
      if (!mounted || gen != _gen) return;
      setState(() {
        _bytes = bytes;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text('$_error', style: const TextStyle(fontSize: 12)));
    final bytes = _bytes;
    if (bytes == null) return const Center(child: CircularProgressIndicator());
    return PdfPreview(
      // Nouvelle clé à chaque rendu : PdfPreview recharge alors le document.
      key: ValueKey(_gen),
      build: (_) async => bytes,
      useActions: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      allowPrinting: false,
      allowSharing: false,
      pdfPreviewPageDecoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10)],
      ),
      loadingWidget: const Center(child: CircularProgressIndicator()),
    );
  }
}
