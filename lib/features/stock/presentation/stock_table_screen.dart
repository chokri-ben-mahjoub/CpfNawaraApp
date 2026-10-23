import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/stock_repository.dart';
import '../../../core/l10n/app_strings.dart';
import 'stock_screen.dart';

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// Tableau de suivi annuel du stock, comme le classeur de suivi des produits :
/// désignation, référence, MMN, consommation N-1, consommation N calculée,
/// stock disponible, commande en attente, quantité à commander, observations.
class StockAnnualTable extends ConsumerWidget {
  const StockAnnualTable({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final stock = ref.watch(stockControllerProvider);
    String s(String key) => tr(locale, key);
    final year = DateTime.now().year;
    final rows = stockTableRows(stock, year);
    final headers = stockTableHeaders(s, year);
    final border = BorderSide(color: scheme.outlineVariant);

    Widget cell(
      String text, {
      bool bold = false,
      TextAlign align = TextAlign.center,
      Color? color,
      double width = 120,
    }) => Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(right: border, bottom: border),
      ),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: color,
        ),
      ),
    );

    // Largeurs de base ; sur un écran assez large (ou presque), elles sont
    // ajustées pour que TOUTES les colonnes tiennent sans défilement.
    const baseWidths = [
      170.0,
      120.0,
      80.0,
      110.0,
      110.0,
      110.0,
      125.0,
      105.0,
      150.0,
      200.0,
    ];
    final baseTotal = baseWidths.fold<double>(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s('stockTableFormula'),
          style: TextStyle(
            fontSize: 12.5,
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth - 1;
            final factor = available >= baseTotal * 0.8
                ? available / baseTotal
                : 1.0;
            final widths = [for (final w in baseWidths) w * factor];
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(top: border, left: border),
                ),
                child: Column(
                  children: [
                    Container(
                      color: scheme.surfaceContainerHighest,
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var c = 0; c < headers.length; c++)
                              cell(headers[c], bold: true, width: widths[c]),
                          ],
                        ),
                      ),
                    ),
                    for (final r in rows)
                      InkWell(
                        onTap: () => context.push('/stock/${r.item.id}'),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cell(r.item.name, bold: true, width: widths[0]),
                              cell(r.item.reference, width: widths[1]),
                              cell(r.item.mmn, width: widths[2]),
                              cell(
                                r.item.prevConsumption == null
                                    ? s('stockNewProduct')
                                    : _num(r.item.prevConsumption!),
                                width: widths[3],
                              ),
                              cell(_num(r.consumption), width: widths[4]),
                              cell(
                                _num(r.item.quantity),
                                bold: true,
                                width: widths[5],
                                color: stockStatusColor(r.item, scheme),
                              ),
                              cell(_num(r.item.pendingOrder), width: widths[6]),
                              cell(
                                _num(r.toOrder),
                                bold: true,
                                width: widths[7],
                                color: r.toOrder > 0 ? scheme.error : null,
                              ),
                              cell(
                                stockForecastText(r.forecast, s),
                                width: widths[8],
                                color:
                                    r.forecast.hasRate && r.forecast.within(30)
                                    ? const Color(0xFFE08A1E)
                                    : null,
                              ),
                              cell(r.item.notes, width: widths[9]),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
