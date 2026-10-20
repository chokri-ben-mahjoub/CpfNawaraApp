import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brand_backdrop.dart';

/// Bandeau d'en-tête des écrans d'installation : fond de marque (bleu nuit,
/// halos orange), pastille d'icône en verre, titre et sous-titre en blanc.
/// Le formulaire s'affiche juste dessous, sur fond clair.
class AuthHeaderBand extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final String? backTooltip;
  final Widget? trailing;
  final double maxWidth;

  const AuthHeaderBand({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.backTooltip,
    this.trailing,
    this.maxWidth = 560,
  });

  @override
  Widget build(BuildContext context) {
    return BrandBackdrop(
      bottomRadius: 32,
      child: SizedBox(
        width: double.infinity,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          if (onBack != null)
                            IconButton(
                              tooltip: backTooltip,
                              onPressed: onBack,
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                            ),
                          const Spacer(),
                          ?trailing,
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.3),
                            blurRadius: 28,
                            spreadRadius: -6,
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 14.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Indicateur du code à 4 chiffres : une pastille par chiffre, qui s'étire et
/// s'illumine en orange à la saisie, rouge en cas d'erreur.
class PinDots extends StatelessWidget {
  final int length;
  final int filled;
  final bool error;

  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: i < filled ? 34 : 14,
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: error
                  ? const Color(0xFFFF6B6B)
                  : (i < filled
                        ? accentColor
                        : Colors.white.withValues(alpha: 0.18)),
              boxShadow: i < filled && !error
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.6),
                        blurRadius: 12,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
          ),
      ],
    );
  }
}
