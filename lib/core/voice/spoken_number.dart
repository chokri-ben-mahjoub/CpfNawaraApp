/// Convertit une dictée en nombre : « zéro virgule huit » → 0.8,
/// « douze point cinq » → 12.5, « 3,25 » → 3.25, « moins deux » → -2.
/// Français et anglais. `null` si rien d'exploitable n'est reconnu.
double? parseSpokenNumber(String input) {
  var text = input.toLowerCase().trim();
  if (text.isEmpty) return null;
  const accents = {'é': 'e', 'è': 'e', 'ê': 'e', 'à': 'a', 'ù': 'u', 'ô': 'o', 'î': 'i', 'ï': 'i', 'ç': 'c'};
  accents.forEach((k, v) => text = text.replaceAll(k, v));
  // « 0,8 » ou « 0.8 » dictés en chiffres : un séparateur entre deux chiffres.
  text = text.replaceAllMapped(RegExp(r'(\d)\s*[,.]\s*(\d)'), (m) => '${m[1]} virgule ${m[2]}');
  text = text.replaceAll('-', ' ').replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty && t != 'et').toList();

  var negative = false;
  final whole = <String>[];
  final fraction = <String>[];
  var inFraction = false;
  for (final t in tokens) {
    if (t == 'moins' || t == 'minus' || t == 'negative') {
      negative = true;
    } else if (const {'virgule', 'point', 'comma', 'dot'}.contains(t)) {
      inFraction = true;
    } else {
      (inFraction ? fraction : whole).add(t);
    }
  }
  if (whole.isEmpty) return null;

  final integer = _parseInteger(whole);
  if (integer == null) return null;
  var result = integer.toDouble();
  if (fraction.isNotEmpty) {
    final digits = _fractionDigits(fraction);
    if (digits == null) return null;
    result = double.parse('$integer.$digits');
  }
  return negative ? -result : result;
}

const _units = {
  'zero': 0, 'un': 1, 'une': 1, 'deux': 2, 'trois': 3, 'quatre': 4, 'cinq': 5, 'six': 6, 'sept': 7, 'huit': 8,
  'neuf': 9, 'dix': 10, 'onze': 11, 'douze': 12, 'treize': 13, 'quatorze': 14, 'quinze': 15, 'seize': 16,
  // Anglais
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'seven': 7, 'eight': 8, 'nine': 9,
  'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
  'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'oh': 0,
};

const _tens = {
  'vingt': 20, 'trente': 30, 'quarante': 40, 'cinquante': 50, 'soixante': 60,
  'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
};

/// Entier dicté (chiffres ou mots, jusqu'aux milliers).
int? _parseInteger(List<String> tokens) {
  var total = 0;
  var current = 0;
  for (final t in tokens) {
    final digits = int.tryParse(t);
    if (digits != null) {
      current += digits;
    } else if (_units.containsKey(t)) {
      current += _units[t]!;
    } else if (_tens.containsKey(t)) {
      current += _tens[t]!;
    } else if (t == 'cent' || t == 'cents' || t == 'hundred') {
      current = (current == 0 ? 1 : current) * 100;
    } else if (t == 'mille' || t == 'thousand') {
      total += (current == 0 ? 1 : current) * 1000;
      current = 0;
    } else {
      return null;
    }
  }
  return total + current;
}

/// Chiffres après la virgule : dictés un à un (« huit cinq » → 85) ou comme
/// un nombre (« quatre-vingt-cinq » → 85).
String? _fractionDigits(List<String> tokens) {
  final buffer = StringBuffer();
  var allSingle = true;
  for (final t in tokens) {
    final n = int.tryParse(t) ?? _units[t];
    if (n == null || n > 9) {
      allSingle = false;
      break;
    }
    buffer.write(n);
  }
  if (allSingle) return buffer.toString();
  return _parseInteger(tokens)?.toString();
}

/// Texte à mettre dans un champ de saisie pour une valeur dictée (« 12 » et
/// non « 12.0 »).
String spokenNumberText(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
