import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/models/stock_item.dart';

void main() {
  final now = DateTime(2026, 10, 24, 12);
  StockMovement exit(double qty, int daysAgo) => StockMovement(
    id: 'm$daysAgo$qty',
    itemId: 'a',
    delta: -qty,
    operatorName: 'op',
    dateTime: now.subtract(Duration(days: daysAgo)),
  );
  const item = StockItem(id: 'a', name: 'Test', unit: 'L', quantity: 30, threshold: 5);

  test('consommation moyenne sur 30 jours -> jours restants', () {
    // 60 L sortis sur les 30 derniers jours = 2 L/jour, stock 30 L -> 15 jours.
    final f = stockForecast(item, [exit(30, 30), exit(30, 10)], now: now);
    expect(f.dailyRate, closeTo(2, 0.01));
    expect(f.daysLeft, 15);
    expect(f.runOutDate, now.add(const Duration(days: 15)));
    expect(f.within(30), isTrue);
    expect(f.within(10), isFalse);
  });

  test('une seule sortie récente : recul minimal de 7 jours', () {
    final f = stockForecast(item, [exit(7, 1)], now: now);
    expect(f.dailyRate, closeTo(1, 0.01)); // 7 L / 7 jours
    expect(f.daysLeft, 30);
  });

  test('sorties trop anciennes ou entrées : pas de prévision', () {
    final old = exit(50, 90);
    final entry = StockMovement(id: 'e', itemId: 'a', delta: 20, operatorName: 'op', dateTime: now);
    final f = stockForecast(item, [old, entry], now: now);
    expect(f.hasRate, isFalse);
    expect(f.daysLeft, isNull);
  });

  test('article déjà en rupture : 0 jour', () {
    final f = stockForecast(item.copyWith(quantity: 0), [exit(10, 5)], now: now);
    expect(f.daysLeft, 0);
  });

  test('mouvements d\'un autre article ignorés', () {
    final other = StockMovement(id: 'x', itemId: 'b', delta: -99, operatorName: 'op', dateTime: now);
    expect(stockForecast(item, [other], now: now).hasRate, isFalse);
  });
}
