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
  final String notes;

  const StockItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.threshold,
    this.category = '',
    this.notes = '',
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
  }) => StockItem(
    id: id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    threshold: threshold ?? this.threshold,
    category: category ?? this.category,
    notes: notes ?? this.notes,
  );
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
