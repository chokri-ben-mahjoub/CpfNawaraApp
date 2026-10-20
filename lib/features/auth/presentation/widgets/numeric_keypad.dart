import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../../core/theme/app_theme.dart';

/// Pavé numérique pour la saisie d'un code à 4 chiffres (déverrouillage
/// rapide), utilisable avec des gants (grandes zones de tap).
class NumericKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  /// Touches en verre dépoli, pour les fonds sombres (écran de verrouillage).
  final bool glass;

  const NumericKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.glass = false,
  });

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final digit in row)
                  _KeypadButton(
                    label: digit,
                    glass: glass,
                    onTap: () => onDigit(digit),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (onBiometric != null)
                _KeypadButton(
                  icon: Icons.fingerprint,
                  glass: glass,
                  onTap: onBiometric!,
                )
              else
                const SizedBox(width: 72, height: 72),
              _KeypadButton(
                label: '0',
                glass: glass,
                onTap: () => onDigit('0'),
              ),
              _KeypadButton(
                icon: Icons.backspace_outlined,
                glass: glass,
                onTap: onBackspace,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool glass;
  final VoidCallback onTap;

  const _KeypadButton({
    this.label,
    this.icon,
    this.glass = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = icon == Icons.fingerprint
        ? accentColor
        : (glass
              ? Colors.white.withValues(alpha: 0.75)
              : scheme.onSurfaceVariant);
    final content = Center(
      child: label != null
          ? Text(
              label!,
              style: TextStyle(
                fontSize: glass ? 29 : 24,
                fontWeight: glass ? FontWeight.w500 : FontWeight.w700,
                color: glass ? Colors.white : null,
              ),
            )
          : Icon(icon, color: iconColor, size: 26),
    );

    if (!glass) {
      return Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 72, height: 72, child: content),
        ),
      );
    }

    // Verre dépoli : disque translucide, fin liseré clair, flou de l'arrière-plan.
    // Les touches sans libellé (empreinte, effacer) restent sans fond.
    final filled = label != null;
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: filled
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.transparent,
          shape: CircleBorder(
            side: BorderSide(
              color: Colors.white.withValues(alpha: filled ? 0.16 : 0),
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            splashColor: accentColor.withValues(alpha: 0.35),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox(width: 76, height: 76, child: content),
          ),
        ),
      ),
    );
  }
}
