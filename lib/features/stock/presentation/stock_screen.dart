import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/stock_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/stock_item.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../admin/presentation/widgets/admin_widgets.dart';
import 'widgets/stock_item_form_sheet.dart';

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

    final byCategory = <String, List<StockItem>>{};
    for (final item in stock.items) {
      final key = item.category.trim().isEmpty ? unassignedStockCategoryLabel : item.category.trim();
      byCategory.putIfAbsent(key, () => []).add(item);
    }
    final categories = byCategory.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: Text(s('stockTitle'))),
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
                _SummaryRow(total: stock.items.length, low: stock.lowStockItems.length, s: s),
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
                      AdminColumn(s('stockStatusLabel'), (i) => _StatusPill(item: i)),
                    ],
                    card: (context, i) => AdminCard(
                      leading: IconBadge(Icons.warning_amber_rounded, color: stockStatusColor(i, scheme)),
                      title: i.name,
                      subtitle: '${_qtyText(i.quantity)} ${i.unit} · ${s('stockThresholdLabel')} ${_qtyText(i.threshold)} ${i.unit}',
                      trailing: _StatusPill(item: i),
                      onTap: () => context.push('/stock/${i.id}'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                for (final category in categories) ...[
                  AdminSectionTitle(category == unassignedStockCategoryLabel ? s('stockUncategorized') : category),
                  AdminTable<StockItem>(
                    items: byCategory[category]!..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
                    onTap: (item) => context.push('/stock/${item.id}'),
                    columns: [
                      AdminColumn(s('stockNameLabel'), (i) => Text(i.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                      AdminColumn(
                        s('stockQuantityLabel'),
                        (i) => Text('${_qtyText(i.quantity)} ${i.unit}'),
                        numeric: true,
                      ),
                      AdminColumn(s('stockStatusLabel'), (i) => _StatusPill(item: i)),
                    ],
                    card: (context, i) => AdminCard(
                      leading: IconBadge(Icons.inventory_2_outlined, color: stockStatusColor(i, scheme)),
                      title: i.name,
                      subtitle: '${_qtyText(i.quantity)} ${i.unit}',
                      trailing: _StatusPill(item: i),
                      onTap: () => context.push('/stock/${i.id}'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final int total;
  final int low;
  final String Function(String) s;
  const _SummaryRow({required this.total, required this.low, required this.s});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ResponsiveWrapGrid(
        minItemWidth: 180,
        spacing: 12,
        children: [
          _StatCard(icon: Icons.inventory_2_outlined, color: accentColor, label: s('stockTotalItems'), value: '$total'),
          _StatCard(
            icon: Icons.warning_amber_rounded,
            color: low > 0 ? const Color(0xFFE08A1E) : Colors.green.shade600,
            label: s('stockLowSection'),
            value: '$low',
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _StatCard({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          IconBadge(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
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
