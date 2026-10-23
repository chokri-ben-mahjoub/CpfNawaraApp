import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/stock_repository.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/models/stock_item.dart';
import '../../../admin/presentation/widgets/admin_widgets.dart';
import '../../../stock/presentation/stock_screen.dart' show stockForecastText, stockStatusColor;

/// Cloche de notifications (AppBar) : articles de stock en alerte. Tant
/// qu'il y en a au moins un, une pastille rouge clignotante attire l'œil ;
/// le tap ouvre la liste, chaque ligne mène directement à la fiche de
/// l'article concerné (voir `stock_repository.dart` pour la détection du
/// seuil bas).
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void initState() {
    super.initState();
    final stock = ref.read(stockControllerProvider);
    if (stock.lowStockItems.isNotEmpty || stock.soonList().isNotEmpty) _blinkThenHold();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Clignote un court instant pour attirer l'attention à l'apparition d'une
  /// alerte, puis reste allumée (pastille fixe) plutôt que de clignoter sans
  /// fin.
  void _blinkThenHold() {
    _pulse
      ..stop()
      ..repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 2700), () {
      if (mounted) _pulse.stop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final items = ref.watch(stockControllerProvider.select((s) => s.lowStockItems));
    final soon = ref.watch(stockControllerProvider.select((s) => s.soonList()));
    final total = items.length + soon.length;
    ref.listen(stockControllerProvider.select((s) => s.lowStockItems.length + s.soonList().length), (previous, next) {
      if (next > 0 && (previous == null || previous == 0)) _blinkThenHold();
    });
    String s(String key) => tr(locale, key);
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: s('notificationsTitle'),
      onPressed: () => _open(context, items, soon, s),
      icon: total == 0
          ? const Icon(Icons.notifications_outlined)
          : AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Badge(
                label: Text('$total'),
                backgroundColor: Color.lerp(scheme.error, scheme.error.withValues(alpha: 0.45), _pulse.value),
                child: child,
              ),
              child: const Icon(Icons.notifications_active_rounded),
            ),
    );
  }

  void _open(
    BuildContext context,
    List<StockItem> items,
    List<(StockItem, StockForecast)> soon,
    String Function(String) s,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    s('notificationsTitle'),
                    style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(s('notificationsStockHint'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 12),
                  if (items.isEmpty && soon.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(s('notificationsEmpty'), style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length + soon.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (itemContext, i) {
                          if (i >= items.length) {
                            final (soonItem, f) = soon[i - items.length];
                            const orange = Color(0xFFE08A1E);
                            return Material(
                              color: orange.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              child: ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                leading: const IconBadge(Icons.trending_down_rounded, color: orange),
                                title: Text(soonItem.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text('${s('notificationsSoonSection')}\n${stockForecastText(f, s)}'),
                                isThreeLine: true,
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  context.push('/stock/${soonItem.id}');
                                },
                              ),
                            );
                          }
                          final item = items[i];
                          final color = stockStatusColor(item, scheme);
                          return Material(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              leading: IconBadge(Icons.warning_amber_rounded, color: color),
                              title: Text(
                                fill(s('stockAlertTitle'), {'name': item.name}),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                fill(s('stockAlertBody'), {
                                  'qty': _qty(item.quantity),
                                  'unit': item.unit,
                                  'threshold': _qty(item.threshold),
                                }),
                              ),
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                context.push('/stock/${item.id}');
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  if (items.isNotEmpty || soon.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        context.push('/stock');
                      },
                      child: Text(s('seeAll')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _qty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
