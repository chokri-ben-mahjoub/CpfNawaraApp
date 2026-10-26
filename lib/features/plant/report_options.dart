import '../../core/export/pdf_export_settings.dart';

/// Contenu d'un export de rapport usine, tel que choisi dans la fenêtre
/// « Contenu du rapport » à l'export. Les valeurs de départ viennent des
/// réglages de la famille de PDF (Réglages › Exports PDF) et le choix fait à
/// l'export y est mémorisé.
class ReportOptions {
  final bool curves;
  final bool photo;
  final bool limitColumn;
  final bool statusColumn;
  final bool details; // source, opérateur, commentaire
  final bool samplingTime;
  final bool allAnalyses; // sinon : seulement la plus récente du jour
  final bool signatureBottom;
  final bool logo;

  const ReportOptions({
    this.curves = false,
    this.photo = true,
    this.limitColumn = true,
    this.statusColumn = true,
    this.details = true,
    this.samplingTime = true,
    this.allAnalyses = true,
    this.signatureBottom = true,
    this.logo = true,
  });

  static const keys = [
    'curves',
    'photo',
    'limitColumn',
    'statusColumn',
    'details',
    'samplingTime',
    'allAnalyses',
    'signatureBottom',
    'logo',
  ];

  bool operator [](String key) => switch (key) {
    'curves' => curves,
    'photo' => photo,
    'limitColumn' => limitColumn,
    'statusColumn' => statusColumn,
    'details' => details,
    'samplingTime' => samplingTime,
    'allAnalyses' => allAnalyses,
    'signatureBottom' => signatureBottom,
    _ => logo,
  };

  factory ReportOptions.fromMap(Map<String, bool> m) => ReportOptions(
    curves: m['curves'] ?? false,
    photo: m['photo'] ?? true,
    limitColumn: m['limitColumn'] ?? true,
    statusColumn: m['statusColumn'] ?? true,
    details: m['details'] ?? true,
    samplingTime: m['samplingTime'] ?? true,
    allAnalyses: m['allAnalyses'] ?? true,
    signatureBottom: m['signatureBottom'] ?? true,
    logo: m['logo'] ?? true,
  );

  /// Contenu défini par les réglages d'une famille de PDF.
  factory ReportOptions.of(PdfExportSettings c) => ReportOptions(
    curves: c.charts != PdfChartsPosition.hidden,
    photo: c.showPhoto,
    limitColumn: c.showLimit,
    statusColumn: c.showStatus,
    details: c.showDetails,
    samplingTime: c.showSamplingTime,
    allAnalyses: c.allAnalyses,
    signatureBottom: c.showSignature,
    logo: c.showLogo,
  );

  /// Réglages [c] mis à jour avec ce contenu (choix fait à l'export).
  PdfExportSettings applyTo(PdfExportSettings c) => c.copyWith(
    charts: curves ? (c.charts == PdfChartsPosition.hidden ? PdfChartsPosition.after : c.charts) : PdfChartsPosition.hidden,
    showPhoto: photo,
    showLimit: limitColumn,
    showStatus: statusColumn,
    showDetails: details,
    showSamplingTime: samplingTime,
    allAnalyses: allAnalyses,
    showSignature: signatureBottom,
    showLogo: logo,
  );
}
