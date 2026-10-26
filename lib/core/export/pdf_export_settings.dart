import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PdfChartsPosition { after, before, hidden }

enum PdfDatePlacement { header, footer, top, hidden }

enum PdfOrientation { auto, portrait, landscape }

/// Réglages communs à tous les exports PDF (tableaux, historiques, alertes,
/// rapport usine...) : ce qui s'affiche et où. Mémorisés sur l'appareil.
class PdfExportSettings {
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

  const PdfExportSettings({
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
  });

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
  }) => PdfExportSettings(
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
  );

  static const _p = 'pdf_set_';

  static T _enum<T>(List<T> values, int? i, T fallback) => i != null && i >= 0 && i < values.length ? values[i] : fallback;

  static Future<PdfExportSettings> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      const d = PdfExportSettings();
      return PdfExportSettings(
        charts: _enum(PdfChartsPosition.values, p.getInt('${_p}charts'), d.charts),
        datePlacement: _enum(PdfDatePlacement.values, p.getInt('${_p}datePlacement'), d.datePlacement),
        dateFormat: p.getInt('${_p}dateFormat') ?? d.dateFormat,
        showTime: p.getBool('${_p}showTime') ?? d.showTime,
        showLogo: p.getBool('${_p}showLogo') ?? d.showLogo,
        showAppName: p.getBool('${_p}showAppName') ?? d.showAppName,
        showTitle: p.getBool('${_p}showTitle') ?? d.showTitle,
        showOperator: p.getBool('${_p}showOperator') ?? d.showOperator,
        showPageNumbers: p.getBool('${_p}showPageNumbers') ?? d.showPageNumbers,
        orientation: _enum(PdfOrientation.values, p.getInt('${_p}orientation'), d.orientation),
        textSize: p.getInt('${_p}textSize') ?? d.textSize,
        headerText: p.getString('${_p}headerText') ?? '',
        footerText: p.getString('${_p}footerText') ?? '',
      );
    } catch (_) {
      return const PdfExportSettings();
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('${_p}charts', charts.index);
      await p.setInt('${_p}datePlacement', datePlacement.index);
      await p.setInt('${_p}dateFormat', dateFormat);
      await p.setBool('${_p}showTime', showTime);
      await p.setBool('${_p}showLogo', showLogo);
      await p.setBool('${_p}showAppName', showAppName);
      await p.setBool('${_p}showTitle', showTitle);
      await p.setBool('${_p}showOperator', showOperator);
      await p.setBool('${_p}showPageNumbers', showPageNumbers);
      await p.setInt('${_p}orientation', orientation.index);
      await p.setInt('${_p}textSize', textSize);
      await p.setString('${_p}headerText', headerText);
      await p.setString('${_p}footerText', footerText);
    } catch (_) {}
  }
}
