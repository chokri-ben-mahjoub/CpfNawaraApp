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

/// Palettes proposées : couleur d'accent + couleur d'en-tête de tableau.
const pdfPalettes = <({int accent, int header, String nameKey})>[
  (accent: 0xFFFF7A33, header: 0xFF0B1E2D, nameKey: 'pdfPalOrange'),
  (accent: 0xFF1E88E5, header: 0xFF16344A, nameKey: 'pdfPalBlue'),
  (accent: 0xFF2E9E5B, header: 0xFF14402B, nameKey: 'pdfPalGreen'),
  (accent: 0xFF8E24AA, header: 0xFF2E1A47, nameKey: 'pdfPalPurple'),
  (accent: 0xFFC62828, header: 0xFF2B2B2B, nameKey: 'pdfPalRed'),
  (accent: 0xFF00897B, header: 0xFF0B2E2B, nameKey: 'pdfPalTeal'),
];

/// Modèles prêts à l'emploi : un geste applique plusieurs réglages d'un coup.
enum PdfPreset { classic, minimal, compact, detailed, official }

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

  /// Valeur hors seuil en gras rouge dans le tableau (sinon seule la colonne
  /// « État » le signale, comme avant).
  final bool highlightOutOfRange;

  /// Commentaire saisi pour une valeur hors seuil, imprimé sous le tableau.
  final bool showOutOfRangeComments;

  /// Pastille colorée avec le nom du circuit (ex: "PRODUCED WATER") avant
  /// chaque groupe de points.
  final bool showCircuitBadge;

  // Apparence.
  final int palette; // index dans [pdfPalettes]
  final int tableStyle; // 0 en-tête plein, 1 filets, 2 lignes alternées
  final int margins; // 0 serrées, 1 standard, 2 larges
  final String watermark; // filigrane (ex: CONFIDENTIEL), vide = aucun

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
    this.highlightOutOfRange = true,
    this.showOutOfRangeComments = true,
    this.showCircuitBadge = true,
    this.palette = 0,
    this.tableStyle = 0,
    this.margins = 1,
    this.watermark = '',
  });

  /// Réglages par défaut d'une famille (les rapports usine n'ont pas de
  /// courbes tant qu'on ne les demande pas).
  factory PdfExportSettings.defaults(PdfReportKind kind) =>
      PdfExportSettings(kind: kind, charts: kind.isPlant ? PdfChartsPosition.hidden : PdfChartsPosition.after);

  static const dateFormats = ['dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd'];

  /// Couleur d'accent (titres, filet, nom de l'app) et couleur d'en-tête de
  /// tableau, au format ARGB.
  int get accentArgb => pdfPalettes[palette.clamp(0, pdfPalettes.length - 1)].accent;
  int get headerArgb => pdfPalettes[palette.clamp(0, pdfPalettes.length - 1)].header;

  /// Facteur appliqué aux marges de la page.
  double get marginScale => const [0.6, 1.0, 1.4][margins.clamp(0, 2)];

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
    bool? highlightOutOfRange,
    bool? showOutOfRangeComments,
    bool? showCircuitBadge,
    int? palette,
    int? tableStyle,
    int? margins,
    String? watermark,
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
    highlightOutOfRange: highlightOutOfRange ?? this.highlightOutOfRange,
    showOutOfRangeComments: showOutOfRangeComments ?? this.showOutOfRangeComments,
    showCircuitBadge: showCircuitBadge ?? this.showCircuitBadge,
    palette: palette ?? this.palette,
    tableStyle: tableStyle ?? this.tableStyle,
    margins: margins ?? this.margins,
    watermark: watermark ?? this.watermark,
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
        highlightOutOfRange: p.getBool('${k}highlightOutOfRange') ?? d.highlightOutOfRange,
        showOutOfRangeComments: p.getBool('${k}showOutOfRangeComments') ?? d.showOutOfRangeComments,
        showCircuitBadge: p.getBool('${k}showCircuitBadge') ?? d.showCircuitBadge,
        palette: p.getInt('${k}palette') ?? d.palette,
        tableStyle: p.getInt('${k}tableStyle') ?? d.tableStyle,
        margins: p.getInt('${k}margins') ?? d.margins,
        watermark: p.getString('${k}watermark') ?? '',
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
      await p.setBool('${k}highlightOutOfRange', highlightOutOfRange);
      await p.setBool('${k}showOutOfRangeComments', showOutOfRangeComments);
      await p.setBool('${k}showCircuitBadge', showCircuitBadge);
      await p.setInt('${k}palette', palette);
      await p.setInt('${k}tableStyle', tableStyle);
      await p.setInt('${k}margins', margins);
      await p.setString('${k}watermark', watermark);
    } catch (_) {}
  }
}

