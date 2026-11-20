import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/stock_repository.dart';
import '../../../core/export/export_format_sheet.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/export/stock_monthly_excel.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/stock_item.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_style.dart';
import '../../../core/widgets/hero_header.dart';
import '../../../core/widgets/modern_widgets.dart';
import '../../../core/widgets/responsive.dart';
import '../../admin/presentation/widgets/admin_widgets.dart';
import 'stock_table_screen.dart';
import 'widgets/stock_item_form_sheet.dart';

/// Une ligne du tableau de suivi annuel (reproduit le classeur de suivi des
/// produits : consommations par mois, stock disponible, commande, quantité
/// à commander).
class StockTableRow {
  final StockItem item;

  /// Consommation par mois de l'année affichée (index 0 = janvier ... 11 =
  /// décembre), comme les colonnes mensuelles du classeur de suivi.
  final List<double> monthly;
  final double consumption;
  final StockForecast forecast;

  /// Stock au 1er janvier de l'année affichée (voir [StockState.openingStockAt]).
  final double opening;

  /// Quantité achetée (entrées) durant l'année affichée.
  final double purchased;

  const StockTableRow(this.item, this.monthly, this.consumption, this.forecast, this.opening, this.purchased);

  double get toOrder => item.toOrder(consumption);

  /// Stock restant = stock de départ − consommé + acheté, comme la colonne
  /// « Remaining Quantity in Stock » du classeur de suivi (équivaut à la
  /// quantité actuelle de l'article pour l'année en cours).
  double get remaining => opening - consumption + purchased;
}

List<StockTableRow> stockTableRows(StockState stock, int year) {
  final items = [...stock.items]
    ..sort((a, b) {
      final byCategory = a.category.compareTo(b.category);
      return byCategory != 0 ? byCategory : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  final isCurrentYear = year == DateTime.now().year;
  return [
    for (final i in items)
      () {
        final monthly = stock.monthlyConsumptionOf(i.id, year);
        final total = monthly.fold<double>(0, (a, b) => a + b);
        return StockTableRow(
          i,
          monthly,
          (isCurrentYear ? i.consumptionOverride : null) ?? total,
          stock.forecastOf(i),
          stock.openingStockAt(i, year),
          stock.purchasedOf(i.id, year),
        );
      }(),
  ];
}

/// Clés des 12 en-têtes de mois (index 0 = janvier ... 11 = décembre).
const _monthHeaderKeys = [
  'stockMonthJan', 'stockMonthFeb', 'stockMonthMar', 'stockMonthApr',
  'stockMonthMay', 'stockMonthJun', 'stockMonthJul', 'stockMonthAug',
  'stockMonthSep', 'stockMonthOct', 'stockMonthNov', 'stockMonthDec',
];

/// Le suivi annuel d'une zone (Chimique, ARO, Wells, CPF, Laboratoire...) :
/// ses lignes, triées par catégorie puis par nom, et le total à commander
/// (pour le signaler d'un coup d'œil sans dérouler tout le tableau).
class StockTableSection {
  final String zone;
  final List<StockTableRow> rows;
  const StockTableSection(this.zone, this.rows);

  int get toOrderCount => rows.where((r) => r.toOrder > 0).length;
}

/// Le suivi annuel éclaté en un tableau par zone plutôt qu'un seul tableau
/// global : une zone sans article n'apparaît pas, et l'ordre suit
/// [stockZoneSuggestions] (zones libres ensuite par ordre alphabétique, non
/// affectées en dernier).
List<StockTableSection> stockTableSections(StockState stock, int year) {
  final rows = stockTableRows(stock, year);
  final byZone = <String, List<StockTableRow>>{};
  for (final r in rows) {
    byZone.putIfAbsent(r.item.zone.trim(), () => []).add(r);
  }
  final known = [for (final z in stockZoneSuggestions) if (byZone.containsKey(z)) z];
  final extra = byZone.keys.where((z) => z.isNotEmpty && !stockZoneSuggestions.contains(z)).toList()..sort();
  final order = [...known, ...extra, if (byZone.containsKey('')) ''];
  return [for (final z in order) StockTableSection(z, byZone[z]!)];
}

/// En-têtes du tableau de suivi annuel pour l'année [year] : une colonne par
/// mois (comme le classeur de suivi), suivie du total de l'année.
List<String> stockTableHeaders(String Function(String) s, int year) => [
  s('stockColDescription'),
  s('stockColReference'),
  s('stockMmnLabel'),
  s('stockPackagingLabel'),
  fill(s('stockColPrev'), {'y': '${year - 1}'}),
  for (final key in _monthHeaderKeys) s(key),
  fill(s('stockColMonthTotal'), {'y': '$year'}),
  fill(s('stockColAvailable'), {'y': '$year'}),
  fill(s('stockColPending'), {'y': '$year'}),
  s('stockColToOrder'),
  s('stockColRunOut'),
  s('stockColExpiry'),
  s('stockNotesLabel'),
];

/// Exporte le suivi annuel du stock (PDF / Excel / CSV), un tableau par zone
/// (Chimique, ARO, Wells, CPF, Laboratoire...), comme à l'écran. Demande
/// d'abord la période (année complète, ou un seul mois) pour le classeur
/// Excel — voir [StockMonthlyExcel].
Future<void> exportStock(WidgetRef ref, BuildContext context) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final period = await pickStockExportPeriod(context, locale, DateTime.now().year);
  if (period == null || !context.mounted) return;
  final year = period.year;
  final sections = stockTableSections(ref.read(stockControllerProvider), year);
  final headers = stockTableHeaders(s, year);

  final choice = await chooseExport(context, locale);
  if (choice == null || !context.mounted) return;
  await exportWithChoice(
    context: context,
    locale: locale,
    choice: choice,
    baseName: period.month == null ? 'stock_$year' : 'stock_${year}_${period.month!.toString().padLeft(2, '0')}',
    // Classeur Excel sur mesure (mise en page du classeur de suivi du
    // laboratoire : bandeau, titre, colonnes mensuelles, statut coloré) —
    // CSV/PDF restent le tableau générique ci-dessous (toujours l'année
    // complète, inchangé).
    xlsxBuilder: () => StockMonthlyExcel.encode(sections: sections, year: year, month: period.month, s: s),
    tables: [
      for (final section in sections)
        ExportTable(
          name: section.zone.isEmpty ? s('stockZoneUnclassified') : section.zone,
          headers: headers,
          rows: [
            for (final r in section.rows)
              [
                r.item.name,
                r.item.reference,
                r.item.mmn,
                r.item.packaging,
                r.item.prevConsumption ?? s('stockNewProduct'),
                ...r.monthly,
                r.consumption,
                r.item.quantity,
                r.item.pendingOrder,
                r.toOrder,
                stockForecastText(r.forecast, s),
                r.item.expiryDate == null ? '' : DateFormat('dd/MM/yyyy').format(r.item.expiryDate!),
                r.item.notes,
              ],
          ],
        ),
    ],
  );
}

/// Période choisie pour l'export du classeur mensuel : [month] nul = année
/// complète (12 colonnes), sinon un seul mois (1 = janvier ... 12 = décembre).
class StockExportPeriod {
  final int year;
  final int? month;
  const StockExportPeriod(this.year, this.month);
}

/// Demande la période à exporter (année complète ou un seul mois) avant de
/// générer le classeur. `null` si l'utilisateur ferme la feuille.
Future<StockExportPeriod?> pickStockExportPeriod(BuildContext context, Locale locale, int currentYear) =>
    showModalBottomSheet<StockExportPeriod>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => _StockExportPeriodSheet(locale: locale, currentYear: currentYear),
    );

