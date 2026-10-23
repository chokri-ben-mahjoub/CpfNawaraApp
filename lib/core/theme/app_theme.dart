import 'package:flutter/material.dart';

import 'page_transitions.dart';

/// Couleur d'accent de l'app Suivi Puits (ambre énergie, inspiré du secteur gazier).
const accentColor = Color(0xFFFF7A33);

/// Bleu nuit profond utilisé pour les fonds et dégradés "industriels".
const deepNavy = Color(0xFF0B1E2D);

class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    var colorScheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: brightness,
    );
    if (brightness == Brightness.dark) {
      // Mode sombre soigné : fond presque noir (économie d'énergie sur les
      // écrans OLED), surfaces étagées en bleu nuit et accent plus lumineux.
      colorScheme = colorScheme.copyWith(
        surface: const Color(0xFF070B10),
        surfaceContainerLowest: const Color(0xFF05080C),
        surfaceContainerLow: const Color(0xFF0E141B),
        surfaceContainer: const Color(0xFF121A22),
        surfaceContainerHigh: const Color(0xFF18212B),
        surfaceContainerHighest: const Color(0xFF1F2A36),
        onSurface: const Color(0xFFE8EDF2),
        onSurfaceVariant: const Color(0xFFA6B2BF),
        outline: const Color(0xFF55667A),
        outlineVariant: const Color(0xFF243242),
        primary: const Color(0xFFFF9457),
        onPrimary: const Color(0xFF3A1600),
        primaryContainer: const Color(0xFF5A2A0E),
        onPrimaryContainer: const Color(0xFFFFDBC8),
        surfaceTint: Colors.transparent,
      );
    }
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      fontFamily: 'Manrope',
      pageTransitionsTheme: appPageTransitionsTheme,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant.withValues(alpha: 0.6), space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primary.withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.16),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ).copyWith(color: colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      // Messages flottants (arrondis, avec marges) : plus lisibles sur grand
      // écran qu'une barre pleine largeur.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }
}
