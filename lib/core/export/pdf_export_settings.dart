import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PdfChartsPosition { after, before, hidden }

enum PdfDatePlacement { header, footer, top, hidden }

enum PdfOrientation { auto, portrait, landscape }

/// Les trois familles de PDF, chacune avec ses propres réglages :
/// * [tables] : tous les exports de tableaux (alertes, stock, historique,
///   tableau de bord...) ;
/// * [allCircuits] : rapport journalier de l'usine, tous les circuits ;
/// * [samples] : échantillons d'un seul circuit, ou analyses choisies d'un
///   point (« Produced samples from CPI »).
enum PdfReportKind { tables, allCircuits, samples }

extension PdfReportKindX on PdfReportKind {
  /// Les anciens réglages (avant les familles) restent ceux des tableaux.
  String get prefix => switch (this) {
    PdfReportKind.tables => 'pdf_set_',
    PdfReportKind.allCircuits => 'pdf_set_all_',
    PdfReportKind.samples => 'pdf_set_smp_',
  };

  bool get isPlant => this != PdfReportKind.tables;

  String get labelKey => switch (this) {
    PdfReportKind.tables => 'pdfKindTables',
    PdfReportKind.allCircuits => 'pdfKindAll',
    PdfReportKind.samples => 'pdfKindSamples',
  };
}

/// Réglages d'une famille de PDF : ce qui s'affiche et où. Mémorisés sur
/// l'appareil.
class PdfExportSettings {
  final PdfReportKind kind;
  final PdfChartsPosition charts;
  final PdfDatePlacement datePlacement;
  final int dateFormat; // index dans [dateFormats]
  final bool showTime;
  final bool showLogo;
  final bool showAppName;
  final bool showTitle;
  final bool showOperator;
  final bool showPageNumbers;
  final PdfOrientation orientation;
  final int textSize; // 0 petit, 1 normal, 2 grand
  final String headerText;
  final String footerText;

  /// Titre et fonction du rapport usine (vide = texte par défaut).
  final String reportTitle;
  final String signatureRole;

  // Contenu du rapport usine.
  final bool showReportNumber;
  final bool showPhoto;
  final bool showLimit;
  final bool showStatus;
  final bool showDetails;
  final bool showSamplingTime;
  final bool allAnalyses; // sinon : seulement la plus récente du jour
  final bool showSignature; // bloc « Date / Nom : fonction » en bas

  const PdfExportSettings({
    this.kind = PdfReportKind.tables,
    this.charts = PdfChartsPosition.after,
    this.datePlacement = PdfDatePlacement.header,
    this.dateFormat = 0,
    this.showTime = true,
    this.showLogo = true,
    this.showAppName = true,
    this.showTitle = true,
    this.showOperator = true,
    this.showPageNumbers = true,
    this.orientation = PdfOrientation.auto,
    this.textSize = 1,
    this.headerText = '',
    this.footerText = '',
    this.reportTitle = '',
    this.signatureRole = '',
    this.showReportNumber = true,
    this.showPhoto = true,
    this.showLimit = true,
    this.showStatus = true,
    this.showDetails = true,
    this.showSamplingTime = true,
    this.allAnalyses = true,
    this.showSignature = true,
  });

  /// Réglages par défaut d'une famille (les rapports usine n'ont pas de
  /// courbes tant qu'on ne les demande pas).
  factory PdfExportSettings.defaults(PdfReportKind kind) =>
      PdfExportSettings(kind: kind, charts: kind.isPlant ? PdfChartsPosition.hidden : PdfChartsPosition.after);

  static const dateFormats = ['dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd'];

  double get textScale => const [0.88, 1.0, 1.15][textSize.clamp(0, 2)];

  /// Date (et heure) du jour au format choisi.
  String stamp([DateTime? at]) {
    final pattern = dateFormats[dateFormat.clamp(0, dateFormats.length - 1)];
    return DateFormat(showTime ? '$pattern HH:mm' : pattern).format(at ?? DateTime.now());
  }

