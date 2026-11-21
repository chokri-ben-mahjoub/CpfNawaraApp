import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/stock_repository.dart';
import '../../../core/l10n/app_strings.dart';
import 'stock_screen.dart' show exportStock;
import 'stock_table_screen.dart';

/// Page dédiée au suivi mensuel du stock (comme le classeur de suivi du
/// laboratoire), séparée de la gestion courante des articles (voir
/// `StockScreen`) pour un accès direct depuis le menu.
class StockMonthlyScreen extends ConsumerWidget {
  const StockMonthlyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final stock = ref.watch(stockControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s('stockMonthlyTitle')),
        actions: [
          if (stock.items.isNotEmpty)
            IconButton(
              tooltip: s('stockExportTooltip'),
              icon: const Icon(Icons.download_outlined),
              onPressed: () => exportStock(ref, context),
            ),
        ],
      ),
      body: !stock.ready
          ? const Center(child: CircularProgressIndicator())
          : stock.items.isEmpty
          ? Center(child: Text(s('stockEmpty')))
          : const SingleChildScrollView(padding: EdgeInsets.all(16), child: StockAnnualTable()),
    );
  }
}
