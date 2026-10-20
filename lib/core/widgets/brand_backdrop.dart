import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Fond de marque des écrans de démarrage (accueil, verrouillage) : dégradé
/// bleu nuit avec halo orange, comme l'écran de chargement et les en-têtes.
class BrandBackdrop extends StatelessWidget {
  final Widget child;

  /// Arrondi du bas (bandeau d'en-tête) ; 0 = plein écran.
  final double bottomRadius;

  const BrandBackdrop({super.key, required this.child, this.bottomRadius = 0});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(bottomRadius)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [deepNavy, Color(0xFF173B54)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -70,
              top: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor.withValues(alpha: 0.2)),
              ),
            ),
            Positioned(
              left: -90,
              bottom: -110,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor.withValues(alpha: 0.08)),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