  PdfExportSettings copyWith({
    PdfChartsPosition? charts,
    PdfDatePlacement? datePlacement,
    int? dateFormat,
    bool? showTime,
    bool? showLogo,
    bool? showAppName,
    bool? showTitle,
    bool? showOperator,
    bool? showPageNumbers,
    PdfOrientation? orientation,
    int? textSize,
    String? headerText,
    String? footerText,
    String? reportTitle,
    String? signatureRole,
    bool? showReportNumber,
    bool? showPhoto,
    bool? showLimit,
    bool? showStatus,
    bool? showDetails,
    bool? showSamplingTime,
    bool? allAnalyses,
    bool? showSignature,
  }) => PdfExportSettings(
    kind: kind,
    charts: charts ?? this.charts,
    datePlacement: datePlacement ?? this.datePlacement,
    dateFormat: dateFormat ?? this.dateFormat,
    showTime: showTime ?? this.showTime,
    showLogo: showLogo ?? this.showLogo,
    showAppName: showAppName ?? this.showAppName,
    showTitle: showTitle ?? this.showTitle,
    showOperator: showOperator ?? this.showOperator,
    showPageNumbers: showPageNumbers ?? this.showPageNumbers,
    orientation: orientation ?? this.orientation,
    textSize: textSize ?? this.textSize,
    headerText: headerText ?? this.headerText,
    footerText: footerText ?? this.footerText,
    reportTitle: reportTitle ?? this.reportTitle,
    signatureRole: signatureRole ?? this.signatureRole,
    showReportNumber: showReportNumber ?? this.showReportNumber,
    showPhoto: showPhoto ?? this.showPhoto,
    showLimit: showLimit ?? this.showLimit,
    showStatus: showStatus ?? this.showStatus,
    showDetails: showDetails ?? this.showDetails,
    showSamplingTime: showSamplingTime ?? this.showSamplingTime,
    allAnalyses: allAnalyses ?? this.allAnalyses,
    showSignature: showSignature ?? this.showSignature,
  );

  static T _enum<T>(List<T> values, int? i, T fallback) => i != null && i >= 0 && i < values.length ? values[i] : fallback;

  static Future<PdfExportSettings> load([PdfReportKind kind = PdfReportKind.tables]) async {
    final d = PdfExportSettings.defaults(kind);
    try {
      final p = await SharedPreferences.getInstance();
      final k = kind.prefix;
      return PdfExportSettings(
        kind: kind,
        charts: _enum(PdfChartsPosition.values, p.getInt('${k}charts'), d.charts),
        datePlacement: _enum(PdfDatePlacement.values, p.getInt('${k}datePlacement'), d.datePlacement),
        dateFormat: p.getInt('${k}dateFormat') ?? d.dateFormat,
        showTime: p.getBool('${k}showTime') ?? d.showTime,
        showLogo: p.getBool('${k}showLogo') ?? d.showLogo,
        showAppName: p.getBool('${k}showAppName') ?? d.showAppName,
        showTitle: p.getBool('${k}showTitle') ?? d.showTitle,
        showOperator: p.getBool('${k}showOperator') ?? d.showOperator,
        showPageNumbers: p.getBool('${k}showPageNumbers') ?? d.showPageNumbers,
        orientation: _enum(PdfOrientation.values, p.getInt('${k}orientation'), d.orientation),
        textSize: p.getInt('${k}textSize') ?? d.textSize,
        headerText: p.getString('${k}headerText') ?? '',
        footerText: p.getString('${k}footerText') ?? '',
        reportTitle: p.getString('${k}reportTitle') ?? '',
        signatureRole: p.getString('${k}signatureRole') ?? '',
        showReportNumber: p.getBool('${k}showReportNumber') ?? d.showReportNumber,
        showPhoto: p.getBool('${k}showPhoto') ?? d.showPhoto,
        showLimit: p.getBool('${k}showLimit') ?? d.showLimit,
        showStatus: p.getBool('${k}showStatus') ?? d.showStatus,
        showDetails: p.getBool('${k}showDetails') ?? d.showDetails,
        showSamplingTime: p.getBool('${k}showSamplingTime') ?? d.showSamplingTime,
        allAnalyses: p.getBool('${k}allAnalyses') ?? d.allAnalyses,
        showSignature: p.getBool('${k}showSignature') ?? d.showSignature,
      );
    } catch (_) {
      return d;
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      final k = kind.prefix;
      await p.setInt('${k}charts', charts.index);
      await p.setInt('${k}datePlacement', datePlacement.index);
      await p.setInt('${k}dateFormat', dateFormat);
      await p.setBool('${k}showTime', showTime);
      await p.setBool('${k}showLogo', showLogo);
      await p.setBool('${k}showAppName', showAppName);
      await p.setBool('${k}showTitle', showTitle);
      await p.setBool('${k}showOperator', showOperator);
      await p.setBool('${k}showPageNumbers', showPageNumbers);
      await p.setInt('${k}orientation', orientation.index);
      await p.setInt('${k}textSize', textSize);
      await p.setString('${k}headerText', headerText);
      await p.setString('${k}footerText', footerText);
      await p.setString('${k}reportTitle', reportTitle);
      await p.setString('${k}signatureRole', signatureRole);
      await p.setBool('${k}showReportNumber', showReportNumber);
      await p.setBool('${k}showPhoto', showPhoto);
      await p.setBool('${k}showLimit', showLimit);
      await p.setBool('${k}showStatus', showStatus);
      await p.setBool('${k}showDetails', showDetails);
      await p.setBool('${k}showSamplingTime', showSamplingTime);
      await p.setBool('${k}allAnalyses', allAnalyses);
      await p.setBool('${k}showSignature', showSignature);
    } catch (_) {}
  }
}
