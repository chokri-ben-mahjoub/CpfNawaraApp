import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'responsive.dart';

/// Comportement de défilement de toute l'app :
/// - glisser à la souris, au pavé tactile ou au stylet fait défiler (par
///   défaut seul le toucher le fait : sur PC les listes ne bougeaient qu'à la
///   molette) ;
/// - sur grand écran, la barre de défilement verticale reste visible et plus
///   épaisse (par défaut elle disparaît après une seconde et se voit à peine).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    final controller = details.controller;
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    if (wide && controller != null && details.direction == AxisDirection.down) {
      return Scrollbar(controller: controller, thumbVisibility: true, interactive: true, child: child);
    }
    return super.buildScrollbar(context, child, details);
  }
}