class _StockExportPeriodSheet extends StatefulWidget {
  final Locale locale;
  final int currentYear;
  const _StockExportPeriodSheet({required this.locale, required this.currentYear});

  @override
  State<_StockExportPeriodSheet> createState() => _StockExportPeriodSheetState();
}

class _StockExportPeriodSheetState extends State<_StockExportPeriodSheet> {
  late bool _fullYear = true;
  late int _year = widget.currentYear;
  late int _month = DateTime.now().month;

  @override
  Widget build(BuildContext context) {
    String s(String key) => tr(widget.locale, key);
    final years = [for (var y = widget.currentYear; y >= widget.currentYear - 3; y--) y];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s('stockExportPeriodTitle'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: Text(s('stockExportFullYear')),
                    selected: _fullYear,
                    onSelected: (_) => setState(() => _fullYear = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceChip(
                    label: Text(s('stockExportOneMonth')),
                    selected: !_fullYear,
                    onSelected: (_) => setState(() => _fullYear = false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _year,
                    decoration: InputDecoration(labelText: s('stockExportYearLabel')),
                    items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                    onChanged: (v) => setState(() => _year = v ?? _year),
                  ),
                ),
                if (!_fullYear) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _month,
                      decoration: InputDecoration(labelText: s('stockExportMonthLabel')),
                      items: [
                        for (var m = 1; m <= 12; m++)
                          DropdownMenuItem(value: m, child: Text(s(_monthHeaderKeys[m - 1]))),
                      ],
                      onChanged: (v) => setState(() => _month = v ?? _month),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(StockExportPeriod(_year, _fullYear ? null : _month)),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(s('stockExportContinue'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
      floatingActionButton: role.canManageOps
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
            child: TapScale(child: _GaugeCard(item: items[i], forecast: stock.forecastOf(items[i]), s: s, scheme: scheme)),
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
