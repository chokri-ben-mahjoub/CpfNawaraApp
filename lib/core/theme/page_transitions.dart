import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Transition entre deux pages : la nouvelle page arrive en glissant
/// légèrement depuis la droite et en apparaissant en fondu ; la page
/// quittée glisse un peu vers la gauche et s'estompe (axe horizontal
/// partagé, Material). Identique sur téléphone, PC et web.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final exit = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: Offset.zero, end: const Offset(-0.05, 0)).animate(exit),
      child: FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.5).animate(exit),
        child: SlideTransition(
          position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(enter),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.7, curve: Curves.easeOut)),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Mêmes transitions sur toutes les plateformes.
const appPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: AppPageTransitionsBuilder(),
    TargetPlatform.windows: AppPageTransitionsBuilder(),
    TargetPlatform.linux: AppPageTransitionsBuilder(),
    TargetPlatform.macOS: AppPageTransitionsBuilder(),
    // iOS : transition native (retour par balayage depuis le bord).
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
  },
);

/// Fondu d'apparition, une seule fois (première page après l'écran de
/// démarrage, changement d'onglet...).
class FadeInOnce extends StatefulWidget {
  final Widget child;
  final Duration duration;
  const FadeInOnce({super.key, required this.child, this.duration = const Duration(milliseconds: 350)});

  @override
  State<FadeInOnce> createState() => _FadeInOnceState();
}

class _FadeInOnceState extends State<FadeInOnce> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration)
    ..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut), child: widget.child);
}
