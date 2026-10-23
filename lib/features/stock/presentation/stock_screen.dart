import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/stock_repository.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/stock_item.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/status_style.dart';
import '../../../core/widgets/hero_header.dart';
import '../../../core/widgets/responsive.dart';
import '../../admin/presentation/widgets/admin_widgets.dart';
import 'stock_table_screen.dart';
import 'widgets/stock_item_form_sheet.dart';

/// Une ligne du tableau de suivi annuel (reproduit le classeur de suivi des
/// produits : consommations, stock disponible, commande, quantité à commander).
class StockTableRow {
  final StockItem item;
  final double consumption;
  const StockTableRow(this.item, this.consumption);

  double get toOrder => item.toOrder(consumption);
}

List<StockTableRow> stockTableRows(StockState stock, int year) {
  final items = [...stock.items]
    ..sort((a, b) {
      final byCategory = a.category.compareTo(b.category);
      return byCategory != 0 ? byCategory : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return [for (final i in items) StockTableRow(i, stock.consumptionOf(i.id, year))];
}

/// En-têtes du tableau de suivi annuel pour l'année [year].
List<String> stockTableHeaders(String Function(String) s, int year) => [
  s('stockColDescription'),
  s('stockColReference'),
  s('stockMmnLabel'),
  fill(s('stockColPrev'), {'y': '${year - 1}'}),
  fill(s('stockColCurrent'), {'y': '$year'}),
  fill(s('stockColAvailable'), {'y': '$year'}),
  fill(s('stockColPending'), {'y': '$year'}),
  s('stockColToOrder'),
  s('stockNotesLabel'),
];

/// Exporte le tableau de suivi annuel du stock (PDF / Excel / CSV).
Future<void> exportStock(WidgetRef ref, BuildContext context) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final year = DateTime.now().year;
  final rows = stockTableRows(ref.read(stockControllerProvider), year);

  await runExport(
    context: context,
    locale: locale,
    baseName: 'stock_$year',
    tables: [
      ExportTable(
        name: s('stockTableTitle'),
        headers: stockTableHeaders(s, year),
        rows: [
          for (final r in rows)
            [
              r.item.name,
              r.item.reference,
              r.item.mmn,
              r.item.prevConsumption ?? s('stockNewProduct'),
              r.consumption,
              r.item.quantity,
              r.item.pendingOrder,
              r.toOrder,
              r.item.notes,
            ],
        ],
      ),
    ],
  );
}

Color stockStatusColor(StockItem item, ColorScheme scheme) {
  if (item.isOut) return scheme.error;
  if (item.isLow) return const Color(0xFFE08A1E);
  return Colors.green.shade600;
}

String stockStatusLabel(StockItem item, String Function(String) s) {
  if (item.isOut) return s('stockStatusOut');
  if (item.isLow) return s('stockStatusLow');
  return s('stockStatusOk');
}

String _qtyText(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// Gestion de stock : articles (chimie, pièces, consommables...) consommés
/// sur les puits, avec alerte quand la quantité passe sous le seuil choisi
/// (voir `stock_repository.dart`).
class StockScreen extends ConsumerWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final stock = ref.watch(stockControllerProvider);
    String s(String key) => tr(locale, key);

    return Scaffold(
      appBar: AppBar(
        title: Text(s('stockTitle')),
        actions: [
          if (stock.items.isNotEmpty)
            IconButton(
              tooltip: s('stockExportTooltip'),
              icon: const Icon(Icons.download_outlined),
              onPressed: () => exportStock(ref, context),
            ),
        ],
      ),
      floatingActionButton: role.canEnterData
          ? FloatingActionButton.extended(
              onPressed: () => showAdminSheet<void>(context, builder: (_) => const StockItemFormSheet()),
              icon: const Icon(Icons.add),
              label: Text(s('stockAddItem')),
            )
          : null,
      body: stock.items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 56, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      s('stockEmpty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: pagePadding(context, top: 12, bottom: 130),
              children: [
                _SummaryRow(items: stock.items, s: s),
                if (stock.lowStockItems.isNotEmpty) ...[
                  AdminSectionTitle(s('stockLowSection')),
                  AdminTable<StockItem>(
                    items: stock.lowStockItems,
                    onTap: (item) => context.push('/stock/${item.id}'),
                    columns: [
                      AdminColumn(s('stockNameLabel'), (i) => Text(i.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                      AdminColumn(s('stockCategoryLabel'), (i) => Text(i.category.isEmpty ? '—' : i.category)),
                      AdminColumn(
                        s('stockQuantityLabel'),
                        (i) => Text('${_qtyText(i.quantity)} ${i.unit}'),
                        numeric: true,
                      ),
                      AdminColumn(
                        s('stockStatusLabel'),
                        (i) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StatusPill(item: i),
                            const SizedBox(width: 8),
                            Icon(Icons.visibility_outlined, size: 18, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ],
                    card: (context, i) => AdminCard(
                      leading: IconBadge(Icons.warning_amber_rounded, color: stockStatusColor(i, scheme)),
                      title: i.name,
                      subtitle: '${_qtyText(i.quantity)} ${i.unit} · ${s('stockThresholdLabel')} ${_qtyText(i.threshold)} ${i.unit}',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StatusPill(item: i),
                          const SizedBox(width: 8),
                          Icon(Icons.visibility_outlined, size: 20, color: scheme.onSurfaceVariant),
                        ],
                      ),
                      onTap: () => context.push('/stock/${i.id}'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                AdminSectionTitle(s('stockAnnualSection')),
                const StockAnnualTable(),
              ],
            ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final List<StockItem> items;
  final String Function(String) s;
  const _SummaryRow({required this.items, required this.s});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final low = items.where((i) => i.isLow).length;
    final out = items.where((i) => i.isOut).length;
    final categories = items.map((i) => i.category.trim()).where((c) => c.isNotEmpty).toSet().length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: HeroHeader(
        icon: Icons.inventory_2_outlined,
        title: s('stockTitle'),
        subtitle: '${items.length} ${s('stockTotalItems').toLowerCase()}',
        pillLabel: low > 0 ? s('stockLowSection') : s('stockHeroAllGood'),
        pillColor: low > 0 ? AppStatus.todo.color(scheme) : AppStatus.ok.color(scheme),
        stats: [
          HeroStat(value: '${items.length}', label: s('stockTotalItems')),
          HeroStat(value: '$low', label: s('stockLowSection'), valueColor: low > 0 ? const Color(0xFFFFB74D) : null),
          HeroStat(value: '$out', label: s('stockHeroOut'), valueColor: out > 0 ? const Color(0xFFFF8A80) : null),
          HeroStat(value: '$categories', label: s('stockHeroCategories')),
        ],
      ),
    );
  }
}

class _StatusPill extends ConsumerWidget {
  final StockItem item;
  const _StatusPill({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String s(String key) => tr(ref.watch(localeProvider), key);
    final scheme = Theme.of(context).colorScheme;
    final color = stockStatusColor(item, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(100)),
      child: Text(
        stockStatusLabel(item, s),
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5),
      ),
    );
  }
}