extension PdfPresetX on PdfPreset {
  String get labelKey => 'pdfPreset_$name';
  String get hintKey => 'pdfPresetHint_$name';

  /// [base] avec les réglages de ce modèle (les textes libres, titre et
  /// fonction saisis par l'utilisateur sont conservés).
  PdfExportSettings applyTo(PdfExportSettings base) {
    final plant = base.kind.isPlant;
    return switch (this) {
      PdfPreset.classic => base.copyWith(
        palette: 0,
        tableStyle: 0,
        margins: 1,
        textSize: 1,
        showLogo: true,
        showAppName: true,
        showTitle: true,
        showPageNumbers: true,
        datePlacement: PdfDatePlacement.header,
        showDetails: true,
        showPhoto: true,
        showLimit: true,
        showStatus: true,
        showSamplingTime: true,
        allAnalyses: true,
        showSignature: true,
        watermark: '',
      ),
      PdfPreset.minimal => base.copyWith(
        palette: 5,
        tableStyle: 1,
        margins: 2,
        textSize: 1,
        showLogo: true,
        showAppName: false,
        showTitle: true,
        showPageNumbers: true,
        datePlacement: PdfDatePlacement.footer,
        showDetails: false,
        showPhoto: true,
        showLimit: true,
        showStatus: true,
        showSamplingTime: true,
        showSignature: true,
        watermark: '',
      ),
      PdfPreset.compact => base.copyWith(
        palette: 1,
        tableStyle: 2,
        margins: 0,
        textSize: 0,
        showLogo: true,
        showAppName: true,
        showTitle: true,
        showPageNumbers: true,
        datePlacement: PdfDatePlacement.header,
        showDetails: false,
        showPhoto: false,
        showSamplingTime: true,
        allAnalyses: true,
        showSignature: plant,
        watermark: '',
      ),
      PdfPreset.detailed => base.copyWith(
        palette: 0,
        tableStyle: 2,
        margins: 1,
        textSize: 1,
        showLogo: true,
        showAppName: true,
        showTitle: true,
        showReportNumber: true,
        showOperator: true,
        showPageNumbers: true,
        datePlacement: PdfDatePlacement.header,
        showDetails: true,
        showPhoto: true,
        showLimit: true,
        showStatus: true,
        showSamplingTime: true,
        allAnalyses: true,
        showSignature: true,
        charts: PdfChartsPosition.after,
      ),
      PdfPreset.official => base.copyWith(
        palette: 1,
        tableStyle: 3,
        margins: 1,
        textSize: 1,
        showLogo: true,
        showAppName: true,
        showTitle: true,
        showReportNumber: true,
        showOperator: true,
        showPageNumbers: true,
        datePlacement: PdfDatePlacement.header,
        showDetails: true,
        showPhoto: true,
        showLimit: true,
        showStatus: true,
        highlightOutOfRange: true,
        showOutOfRangeComments: true,
        showCircuitBadge: true,
        showSamplingTime: true,
        allAnalyses: true,
        showSignature: true,
        watermark: '',
      ),
    };
  }
}
