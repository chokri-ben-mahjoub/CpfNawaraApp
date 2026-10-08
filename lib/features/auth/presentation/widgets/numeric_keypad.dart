import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Pavé numérique pour la saisie d'un code à 4 chiffres (déverrouillage
/// rapide), utilisable avec des gants (grandes zones de tap).
class NumericKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  const NumericKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
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
              children: [for (final digit in row) _KeypadButton(label: digit, onTap: () => onDigit(digit))],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (onBiometric != null)
                _KeypadButton(icon: Icons.fingerprint, onTap: onBiometric!)
              else
                const SizedBox(width: 72, height: 72),
              _KeypadButton(label: '0', onTap: () => onDigit('0')),
              _KeypadButton(icon: Icons.backspace_outlined, onTap: onBackspace),
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
  final VoidCallback onTap;

  const _KeypadButton({this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: label != null
                ? Text(label!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700))
                : Icon(icon, color: icon == Icons.fingerprint ? accentColor : scheme.onSurfaceVariant, size: 26),
          ),
        ),
      ),
    );
  }
}
