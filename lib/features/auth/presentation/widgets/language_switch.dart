import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

/// Petit sélecteur FR/EN affiché en haut des écrans d'authentification.
class LanguageSwitch extends ConsumerWidget {
  /// Variante pour fond sombre (verre dépoli, sélection orange).
  final bool dark;

  const LanguageSwitch({super.key, this.dark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.12)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in supportedLocales)
            _LangChip(
              label: l.languageCode.toUpperCase(),
              selected: l.languageCode == locale.languageCode,
              dark: dark,
              onTap: () => ref.read(localeProvider.notifier).setLocale(l),
            ),
        ],
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  const _LangChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? (dark ? accentColor : scheme.primary)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected
                ? (dark ? Colors.white : scheme.onPrimary)
                : (dark
                      ? Colors.white.withValues(alpha: 0.7)
                      : scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
