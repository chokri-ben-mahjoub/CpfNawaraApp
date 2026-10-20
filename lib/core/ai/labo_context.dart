import '../analysis/series.dart';
import '../data/stock_repository.dart';
import '../data/wells_repository.dart';
import '../plant/plant_repository.dart';

const _maxChars = 24000;
const _wellDays = 21;
const _plantDays = 14;

/// Instantané texte du laboratoire envoyé à l'assistant : valeurs récentes
/// par puits et par point, seuils, stock. Volontairement compact et borné.
String buildLaboContext({
  required WellsState data,
  required PlantState plantState,
  required PlantController plant,
  required StockState stock,
  required DateTime today,
  required String Function(String) s,
}) {
  final b = StringBuffer();
  String d(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  b.writeln('Date du jour : ${d(today)}');

  b.writeln('\n## PUITS (analyses des $_wellDays derniers jours ; format date=valeur)');
  final since = today.subtract(const Duration(days: _wellDays));
  for (final well in data.wells.where((w) => w.active)) {
    final lines = <String>[];
    for (final type in data.analysisTypes) {
      final records = data.records
          .where((r) => r.wellId == well.id && r.typeId == type.id && r.dateTime.isAfter(since))
          .toList()
        ..sort((a, c) => a.dateTime.compareTo(c.dateTime));
      if (records.isEmpty) continue;
      final values = records.map((r) => '${d(r.dateTime)}=${formatNumber(r.value)}').join(', ');
      lines.add('  - ${type.label} [${type.unit}] seuil ${type.min}..${type.max} : $values');
    }
    if (lines.isEmpty) continue;
    b.writeln('Puits ${well.name} (${well.code})');
    lines.forEach(b.writeln);
  }

  b.writeln('\n## USINE (points d\'échantillonnage, $_plantDays derniers jours)');
  final plantSince = today.subtract(const Duration(days: _plantDays));
  for (final point in plantState.points.where((p) => p.active)) {
    final analyses = plantState.analyses.where((a) => a.pointId == point.id && a.date.isAfter(plantSince)).toList()
      ..sort((a, c) => a.date.compareTo(c.date));
    if (analyses.isEmpty) continue;
    b.writeln('Point ${point.code} ${point.name} (${s(point.circuit.labelKey)})');
    for (final param in point.params) {
      final entries = [
        for (final a in analyses)
          if (a.values[param.key] != null)
            '${d(a.date)}=${param.isNumeric ? formatNumber((a.values[param.key] as num).toDouble()) : s('${a.values[param.key]}')}',
      ];
      if (entries.isEmpty) continue;
      final t = plant.threshold(point.id, param.key);
      final limit = t == null || t.isEmpty ? '' : ' seuil ${t.min ?? ''}..${t.max ?? ''}';
      b.writeln('  - ${s(param.labelKey)} [${param.unit}]$limit : ${entries.join(', ')}');
    }
  }

  b.writeln('\n## STOCK');
  for (final item in stock.items) {
    b.writeln('  - ${item.name} : ${formatNumber(item.quantity)} ${item.unit} (seuil ${formatNumber(item.threshold)})'
        '${item.isLow ? ' ALERTE' : ''}');
  }

  final text = b.toString();
  return text.length <= _maxChars ? text : '${text.substring(0, _maxChars)}\n[… tronqué]';
}

const assistantSystemPrompt =
    'Tu es l\'assistant d\'un laboratoire d\'analyse de puits et d\'usine pétrolière/gazière (CPF Nawara). '
    'Réponds en français, de façon concise et concrète, uniquement à partir des données fournies ci-dessous. '
    'Si une information manque, dis-le au lieu de l\'inventer. Cite les puits, points et dates concernés. '
    'Pour comparer ou tendancer, donne les chiffres clés. Tu ne remplaces pas un jugement d\'ingénieur : '
    'signale les valeurs hors seuil et les dérives.\n\nDONNÉES :\n';
