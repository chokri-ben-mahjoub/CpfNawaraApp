import 'dart:convert';

/// Police PDF (polices standard du format, aucune à embarquer).
enum PdfFontFamily { helvetica, times, courier }

enum PdfTextAlign { left, center, right }

/// Style d'un texte du PDF. Les champs `null` signifient « automatique » :
/// taille calculée selon le nombre de colonnes, couleur suivant la palette.
/// Les valeurs par défaut reproduisent le rendu d'avant la personnalisation.
class PdfTextStyleSpec {
  final PdfFontFamily family;
  final double? size;
  final bool bold;
  final bool italic;
  final int? colorArgb;
  final PdfTextAlign align;

  const PdfTextStyleSpec({
    this.family = PdfFontFamily.helvetica,
    this.size,
    this.bold = false,
    this.italic = false,
    this.colorArgb,
    this.align = PdfTextAlign.left,
  });

  PdfTextStyleSpec copyWith({
    PdfFontFamily? family,
    double? size,
    bool clearSize = false,
    bool? bold,
    bool? italic,
    int? colorArgb,
    bool clearColor = false,
    PdfTextAlign? align,
  }) => PdfTextStyleSpec(
    family: family ?? this.family,
    size: clearSize ? null : (size ?? this.size),
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    colorArgb: clearColor ? null : (colorArgb ?? this.colorArgb),
    align: align ?? this.align,
  );

  Map<String, dynamic> toJson() => {
    'family': family.index,
    'size': size,
    'bold': bold,
    'italic': italic,
    'color': colorArgb,
    'align': align.index,
  };

