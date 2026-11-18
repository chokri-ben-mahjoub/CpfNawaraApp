import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Aperçu plein écran d'un rapport PDF, avant de l'envoyer ou de
/// l'enregistrer : on voit la mise en page réelle (pages, tableaux...).
class ReportPreviewPage extends StatelessWidget {
  const ReportPreviewPage({super.key, required this.title, required this.bytes});

  final String title;
  final List<int> bytes;

  @override
  Widget build(BuildContext context) {
    final data = Uint8List.fromList(bytes);
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: PdfPreview(
        build: (_) async => data,
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
      ),
    );
  }
}
