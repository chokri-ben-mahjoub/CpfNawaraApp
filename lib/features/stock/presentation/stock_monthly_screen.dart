import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/stock_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../admin/presentation/widgets/admin_widgets.dart';
import 'stock_screen.dart' show exportStock;
import 'stock_table_screen.dart';
import 'widgets/stock_item_form_sheet.dart';

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
    final role = ref.watch(currentRoleProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s('stockMonthlyTitle')),
        actions: [
          if (stock.items.isNotEmpty)
            IconButton(
              tooltip: s('stockExportTooltip'),
              icon: const Icon(Icons.download_outlined),
              onPressed: () => exportStock(ref, context, monthOnly: true),
            ),
        ],
      ),
      floatingActionButton: role.canManageOps
          ? FloatingActionButton.extended(
              onPressed: () => showAdminSheet<void>(context, builder: (_) => const StockItemFormSheet()),
              icon: const Icon(Icons.add),
              label: Text(s('stockAddItem')),
            )
          : null,
      body: !stock.ready
          ? const Center(child: CircularProgressIndicator())
          : stock.items.isEmpty
          ? Center(child: Text(s('stockEmpty')))
          : const SingleChildScrollView(padding: EdgeInsets.all(16), child: StockAnnualTable()),
    );
  }
}
