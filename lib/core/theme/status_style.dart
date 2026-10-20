import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Charte de statut unique de l'app : même couleur et même icône pour un état
/// donné, sur le tableau de bord, les alertes, l'usine et les écrans de détail.
///
/// vert = conforme / fait · orange = à faire · rouge = en retard ou hors seuil
/// · gris = non analysé.
enum AppStatus {
  ok(Icons.check_circle_outline),
  todo(Icons.hourglass_empty_rounded),
  late(Icons.warning_amber_rounded),
  out(Icons.error_outline),
  none(Icons.remove_circle_outline);

  final IconData icon;
  const AppStatus(this.icon);

  Color color(ColorScheme scheme) => switch (this) {
    AppStatus.ok => const Color(0xFF2E7D32),
    AppStatus.todo => accentColor,
    AppStatus.late || AppStatus.out => scheme.error,
    AppStatus.none => scheme.outline,
  };
}
