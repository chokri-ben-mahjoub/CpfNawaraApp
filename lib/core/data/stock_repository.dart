import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_strings.dart';
import '../models/stock_item.dart';
import '../notifications/stock_notification_service.dart';
import 'local_database.dart';

/// État courant du stock (articles + historique des mouvements), reflet de
/// la base locale (voir `local_database.dart`).
class StockState {
  final List<StockItem> items;
  final List<StockMovement> movements;

  /// Faux tant que la base locale n'a pas encore été lue.
  final bool ready;

  const StockState({required this.items, required this.movements, this.ready = true});

  static const empty = StockState(items: [], movements: [], ready: false);

  /// Consommation de l'année [year] pour l'article [itemId] : somme des
  /// sorties (mouvements négatifs) enregistrées cette année-là.
  double consumptionOf(String itemId, int year) {
    var total = 0.0;
    for (final m in movements) {
      if (m.itemId == itemId && m.delta < 0 && m.dateTime.year == year) total -= m.delta;
    }
    return total;
  }

  /// Prévision de rupture de [item] (voir [stockForecast]).
  StockForecast forecastOf(StockItem item, {DateTime? now}) => stockForecast(item, movements, now: now);

  /// Articles dont la rupture est prévue sous [days] jours (pas encore en
  /// rupture), du plus urgent au moins urgent.
  List<(StockItem, StockForecast)> watchList({int days = 30, DateTime? now}) {
    final out = <(StockItem, StockForecast)>[];
    for (final item in items) {
      if (item.isOut) continue;
      final f = forecastOf(item, now: now);
      if (f.hasRate && f.within(days)) out.add((item, f));
    }
    out.sort((a, b) => a.$2.daysLeft!.compareTo(b.$2.daysLeft!));
    return out;
  }

  /// Articles à leur seuil d'alerte ou en dessous, triés du plus critique
  /// (rupture) au moins critique.
  List<StockItem> get lowStockItems {
    final low = items.where((i) => i.isLow).toList()
      ..sort((a, b) {
        if (a.isOut != b.isOut) return a.isOut ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return low;
  }
}

/// Libellé affiché pour les articles sans catégorie assignée.
const unassignedStockCategoryLabel = 'Autre';

class StockController extends StateNotifier<StockState> {
  StockController(this._ref) : super(StockState.empty) {
    _load();
  }

  /// Contrôleur pré-rempli, sans lecture de la base locale (tests de rendu) :
  /// `_ref` reste nul, donc [addMovement] ne doit pas y être appelé (les
  /// tests de rendu ne déclenchent pas de mouvement).
  @visibleForTesting
  StockController.seeded(super.initial) : _ref = null {
    _loaded.complete();
  }

  final Ref? _ref;
  static const _uuid = Uuid();

  final _loaded = Completer<void>();

  /// Terminé après la première lecture de la base.
  Future<void> get loaded => _loaded.future;

  /// Relit toute la base (ex: après la restauration d'une sauvegarde).
  Future<void> reload() => _load();

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final items = (await db.query('stock_items')).map(_itemFromRow).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final movements = (await db.query('stock_movements')).map(_movementFromRow).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    state = StockState(items: items, movements: movements);
    if (!_loaded.isCompleted) _loaded.complete();
  }

  StockItem? findItem(String id) {
    for (final i in state.items) {
      if (i.id == id) return i;
    }
    return null;
  }

  List<StockMovement> movementsForItem(String itemId) =>
      state.movements.where((m) => m.itemId == itemId).toList()..sort((a, b) => b.dateTime.compareTo(a.dateTime));

  Future<void> _afterWrite() async {
    await _load();
    LocalDatabase.instance.notifyChange();
  }

  /// Crée un nouvel article (quantité initiale saisie à la création, ensuite
  /// uniquement modifiable via des mouvements pour garder un historique).
  Future<void> addItem({
    required String name,
    required String unit,
    required double quantity,
    required double threshold,
    String category = '',
    String? notes,
    String reference = '',
    String mmn = '',
    double? prevConsumption,
    double pendingOrder = 0,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.insert(
      'stock_items',
      LocalDatabase.stamp({
        'id': _uuid.v4(),
        'name': name,
        'unit': unit,
        'quantity': quantity,
        'threshold': threshold,
        'category': category,
        'notes': notes,
        'reference': reference,
        'mmn': mmn,
        'prev_consumption': prevConsumption,
        'pending_order': pendingOrder,
      }),
    );
    await _afterWrite();
  }

  /// Modifie les informations d'un article (pas la quantité, voir
  /// [addMovement]).
  Future<void> updateItem(StockItem item) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'stock_items',
      LocalDatabase.stamp({
        'name': item.name,
        'unit': item.unit,
        'threshold': item.threshold,
        'category': item.category,
        'notes': item.notes,
        'reference': item.reference,
        'mmn': item.mmn,
        'prev_consumption': item.prevConsumption,
        'pending_order': item.pendingOrder,
      }),
      where: 'id = ?',
      whereArgs: [item.id],
    );
    await _afterWrite();
  }

