import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Texte dont le premier nombre entier « défile » de 0 à sa valeur à
/// l'apparition (ex: « 12 », « 8/12 », « 97 % »). Un texte sans nombre en
/// tête s'affiche tel quel.
class AnimatedNumberText extends StatelessWidget {
  final String value;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow? overflow;
  final Duration duration;

  const AnimatedNumberText(
    this.value, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.duration = const Duration(milliseconds: 750),
  });

  static final _leading = RegExp(r'^(\d{1,9})(.*)$', dotAll: true);

  @override
  Widget build(BuildContext context) {
    final m = _leading.firstMatch(value);
    if (m == null) return Text(value, style: style, maxLines: maxLines, overflow: overflow);
    final target = int.parse(m.group(1)!);
    final rest = m.group(2)!;
    return TweenAnimationBuilder<double>(
      key: ValueKey(value),
      tween: Tween(begin: 0, end: target.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}$rest', style: style, maxLines: maxLines, overflow: overflow),
    );
  }
}

/// Apparition en fondu + léger glissement vers le haut ; [index] décale les
/// éléments d'une liste les uns après les autres (effet « cascade »).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    final steps = math.min(widget.index, 8);
    final total = 380 + steps * 60;
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: total))..forward();
    final begin = steps * 60 / total;
    _curve = CurvedAnimation(parent: _controller, curve: Interval(begin, 1, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(offset: Offset(0, 14 * (1 - _curve.value)), child: child),
      ),
    );
  }
}

/// Jauge circulaire animée : arc de [value] (0 à 1) sur un anneau, contenu
/// libre au centre.
class CircularGauge extends StatelessWidget {
  final double value;
  final Color color;
  final double size;
  final double strokeWidth;
  final Widget? center;

  const CircularGauge({
    super.key,
    required this.value,
    required this.color,
    this.size = 84,
    this.strokeWidth = 9,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _GaugePainter(v, color, track, strokeWidth),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  final double stroke;
  _GaugePainter(this.value, this.color, this.track, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    const start = -math.pi / 2;
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      start,
      math.pi * 2 * value,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + math.pi * 2,
          colors: [color.withValues(alpha: 0.55), color],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}

/// Flèche de tendance ▲▼ avec écart (ex: « ▲ 12 % »). [goodWhenUp] inverse
/// le code couleur (vert quand la valeur baisse, ex: nombre de hors-limites).
class TrendBadge extends StatelessWidget {
  final double delta;
  final String text;
  final bool goodWhenUp;

  const TrendBadge({super.key, required this.delta, required this.text, this.goodWhenUp = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final flat = delta.abs() < 1e-9;
    final good = flat ? null : (delta > 0) == goodWhenUp;
    final color = flat ? scheme.onSurfaceVariant : (good! ? const Color(0xFF2E7D32) : scheme.error);
    final icon = flat ? Icons.remove_rounded : (delta > 0 ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded);
    return BounceIn(
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 2, 8, 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

/// Retour tactile : la carte se « tasse » légèrement tant qu'on l'appuie
/// (sans gêner l'InkWell / le clic du contenu).
class TapScale extends StatefulWidget {
  final Widget child;
  final double scale;
  const TapScale({super.key, required this.child, this.scale = 0.97});

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Apparition avec un petit rebond élastique (pastilles, coches, badges).
class BounceIn extends StatelessWidget {
  final Widget child;
  const BounceIn({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: child,
    );
  }
}