  factory PdfTextStyleSpec.fromJson(Map<String, dynamic>? j, PdfTextStyleSpec fallback) {
    if (j == null) return fallback;
    T pick<T>(List<T> v, Object? i, T d) => i is int && i >= 0 && i < v.length ? v[i] : d;
    final size = j['size'];
    return PdfTextStyleSpec(
      family: pick(PdfFontFamily.values, j['family'], fallback.family),
      size: size is num && size >= 4 && size <= 72 ? size.toDouble() : (j.containsKey('size') ? null : fallback.size),
      bold: j['bold'] is bool ? j['bold'] as bool : fallback.bold,
      italic: j['italic'] is bool ? j['italic'] as bool : fallback.italic,
      colorArgb: j['color'] is int ? j['color'] as int : (j.containsKey('color') ? null : fallback.colorArgb),
      align: pick(PdfTextAlign.values, j['align'], fallback.align),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfTextStyleSpec &&
      other.family == family &&
      other.size == size &&
      other.bold == bold &&
      other.italic == italic &&
      other.colorArgb == colorArgb &&
      other.align == align;

  @override
  int get hashCode => Object.hash(family, size, bold, italic, colorArgb, align);
}

/// Position et taille libres d'un élément déplaçable à la souris sur la page
/// de garde (logo, bloc titre, filigrane) : [dx]/[dy] sont la fraction
/// (0 à 1) de la zone utile de la page où placer son coin haut-gauche,
/// [scale] multiplie sa taille normale, [angleDeg] le fait pivoter (filigrane
/// seulement). `null` dans [PdfStyleSet] = position historique, inchangée.
class PdfElementLayout {
  final double dx;
  final double dy;
  final double scale;
  final double angleDeg;

  const PdfElementLayout({this.dx = 0.5, this.dy = 0.5, this.scale = 1, this.angleDeg = 0});

  PdfElementLayout copyWith({double? dx, double? dy, double? scale, double? angleDeg}) =>
      PdfElementLayout(dx: dx ?? this.dx, dy: dy ?? this.dy, scale: scale ?? this.scale, angleDeg: angleDeg ?? this.angleDeg);

  Map<String, dynamic> toJson() => {'dx': dx, 'dy': dy, 'scale': scale, 'angle': angleDeg};

  factory PdfElementLayout.fromJson(Map<String, dynamic>? j, PdfElementLayout fallback) {
    if (j == null) return fallback;
    double num0(String k, double lo, double hi, double d) {
      final v = j[k];
      return v is num && v >= lo && v <= hi ? v.toDouble() : d;
    }

    return PdfElementLayout(
      dx: num0('dx', 0, 1, fallback.dx),
      dy: num0('dy', 0, 1, fallback.dy),
      scale: num0('scale', 0.2, 4, fallback.scale),
      angleDeg: num0('angle', -180, 180, fallback.angleDeg),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfElementLayout && other.dx == dx && other.dy == dy && other.scale == scale && other.angleDeg == angleDeg;

  @override
  int get hashCode => Object.hash(dx, dy, scale, angleDeg);
}

/// Apparence du cadre des tableaux. `null` = automatique (suit la palette).
class PdfTableStyleSpec {
  final int? headerBgArgb;
  final int borderArgb;
  final double borderWidth;

  /// Marges intérieures des cellules ; `null` = automatiques (plus serrées
  /// quand le tableau a beaucoup de colonnes).
  final double? padH;
  final double? padV;

  /// Espace avant un titre de tableau et entre le titre et le tableau.
  final double spaceBeforeTable;
  final double spaceAfterTitle;

  const PdfTableStyleSpec({
    this.headerBgArgb,
    this.borderArgb = 0xFFBDBDBD,
    this.borderWidth = 0.5,
    this.padH,
    this.padV,
    this.spaceBeforeTable = 16,
    this.spaceAfterTitle = 6,
  });

  PdfTableStyleSpec copyWith({
    int? headerBgArgb,
    bool clearHeaderBg = false,
    int? borderArgb,
    double? borderWidth,
    double? padH,
    double? padV,
    bool clearPadding = false,
    double? spaceBeforeTable,
    double? spaceAfterTitle,
  }) => PdfTableStyleSpec(
    headerBgArgb: clearHeaderBg ? null : (headerBgArgb ?? this.headerBgArgb),
    borderArgb: borderArgb ?? this.borderArgb,
    borderWidth: borderWidth ?? this.borderWidth,
    padH: clearPadding ? null : (padH ?? this.padH),
    padV: clearPadding ? null : (padV ?? this.padV),
    spaceBeforeTable: spaceBeforeTable ?? this.spaceBeforeTable,
    spaceAfterTitle: spaceAfterTitle ?? this.spaceAfterTitle,
  );

  Map<String, dynamic> toJson() => {
    'headerBg': headerBgArgb,
    'border': borderArgb,
    'borderWidth': borderWidth,
    'padH': padH,
    'padV': padV,
    'spaceBefore': spaceBeforeTable,
    'spaceAfterTitle': spaceAfterTitle,
  };

  factory PdfTableStyleSpec.fromJson(Map<String, dynamic>? j) {
    const d = PdfTableStyleSpec();
    if (j == null) return d;
    double? num0(Object? v, double lo, double hi) => v is num && v >= lo && v <= hi ? v.toDouble() : null;
    return PdfTableStyleSpec(
      headerBgArgb: j['headerBg'] is int ? j['headerBg'] as int : null,
      borderArgb: j['border'] is int ? j['border'] as int : d.borderArgb,
      borderWidth: num0(j['borderWidth'], 0, 5) ?? d.borderWidth,
      padH: num0(j['padH'], 0, 30),
      padV: num0(j['padV'], 0, 30),
      spaceBeforeTable: num0(j['spaceBefore'], 0, 80) ?? d.spaceBeforeTable,
      spaceAfterTitle: num0(j['spaceAfterTitle'], 0, 80) ?? d.spaceAfterTitle,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfTableStyleSpec &&
      other.headerBgArgb == headerBgArgb &&
      other.borderArgb == borderArgb &&
      other.borderWidth == borderWidth &&
      other.padH == padH &&
      other.padV == padV &&
      other.spaceBeforeTable == spaceBeforeTable &&
      other.spaceAfterTitle == spaceAfterTitle;

  @override
  int get hashCode => Object.hash(headerBgArgb, borderArgb, borderWidth, padH, padV, spaceBeforeTable, spaceAfterTitle);
}

/// Style fin des éléments typographiques d'un PDF : titre du rapport, titre
/// de tableau, en-têtes de colonnes, cellules, et cadre des tableaux.
///
/// Les défauts ([PdfStyleSet.defaults]) reproduisent exactement l'apparence
/// codée en dur auparavant : un PDF non personnalisé reste inchangé.
class PdfStyleSet {
  final PdfTextStyleSpec reportTitle;
  final PdfTextStyleSpec tableTitle;
  final PdfTextStyleSpec columnHeader;
  final PdfTextStyleSpec cell;
  final PdfTableStyleSpec table;

  /// En-tête et pied de page de chaque page, et textes secondaires (notes
  /// grises : équipement, source, mentions « aucune analyse »…). Pour ces
  /// trois-là, la taille et la couleur `null` laissent chaque élément à son
  /// propre réglage historique, et « gras » vrai force le gras partout (faux =
  /// inchangé) ; l'alignement n'a pas d'effet.
  final PdfTextStyleSpec pageHeader;
  final PdfTextStyleSpec pageFooter;
  final PdfTextStyleSpec secondary;

  /// Position/taille libres sur la page de garde (voir [PdfElementLayout]) :
  /// `null` = position historique (logo absent de la page de garde, titre
  /// centré, filigrane centré à -35°). Dès qu'on déplace un élément à la
  /// souris, il obtient sa position et le reste en mode libre.
  final PdfElementLayout? logoLayout;
  final PdfElementLayout? titleLayout;
  final PdfElementLayout? watermarkLayout;

  const PdfStyleSet({
    this.pageHeader = const PdfTextStyleSpec(),
    this.pageFooter = const PdfTextStyleSpec(),
    this.secondary = const PdfTextStyleSpec(),
    this.reportTitle = const PdfTextStyleSpec(size: 16, bold: true, colorArgb: 0xFF0B1E2D),
    this.tableTitle = const PdfTextStyleSpec(size: 12, bold: true, colorArgb: 0xFF0B1E2D),
    // Taille et couleur automatiques : taille selon le nombre de colonnes,
    // couleur blanche sur fond plein ou couleur d'en-tête sinon.
    this.columnHeader = const PdfTextStyleSpec(bold: true, align: PdfTextAlign.center),
    this.cell = const PdfTextStyleSpec(),
    this.table = const PdfTableStyleSpec(),
    this.logoLayout,
    this.titleLayout,
    this.watermarkLayout,
  });

  static const defaults = PdfStyleSet();

  PdfStyleSet copyWith({
    PdfTextStyleSpec? reportTitle,
    PdfTextStyleSpec? tableTitle,
    PdfTextStyleSpec? columnHeader,
    PdfTextStyleSpec? cell,
    PdfTableStyleSpec? table,
    PdfTextStyleSpec? pageHeader,
    PdfTextStyleSpec? pageFooter,
    PdfTextStyleSpec? secondary,
    PdfElementLayout? logoLayout,
    bool clearLogoLayout = false,
    PdfElementLayout? titleLayout,
    bool clearTitleLayout = false,
    PdfElementLayout? watermarkLayout,
    bool clearWatermarkLayout = false,
  }) => PdfStyleSet(
    pageHeader: pageHeader ?? this.pageHeader,
    pageFooter: pageFooter ?? this.pageFooter,
    secondary: secondary ?? this.secondary,
    reportTitle: reportTitle ?? this.reportTitle,
    tableTitle: tableTitle ?? this.tableTitle,
    columnHeader: columnHeader ?? this.columnHeader,
    cell: cell ?? this.cell,
    table: table ?? this.table,
    logoLayout: clearLogoLayout ? null : (logoLayout ?? this.logoLayout),
    titleLayout: clearTitleLayout ? null : (titleLayout ?? this.titleLayout),
    watermarkLayout: clearWatermarkLayout ? null : (watermarkLayout ?? this.watermarkLayout),
  );

  bool get isDefault => this == defaults;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'reportTitle': reportTitle.toJson(),
    'tableTitle': tableTitle.toJson(),
    'columnHeader': columnHeader.toJson(),
    'cell': cell.toJson(),
    'table': table.toJson(),
    'pageHeader': pageHeader.toJson(),
    'pageFooter': pageFooter.toJson(),
    'secondary': secondary.toJson(),
    if (logoLayout != null) 'logoLayout': logoLayout!.toJson(),
    if (titleLayout != null) 'titleLayout': titleLayout!.toJson(),
    if (watermarkLayout != null) 'watermarkLayout': watermarkLayout!.toJson(),
  };

  String encode() => jsonEncode(toJson());

  factory PdfStyleSet.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? m(String k) => j[k] is Map ? Map<String, dynamic>.from(j[k] as Map) : null;
    const d = PdfStyleSet.defaults;
    return PdfStyleSet(
      reportTitle: PdfTextStyleSpec.fromJson(m('reportTitle'), d.reportTitle),
      tableTitle: PdfTextStyleSpec.fromJson(m('tableTitle'), d.tableTitle),
      columnHeader: PdfTextStyleSpec.fromJson(m('columnHeader'), d.columnHeader),
      cell: PdfTextStyleSpec.fromJson(m('cell'), d.cell),
      table: PdfTableStyleSpec.fromJson(m('table')),
      pageHeader: PdfTextStyleSpec.fromJson(m('pageHeader'), d.pageHeader),
      pageFooter: PdfTextStyleSpec.fromJson(m('pageFooter'), d.pageFooter),
      secondary: PdfTextStyleSpec.fromJson(m('secondary'), d.secondary),
      logoLayout: m('logoLayout') == null ? null : PdfElementLayout.fromJson(m('logoLayout'), const PdfElementLayout()),
      titleLayout: m('titleLayout') == null ? null : PdfElementLayout.fromJson(m('titleLayout'), const PdfElementLayout()),
      watermarkLayout: m('watermarkLayout') == null
          ? null
          : PdfElementLayout.fromJson(m('watermarkLayout'), const PdfElementLayout()),
    );
  }

  /// Relit un style sérialisé ; toute donnée absente ou corrompue redonne les
  /// défauts, sans jamais lever d'erreur.
  factory PdfStyleSet.decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final j = jsonDecode(raw);
      return j is Map ? PdfStyleSet.fromJson(Map<String, dynamic>.from(j)) : defaults;
    } catch (_) {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PdfStyleSet &&
      other.reportTitle == reportTitle &&
      other.tableTitle == tableTitle &&
      other.columnHeader == columnHeader &&
      other.cell == cell &&
      other.table == table &&
      other.pageHeader == pageHeader &&
      other.pageFooter == pageFooter &&
      other.secondary == secondary &&
      other.logoLayout == logoLayout &&
      other.titleLayout == titleLayout &&
      other.watermarkLayout == watermarkLayout;

  @override
  int get hashCode => Object.hash(
    reportTitle,
    tableTitle,
    columnHeader,
    cell,
    table,
    pageHeader,
    pageFooter,
    secondary,
    logoLayout,
    titleLayout,
    watermarkLayout,
  );
}
