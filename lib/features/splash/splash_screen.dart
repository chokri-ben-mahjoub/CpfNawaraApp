import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme/app_theme.dart';

/// Écran de démarrage (splash) affiché au lancement, pendant le chargement
/// de l'app : même présentation que l'écran natif d'Android et que celui de
/// la version web (fond bleu nuit, logo, nom, barre de progression).
class SplashScreen extends StatefulWidget {
  /// Libellé sous le nom de l'app (traduit par l'appelant).
  final String tagline;
  const SplashScreen({super.key, this.tagline = 'Suivi des analyses de puits'});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  late final AnimationController _bar = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.65, curve: Curves.easeOutBack));
    final text = CurvedAnimation(parent: _intro, curve: const Interval(0.3, 1, curve: Curves.easeOutCubic));
    return Scaffold(
      backgroundColor: deepNavy,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, 1.5),
            radius: 1.3,
            colors: [accentColor.withValues(alpha: 0.35), deepNavy.withValues(alpha: 0)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: logo,
                child: ScaleTransition(
                  scale: Tween(begin: 0.7, end: 1.0).animate(logo),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      // Contour discret : le logo (bleu nuit) se détache du fond.
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1.5),
                      boxShadow: [BoxShadow(color: accentColor.withValues(alpha: 0.3), blurRadius: 40, spreadRadius: -6)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset('assets/icon/icon.png', fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              FadeTransition(
                opacity: text,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(text),
                  child: Column(
                    children: [
                      Text(
                        appDisplayName,
                        style: const TextStyle(color: Color(0xFFF5EDE8), fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.tagline,
                        style: TextStyle(color: const Color(0xFFF5EDE8).withValues(alpha: 0.7), fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 26),
              FadeTransition(
                opacity: text,
                child: Container(
                  width: 160,
                  height: 4,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: AnimatedBuilder(
                    animation: _bar,
                    builder: (context, _) => FractionalTranslation(
                      translation: Offset(-1 + _bar.value * 3.5, 0),
                      child: FractionallySizedBox(
                        widthFactor: 0.4,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
