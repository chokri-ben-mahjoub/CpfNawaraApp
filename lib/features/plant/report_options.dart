import 'package:shared_preferences/shared_preferences.dart';

/// Ce qui apparaît dans le rapport usine PDF, au choix du client — mémorisé
/// sur l'appareil et repris à l'export suivant.
class ReportOptions {
  final bool curves;
  final bool photo;
  final bool limitColumn;
  final bool statusColumn;
  final bool details; // source, opérateur, commentaire
  final bool samplingTime;
  final bool allAnalyses; // sinon : seulement la plus récente du jour
  final bool headerDateTime;
  final bool signatureLine;
  final bool logo;

  const ReportOptions({
    this.curves = false,
    this.photo = true,
    this.limitColumn = true,
    this.statusColumn = true,
    this.details = true,
    this.samplingTime = true,
    this.allAnalyses = true,
    this.headerDateTime = true,
    this.signatureLine = true,
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
    'headerDateTime',
    'signatureLine',
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
    'headerDateTime' => headerDateTime,
    'signatureLine' => signatureLine,
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
    headerDateTime: m['headerDateTime'] ?? true,
    signatureLine: m['signatureLine'] ?? true,
    logo: m['logo'] ?? true,
  );

  static Future<ReportOptions> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ReportOptions.fromMap({
        for (final k in keys)
          if (prefs.containsKey('report_opt_$k')) k: prefs.getBool('report_opt_$k')!,
      });
    } catch (_) {
      return const ReportOptions();
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in keys) {
        await prefs.setBool('report_opt_$k', this[k]);
      }
    } catch (_) {}
  }
}