  /// Supprime un article et tout son historique de mouvements.
  Future<void> deleteItem(String itemId) async {
    final db = await LocalDatabase.instance.database;
    final label = state.items.where((i) => i.id == itemId).firstOrNull?.name ?? itemId;
    await db.transaction((txn) async {
      final rows = await txn.query('stock_movements', columns: ['id'], where: 'item_id = ?', whereArgs: [itemId]);
      for (final row in rows) {
        await LocalDatabase.recordDeletion(txn, 'stock_movements', row['id'] as String);
      }
      await txn.delete('stock_movements', where: 'item_id = ?', whereArgs: [itemId]);
      await LocalDatabase.recordDeletion(txn, 'stock_items', itemId, label: label);
      await txn.delete('stock_items', where: 'id = ?', whereArgs: [itemId]);
    });
    await _afterWrite();
  }

  /// Enregistre un mouvement (entrée si [delta] > 0, sortie sinon) et met à
  /// jour la quantité de l'article en conséquence (jamais négative). Déclenche
  /// une alerte locale si l'article passe à son seuil ou en dessous.
  Future<void> addMovement({
    required String itemId,
    required double delta,
    String? reason,
    String? wellId,
    required String operatorName,
  }) async {
    final item = findItem(itemId);
    if (item == null) return;
    final wasLow = item.isLow;
    final newQuantity = (item.quantity + delta).clamp(0, double.infinity).toDouble();

    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.insert(
        'stock_movements',
        LocalDatabase.stamp({
          'id': _uuid.v4(),
          'item_id': itemId,
          'delta': delta,
          'reason': reason,
          'well_id': wellId,
          'operator_name': operatorName,
          'recorded_at': DateTime.now().toIso8601String(),
        }),
      );
      await txn.update(
        'stock_items',
        LocalDatabase.stamp({'quantity': newQuantity}),
        where: 'id = ?',
        whereArgs: [itemId],
      );
    });
    await _afterWrite();

    final isLowNow = newQuantity <= item.threshold;
    if (!wasLow && isLowNow && _ref != null) {
      final locale = _ref.read(localeProvider);
      String s(String key) => tr(locale, key);
      String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
      await StockNotificationService.notifyLowStock(
        itemId: item.id,
        channelName: s('stockAlertChannelName'),
        title: fill(s('stockAlertTitle'), {'name': item.name}),
        body: fill(s('stockAlertBody'), {'qty': fmt(newQuantity), 'threshold': fmt(item.threshold), 'unit': item.unit}),
      );
    }
  }

  StockItem _itemFromRow(Map<String, Object?> row) => StockItem(
    id: row['id'] as String,
    name: row['name'] as String,
    unit: row['unit'] as String? ?? '',
    quantity: (row['quantity'] as num).toDouble(),
    threshold: (row['threshold'] as num).toDouble(),
    category: row['category'] as String? ?? '',
    notes: row['notes'] as String? ?? '',
    reference: row['reference'] as String? ?? '',
    mmn: row['mmn'] as String? ?? '',
    prevConsumption: (row['prev_consumption'] as num?)?.toDouble(),
    pendingOrder: (row['pending_order'] as num?)?.toDouble() ?? 0,
  );

  StockMovement _movementFromRow(Map<String, Object?> row) => StockMovement(
    id: row['id'] as String,
    itemId: row['item_id'] as String,
    delta: (row['delta'] as num).toDouble(),
    reason: row['reason'] as String?,
    wellId: row['well_id'] as String?,
    operatorName: row['operator_name'] as String? ?? '',
    dateTime: DateTime.parse(row['recorded_at'] as String),
  );
}

final stockControllerProvider = StateNotifierProvider<StockController, StockState>((ref) => StockController(ref));
