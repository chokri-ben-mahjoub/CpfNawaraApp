import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'responsive.dart';

/// Indicateur de chargement aux couleurs de l'app : un arc orange qui
/// tourne autour d'un petit derrick.
class AppLoader extends StatefulWidget {
  final double size;

  /// Couleur de l'arc (orange par défaut).
  final Color color;

  /// Affiche le derrick au centre (désactivé pour les petites tailles).
  final bool showIcon;

  const AppLoader({super.key, this.size = 48, this.color = accentColor, this.showIcon = true});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.color.withValues(alpha: 0.16);
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => CustomPaint(
            painter: _ArcPainter(progress: _controller.value, color: widget.color, track: track),
            child: child,
          ),
          child: widget.showIcon && widget.size >= 36
              ? Center(child: Icon(Icons.oil_barrel_outlined, size: widget.size * 0.4, color: widget.color))
              : null,
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  _ArcPainter({required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(2.5, size.width / 12);
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawArc(arcRect, 0, math.pi * 2, false, Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    // L'arc s'allonge puis se raccourcit en tournant.
    final sweep = math.pi * (0.35 + 0.9 * (0.5 - 0.5 * math.cos(progress * math.pi * 2)));
    final start = progress * math.pi * 4 - math.pi / 2;
    canvas.drawArc(arcRect, start, sweep, false, Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [color.withValues(alpha: 0.35), color],
        transform: GradientRotation(start),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress || old.color != color;
}

/// Écran de chargement d'une page : indicateur + message, centré.
class LoadingView extends StatelessWidget {
  final String? message;
  const LoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLoader(size: 56),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Exécute [task] en affichant une fenêtre de chargement (génération d'un
/// rapport, lecture d'un fichier...) ; la fenêtre se ferme à la fin, même
/// en cas d'erreur.
Future<T> runWithLoading<T>(BuildContext context, String message, Future<T> Function() task) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, _) => PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Theme.of(dialogContext).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLoader(size: 52),
                  const SizedBox(height: 14),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(animation), child: child),
    ),
  ).whenComplete(() => open = false);
  try {
    return await task();
  } finally {
    if (open && navigator.mounted) navigator.pop();
  }
}

// ------------------------------------------------------------ Squelettes

/// Reflet animé qui balaie les blocs gris d'un squelette (tous en même
/// temps, de gauche à droite).
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = Color.lerp(base, scheme.surface, 0.65)!;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value * 2 - 0.5;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [base, highlight, base],
            stops: [
              (t - 0.25).clamp(0.0, 1.0),
              t.clamp(0.0, 1.0),
              (t + 0.25).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// Bloc gris d'un squelette (texte, image, bouton...).
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Carte squelette : titre + quelques lignes.
class SkeletonCard extends StatelessWidget {
  final int lines;
  final bool avatar;
  const SkeletonCard({super.key, this.lines = 3, this.avatar = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHighest, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (avatar) ...[
            const SkeletonBox(width: 44, height: 44, radius: 14),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FractionallySizedBox(widthFactor: 0.55, child: SkeletonBox(height: 16)),
                for (var i = 0; i < lines; i++) ...[
                  const SizedBox(height: 12),
                  FractionallySizedBox(widthFactor: i.isEven ? 0.9 : 0.7, child: const SkeletonBox(height: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mise en page imitée par un squelette de page.
enum SkeletonLayout { dashboard, list, plant, cards }

/// Page squelette affichée pendant le chargement des données : des blocs
/// gris à la place du contenu, au même endroit.
class SkeletonPage extends StatelessWidget {
  final SkeletonLayout layout;
  const SkeletonPage({super.key, this.layout = SkeletonLayout.cards});

  @override
  Widget build(BuildContext context) {
    final header = <Widget>[
      const FractionallySizedBox(widthFactor: 0.5, alignment: Alignment.centerLeft, child: SkeletonBox(height: 26)),
      const SizedBox(height: 10),
      const FractionallySizedBox(widthFactor: 0.75, alignment: Alignment.centerLeft, child: SkeletonBox(height: 14)),
      const SizedBox(height: 18),
    ];
    final List<Widget> body = switch (layout) {
      SkeletonLayout.dashboard => [
          ...header,
          const SkeletonBox(height: 40, radius: 20),
          const SizedBox(height: 16),
          const SkeletonBox(height: 150, radius: 20),
          const SizedBox(height: 16),
          const SkeletonBox(height: 74, radius: 20),
          const SizedBox(height: 16),
          ResponsiveWrapGrid(children: [for (var i = 0; i < 4; i++) const SkeletonCard(lines: 4)]),
        ],
      SkeletonLayout.list => [
          const SkeletonBox(height: 50, radius: 16),
          const SizedBox(height: 12),
          const Row(
            children: [
              SkeletonBox(width: 110, height: 34, radius: 17),
              SizedBox(width: 8),
              SkeletonBox(width: 90, height: 34, radius: 17),
              SizedBox(width: 8),
              SkeletonBox(width: 100, height: 34, radius: 17),
            ],
          ),
          const SizedBox(height: 18),
          ResponsiveWrapGrid(children: [for (var i = 0; i < 6; i++) const SkeletonCard(lines: 2, avatar: true)]),
        ],
      SkeletonLayout.plant => [
          const SkeletonBox(height: 44, radius: 22),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 64, radius: 16)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 64, radius: 16)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 64, radius: 16)),
            ],
          ),
          const SizedBox(height: 14),
          const SkeletonBox(height: 40, radius: 20),
          const SizedBox(height: 14),
          const AspectRatio(aspectRatio: 1000 / 560, child: SkeletonBox(radius: 20)),
        ],
      SkeletonLayout.cards => [
          ...header,
          for (var i = 0; i < 4; i++) ...[const SkeletonCard(lines: 3), const SizedBox(height: 12)],
        ],
    };
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: pagePadding(context, top: 8, bottom: 24),
        children: body,
      ),
    );
  }
}

/// Lignes squelettes d'une liste (chargement réseau d'une liste, ex: les
/// utilisateurs ou le journal d'audit).
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) => Shimmer(
        child: Column(
          children: [
            for (var i = 0; i < count; i++) ...[
              const SkeletonCard(lines: 1, avatar: true),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
}
