import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Largeur à partir de laquelle l'app passe en mise en page "grand écran"
/// (web, PC, tablette paysage) : menu latéral et grilles multi-colonnes.
const wideBreakpoint = 900.0;

/// Largeur maximale du contenu : au-delà, il est centré plutôt qu'étiré.
const contentMaxWidth = 1120.0;

bool isWideLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= wideBreakpoint;

/// Marges d'une page défilante : 16 px sur téléphone, contenu centré dans
/// [maxWidth] sur grand écran.
EdgeInsets pagePadding(
  BuildContext context, {
  double top = 8,
  double bottom = 24,
  double maxWidth = contentMaxWidth,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final side = math.max(16.0, (width - maxWidth) / 2);
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}

/// Nombre de colonnes adapté à la largeur disponible (cartes de puits,
/// sections du tableau de bord...).
int columnsFor(double width, {double minItemWidth = 360, int max = 3}) =>
    (width / minItemWidth).floor().clamp(1, max);

/// Grille simple à hauteur libre : les éléments d'une même ligne gardent leur
/// propre hauteur (contrairement à GridView), utile pour des cartes de
/// contenu variable.
class ResponsiveWrapGrid extends StatelessWidget {
  final List<Widget> children;

  /// Espace horizontal entre colonnes.
  final double spacing;

  /// Espace vertical entre lignes (par défaut [spacing]) — 0 pour des cartes
  /// qui ont déjà leur propre marge basse.
  final double? runSpacing;
  final double minItemWidth;
  final int maxColumns;

  const ResponsiveWrapGrid({
    super.key,
    required this.children,
    this.spacing = 12,
    this.runSpacing,
    this.minItemWidth = 360,
    this.maxColumns = 3,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth, minItemWidth: minItemWidth, max: maxColumns);
        final vertical = runSpacing ?? spacing;
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0 && vertical > 0) SizedBox(height: vertical),
                children[i],
              ],
            ],
          );
        }
        final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: vertical,
          children: [for (final child in children) SizedBox(width: itemWidth, child: child)],
        );
      },
    );
  }
}

/// SafeArea dont le contenu reste dans une colonne centrée de [maxWidth] sur
/// grand écran (écrans d'accueil, de profil, de code) au lieu de s'étirer.
class NarrowSafeArea extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const NarrowSafeArea({super.key, required this.child, this.maxWidth = 520});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      ),
    );
  }
}
