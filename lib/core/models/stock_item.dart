/// Catégories suggérées à la création d'un article (liste pas fermée : le
/// champ reste un texte libre, ces valeurs ne sont que des raccourcis).
const stockCategorySuggestions = ['Chimie', 'Pièces', 'EPI', 'Consommables', 'Carburant', 'Autre'];

/// Unités suggérées (idem, texte libre).
const stockUnitSuggestions = ['u', 'kg', 'L', 'm', 'sac', 'bidon'];

/// Article suivi en stock (produit chimique, pièce détachée, consommable...)
/// utilisé sur les puits ou l'usine. La quantité est dénormalisée sur
/// l'article (plutôt que recalculée depuis l'historique des mouvements) pour
/// un affichage instantané de la liste — voir `stock_repository.dart` pour
/// la tenue à jour de ce champ à chaque mouvement.
class StockItem {
  final String id;
  final String name;
  final String unit;
  final double quantity;

  /// Seuil d'alerte : une notification est déclenchée quand la quantité
  /// passe à son niveau ou en dessous (voir `StockController.addMovement`).
  final double threshold;

  /// Vide = non classé (affiché dans un groupe "Autre" dans la liste).
  final String category;
  /// Observations (ex: "PO 4510135789 en attente de livraison").
  final String notes;

  /// Référence produit (ex: "ROCLEAN 810") et code MMN.
  final String reference;
  final String mmn;

  /// Consommation de l'année précédente ; nul = nouveau produit.
  final double? prevConsumption;

  /// Quantité commandée, en attente de livraison.
  final double pendingOrder;

  const StockItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.threshold,
    this.category = '',
    this.notes = '',
    this.reference = '',
    this.mmn = '',
    this.prevConsumption,
    this.pendingOrder = 0,
  });

  bool get isOut => quantity <= 0;
  bool get isLow => quantity <= threshold;

  StockItem copyWith({
    String? name,
    String? unit,
    double? quantity,
    double? threshold,
    String? category,
    String? notes,
    String? reference,
    String? mmn,
    double? prevConsumption,
    bool clearPrevConsumption = false,
    double? pendingOrder,
  }) => StockItem(
    id: id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    threshold: threshold ?? this.threshold,
    category: category ?? this.category,
    notes: notes ?? this.notes,
    reference: reference ?? this.reference,
    mmn: mmn ?? this.mmn,
    prevConsumption: clearPrevConsumption ? null : (prevConsumption ?? this.prevConsumption),
    pendingOrder: pendingOrder ?? this.pendingOrder,
  );

  /// Besoin annuel : la consommation de l'année en cours [consumption], ou
  /// celle de l'année précédente si elle est plus élevée (en début d'année,
  /// ou pour un produit encore peu utilisé, les sorties de l'année ne
  /// reflètent pas encore le besoin réel). Un nouveau produit (sans
  /// historique) n'a que sa consommation de l'année.
  double annualNeed(double consumption) {
    final prev = prevConsumption ?? 0;
    return consumption > prev ? consumption : prev;
  }

  /// Quantité à commander : besoin annuel moins le stock disponible et la
  /// commande déjà en route (jamais négative).
  double toOrder(double consumption) {
    final v = annualNeed(consumption) - quantity - pendingOrder;
    return v > 0 ? v : 0;
  }
}

/// Mouvement de stock : entrée (delta positif, ex: réapprovisionnement),
/// sortie (delta négatif, ex: consommation sur un puits) ou correction
/// d'inventaire (delta positif ou négatif).
class StockMovement {
  final String id;
  final String itemId;

  /// Changement appliqué à la quantité de l'article (positif = entrée,
  /// négatif = sortie).
  final double delta;
  final String? reason;

  /// Puits ayant consommé l'article, le cas échéant (sortie liée à une
  /// intervention sur un puits précis).
  final String? wellId;
  final String operatorName;
  final DateTime dateTime;

  const StockMovement({
    required this.id,
    required this.itemId,
    required this.delta,
    this.reason,
    this.wellId,
    required this.operatorName,
    required this.dateTime,
  });

  bool get isEntry => delta > 0;
}

/// Prévision de rupture d'un article d'après sa consommation récente.
class StockForecast {
  /// Consommation moyenne par jour (unité de l'article) ; 0 = aucune sortie
  /// récente.
  final double dailyRate;

  /// Jours restants avant rupture ; nul = impossible à estimer (pas de
  /// consommation récente).
  final int? daysLeft;

  /// Date estimée de rupture.
  final DateTime? runOutDate;

  const StockForecast({required this.dailyRate, required this.daysLeft, required this.runOutDate});

  bool get hasRate => dailyRate > 0;

  /// Rupture prévue dans moins de [days] jours (ou déjà en rupture).
  bool within(int days) => daysLeft != null && daysLeft! <= days;
}

/// Prévision de rupture : consommation moyenne des [windowDays] derniers
/// jours (au moins 7 jours de recul, pour ne pas extrapoler une seule sortie)
/// appliquée à la quantité actuelle.
StockForecast stockForecast(
  StockItem item,
  Iterable<StockMovement> movements, {
  DateTime? now,
  int windowDays = 30,
}) {
  final today = now ?? DateTime.now();
  final cutoff = today.subtract(Duration(days: windowDays));
  var total = 0.0;
  DateTime? first;
  for (final m in movements) {
    if (m.itemId != item.id || m.delta >= 0 || m.dateTime.isBefore(cutoff) || m.dateTime.isAfter(today)) continue;
    total -= m.delta;
    if (first == null || m.dateTime.isBefore(first)) first = m.dateTime;
  }
  if (first == null || total <= 0) {
    return StockForecast(dailyRate: 0, daysLeft: item.quantity <= 0 ? 0 : null, runOutDate: item.quantity <= 0 ? today : null);
  }
  final span = today.difference(first).inDays.clamp(7, windowDays);
  final rate = total / span;
  final days = item.quantity <= 0 ? 0 : (item.quantity / rate).floor();
  return StockForecast(dailyRate: rate, daysLeft: days, runOutDate: today.add(Duration(days: days)));
}
