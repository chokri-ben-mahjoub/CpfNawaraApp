import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/stock_repository.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/stock_item.dart';
import '../../../core/models/user_role.dart';
import '../../../core/widgets/responsive.dart';
import '../../admin/presentation/widgets/admin_widgets.dart';
import 'stock_screen.dart' show stockStatusColor, stockStatusLabel;
import 'widgets/stock_item_form_sheet.dart';
import 'widgets/stock_movement_sheet.dart';

/// Fiche d'un article : quantité actuelle, mouvements rapides (entrée/
/// sortie) et historique — voir `stock_repository.dart`.
class StockItemDetailScreen extends ConsumerWidget {
  final String itemId;
  const StockItemDetailScreen({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final role = ref.watch(currentRoleProvider);
    final stock = ref.watch(stockControllerProvider);
    final item = stock.items.where((i) => i.id == itemId).firstOrNull;
    String s(String key) => tr(locale, key);

    if (item == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(s('stockItemGone'))));
    }

    final movements = ref.read(stockControllerProvider.notifier).movementsForItem(itemId);
    final statusColor = stockStatusColor(item, scheme);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          if (role.canEnterData)
            IconButton(
              tooltip: s('stockEditItem'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showAdminSheet<void>(context, builder: (_) => StockItemFormSheet(existing: item)),
            ),
          if (role.canConfigure)
            IconButton(
              tooltip: s('stockDeleteItem'),
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: () => _delete(context, ref, item, s),
            ),
        ],
      ),
      body: ListView(
        padding: pagePadding(context, top: 12, bottom: 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.category.isEmpty ? s('stockUncategorized') : item.category,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        stockStatusLabel(item, s),
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_qtyText(item.quantity)} ${item.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 32),
                ),
                const SizedBox(height: 4),
                Text(
                  '${s('stockThresholdLabel')} : ${_qtyText(item.threshold)} ${item.unit}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
                if (item.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(item.notes, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                ],
              ],
            ),
          ),
          if (role.canEnterData) ...[
            const SizedBox(height: 16),
            ResponsiveWrapGrid(
              minItemWidth: 200,
              spacing: 12,
              children: [
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => showStockMovementSheet(context, item: item, isEntry: true),
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(s('stockEntry'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                  ),
                ),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => showStockMovementSheet(context, item: item, isEntry: false),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: Text(s('stockExit'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          AdminSectionTitle(s('stockHistory')),
          if (movements.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(s('stockHistoryEmpty'), style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else
            for (final m in movements)
              _MovementTile(movement: m, dateFormat: dateFormat, s: s),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, StockItem item, String Function(String) s) async {
    final confirmed = await confirmDanger(
      context,
      title: s('stockDeleteConfirmTitle'),
      body: s('stockDeleteConfirmBody'),
      confirm: s('stockDeleteItem'),
      cancel: s('cancel'),
    );
    if (!confirmed) return;
    await ref.read(stockControllerProvider.notifier).deleteItem(item.id);
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('stockItemDeleted'))));
    }
  }
}

String _qtyText(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

class _MovementTile extends ConsumerWidget {
  final StockMovement movement;
  final DateFormat dateFormat;
  final String Function(String) s;
  const _MovementTile({required this.movement, required this.dateFormat, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final color = movement.isEntry ? Colors.green.shade600 : scheme.error;
    final well = movement.wellId == null ? null : ref.watch(wellsControllerProvider.notifier).findWell(movement.wellId!);
    final subtitleParts = <String>[
      dateFormat.format(movement.dateTime),
      if (movement.operatorName.trim().isNotEmpty) movement.operatorName,
      if (well != null) well.name,
      if ((movement.reason ?? '').trim().isNotEmpty) movement.reason!.trim(),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: IconBadge(movement.isEntry ? Icons.add_rounded : Icons.remove_rounded, color: color),
        title: Text(
          '${movement.isEntry ? '+' : ''}${_qtyText(movement.delta)}',
          style: TextStyle(fontWeight: FontWeight.w800, color: color),
        ),
        subtitle: Text(subtitleParts.join(' · '), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
      ),
    );
  }
}
