import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/data/stock_repository.dart';
import 'package:puitstrack/core/models/stock_item.dart';

void main() {
  StockMovement exit(String item, double qty, DateTime at) =>
      StockMovement(id: '$item$qty${at.millisecondsSinceEpoch}', itemId: item, delta: -qty, operatorName: 'op', dateTime: at);
  StockMovement entry(String item, double qty, DateTime at) =>
      StockMovement(id: 'e$item$qty${at.millisecondsSinceEpoch}', itemId: item, delta: qty, operatorName: 'op', dateTime: at);

  test('consommation de l\'année : seules les sorties de cette année comptent', () {
    final stock = StockState(
      items: const [],
      movements: [
        exit('a', 5, DateTime(2026, 3, 1)),
        exit('a', 2, DateTime(2026, 9, 1)),
        exit('a', 40, DateTime(2025, 12, 31)), // année précédente
        entry('a', 100, DateTime(2026, 4, 1)), // une entrée n'est pas de la consommation
        exit('b', 9, DateTime(2026, 5, 1)), // autre article
      ],
    );
    expect(stock.consumptionOf('a', 2026), 7);
    expect(stock.consumptionOf('a', 2025), 40);
    expect(stock.consumptionOf('b', 2026), 9);
    expect(stock.consumptionOf('c', 2026), 0);
  });

  test('à commander : besoin annuel − stock − commande en attente', () {
    const item = StockItem(id: 'a', name: 'A', unit: 'L', quantity: 15, threshold: 5, prevConsumption: 25, pendingOrder: 4);
    // Début d'année : 0 sorties, mais 25 l'an dernier -> 25 − 15 − 4 = 6.
    expect(item.toOrder(0), 6);
    // Consommation de l'année plus forte que l'an dernier : elle prime.
    expect(item.toOrder(40), 21);
    // Stock + commande couvrent déjà le besoin : jamais négatif.
    expect(item.copyWith(quantity: 30).toOrder(10), 0);
  });

  test('nouveau produit (sans historique) : seule la consommation de l\'année compte', () {
    const fresh = StockItem(id: 'n', name: 'Neuf', unit: 'u', quantity: 10, threshold: 2);
    expect(fresh.prevConsumption, isNull);
    expect(fresh.toOrder(0), 0);
    expect(fresh.toOrder(8), 0); // 8 − 10 < 0
    expect(fresh.toOrder(14), 4);
    // Rupture totale sans aucune sortie enregistrée : rien à calculer.
    expect(fresh.copyWith(quantity: 0).toOrder(0), 0);
  });
}
