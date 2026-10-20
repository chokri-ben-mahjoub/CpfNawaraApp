import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// En-tête "héros" des fiches (puits...) : dégradé nuit, grande icône, titre,
/// pastille d'état et quelques chiffres clés alignés en bas.
class HeroHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? pillLabel;
  final Color pillColor;

  /// Remplace l'icône (ex: avatar du profil).
  final Widget? leading;
  final List<HeroStat> stats;

  const HeroHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.pillLabel,
    this.pillColor = Colors.white,
    this.leading,
    this.stats = const [],
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [deepNavy, Color(0xFF173B54)],
          ),
        ),
        child: Stack(
          children: [
            // Halo décoratif.
            Positioned(
              right: -40,
              top: -50,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.22),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      leading ??
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(icon, color: Colors.white, size: 28),
                          ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (pillLabel != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: pillColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: pillColor.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: pillColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            pillLabel!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (stats.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        for (var i = 0; i < stats.length; i++) ...[
                          if (i > 0)
                            Container(
                              width: 1,
                              height: 34,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          Expanded(child: stats[i]),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chiffre clé d'un [HeroHeader] : grande valeur + libellé.
class HeroStat extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;

  const HeroStat({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
