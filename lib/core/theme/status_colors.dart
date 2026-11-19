import 'package:flutter/material.dart';

/// Couleurs d'état de toute l'app : une couleur veut toujours dire la même
/// chose (pastilles, graphiques, alertes, tableaux).
///
/// - [statusOk] : dans la norme, en service, terminé ;
/// - [statusWarn] : à surveiller, en attente, bientôt hors seuil ;
/// - [statusBad] : hors seuil, en défaut, urgent.
///
/// Pour l'inactif ou le neutre, utiliser `colorScheme.outline`.
const statusOk = Color(0xFF2E9E5B);
const statusWarn = Color(0xFFE08A1E);
const statusBad = Color(0xFFD32F2F);
