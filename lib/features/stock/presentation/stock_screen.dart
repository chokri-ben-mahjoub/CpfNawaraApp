import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/stock_repository.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/stock_item.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/status_style.dart';
import '../../../core/widgets/hero_header.dart';
import '../../../core/widgets/modern_widgets.dart';
import '../../../core/widgets/responsive.dart';
import '../../admin/presentation/widgets/admin_widgets.dart';
import 'stock_table_screen.dart';
import 'widgets/stock_item_form_sheet.dart';

/// Une ligne du tableau de suivi annuel (reproduit le classeur de suivi des
/// produits : consommations, stock disponible, commande, quantité à commander).
class StockTableRow {
  final StockItem item;
  final double consumption;
  final StockForecast forecast;
  const StockTableRow(this.item, this.consumption, this.forecast);

  double get toOrder => item.toOrder(consumption);
}

List<StockTableRow> stockTableRows(StockState stock, int year) {
  final items = [...stock.items]
    ..sort((a, b) {
      final byCategory = a.category.compareTo(b.category);
      return byCategory != 0 ? byCategory : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return [for (final i in items) StockTableRow(i, stock.consumptionOf(i.id, year), stock.forecastOf(i))];
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
  s('stockColRunOut'),
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
              stockForecastText(r.forecast, s),
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

/// Texte court d'une prévision : « dans ~12 j · vers le 04/11/2026 ».
String stockForecastText(StockForecast f, String Function(String) s) {
  if (f.daysLeft == null) return s('stockForecastNone');
  final days = f.daysLeft == 0 ? s('stockForecastToday') : fill(s('stockForecastDays'), {'n': '${f.daysLeft}'});
  final date = fill(s('stockForecastDate'), {'date': DateFormat('dd/MM/yyyy').format(f.runOutDate!)});
  return '$days · $date';
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
                AdminSectionTitle(s('stockLevelsSection')),
                _StockGauges(stock: stock, s: s),
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
                if (stock.watchList().isNotEmpty) ...[
                  AdminSectionTitle(s('stockWatchSection')),
                  for (final (item, f) in stock.watchList())
                    AdminCard(
                      leading: IconBadge(Icons.trending_down_rounded, color: const Color(0xFFE08A1E)),
                      title: item.name,
                      subtitle:
                          '${stockForecastText(f, s)}\n${fill(s('stockForecastRate'), {'rate': _qtyText(f.dailyRate), 'unit': item.unit})}',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE08A1E).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          '${f.daysLeft} j',
                          style: const TextStyle(color: Color(0xFFE08A1E), fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                      onTap: () => context.push('/stock/${item.id}'),
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

/// Une jauge circulaire par article : niveau face au seuil d'alerte (l'anneau
/// est plein à 3 fois le seuil), quantité au centre, jours avant rupture.
class _StockGauges extends StatelessWidget {
  final StockState stock;
  final String Function(String) s;
  const _StockGauges({required this.stock, required this.s});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [...stock.items]
      ..sort((a, b) {
        if (a.isOut != b.isOut) return a.isOut ? -1 : 1;
        if (a.isLow != b.isLow) return a.isLow ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return ResponsiveWrapGrid(
      minItemWidth: 165,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (var i = 0; i < items.length; i++)
          FadeSlideIn(
            index: i,
            child: _GaugeCard(item: items[i], forecast: stock.forecastOf(items[i]), s: s, scheme: scheme),
          ),
      ],
    );
  }
}

class _GaugeCard extends StatelessWidget {
  final StockItem item;
  final StockForecast forecast;
  final String Function(String) s;
  final ColorScheme scheme;
  const _GaugeCard({required this.item, required this.forecast, required this.s, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final color = stockStatusColor(item, scheme);
    final level = item.threshold > 0 ? item.quantity / (item.threshold * 3) : (item.quantity > 0 ? 1.0 : 0.0);
    final soon = forecast.hasRate && forecast.within(30) && !item.isOut;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/stock/${item.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularGauge(
                value: level,
                color: color,
                size: 92,
                strokeWidth: 10,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _qtyText(item.quantity),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: color, height: 1.1),
                    ),
                    if (item.unit.isNotEmpty)
                      Text(item.unit, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.2),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(100)),
                child: Text(
                  soon ? fill(s('stockForecastDays'), {'n': '${forecast.daysLeft}'}) : stockStatusLabel(item, s),
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
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
