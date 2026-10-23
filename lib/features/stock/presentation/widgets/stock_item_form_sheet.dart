import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/stock_repository.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/models/stock_item.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../admin/presentation/widgets/admin_widgets.dart';

/// Formulaire d'ajout (quantité initiale saisie une fois) ou de modification
/// (nom, unité, seuil, catégorie — la quantité se change ensuite uniquement
/// via un mouvement, voir `StockItemDetailScreen`).
class StockItemFormSheet extends ConsumerStatefulWidget {
  final StockItem? existing;
  const StockItemFormSheet({super.key, this.existing});

  @override
  ConsumerState<StockItemFormSheet> createState() => _StockItemFormSheetState();
}

class _StockItemFormSheetState extends ConsumerState<StockItemFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _unitController;
  late final TextEditingController _quantityController;
  late final TextEditingController _thresholdController;
  late final TextEditingController _categoryController;
  late final TextEditingController _notesController;
  late final TextEditingController _referenceController;
  late final TextEditingController _mmnController;
  late final TextEditingController _prevController;
  late final TextEditingController _pendingController;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _unitController = TextEditingController(text: e?.unit ?? '');
    _quantityController = TextEditingController(text: e == null ? '' : decimalText(e.quantity));
    _thresholdController = TextEditingController(text: decimalText(e?.threshold));
    _categoryController = TextEditingController(text: e?.category ?? '');
    _notesController = TextEditingController(text: e?.notes ?? '');
    _referenceController = TextEditingController(text: e?.reference ?? '');
    _mmnController = TextEditingController(text: e?.mmn ?? '');
    _prevController = TextEditingController(text: e?.prevConsumption == null ? '' : decimalText(e!.prevConsumption));
    _pendingController = TextEditingController(text: e == null || e.pendingOrder == 0 ? '' : decimalText(e.pendingOrder));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _quantityController.dispose();
    _thresholdController.dispose();
    _categoryController.dispose();
    _notesController.dispose();
    _referenceController.dispose();
    _mmnController.dispose();
    _prevController.dispose();
    _pendingController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(stockControllerProvider.notifier);
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final messenger = ScaffoldMessenger.of(context);

    final threshold = parseDecimal(_thresholdController.text) ?? 0;
    final prev = parseDecimal(_prevController.text);
    final pending = parseDecimal(_pendingController.text) ?? 0;
    if (_isNew) {
      await controller.addItem(
        name: _nameController.text.trim(),
        unit: _unitController.text.trim(),
        quantity: parseDecimal(_quantityController.text) ?? 0,
        threshold: threshold,
        category: _categoryController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        reference: _referenceController.text.trim(),
        mmn: _mmnController.text.trim(),
        prevConsumption: prev,
        pendingOrder: pending,
      );
      messenger.showSnackBar(SnackBar(content: Text(s('stockItemAdded'))));
    } else {
      await controller.updateItem(
        widget.existing!.copyWith(
          name: _nameController.text.trim(),
          unit: _unitController.text.trim(),
          threshold: threshold,
          category: _categoryController.text.trim(),
          notes: _notesController.text.trim(),
          reference: _referenceController.text.trim(),
          mmn: _mmnController.text.trim(),
          prevConsumption: prev,
          clearPrevConsumption: prev == null,
          pendingOrder: pending,
        ),
      );
      messenger.showSnackBar(SnackBar(content: Text(s('stockItemUpdated'))));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isNew ? s('stockItemNew') : s('stockItemEdit'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(labelText: s('stockNameLabel'), hintText: s('stockNameHint')),
            validator: (v) => (v ?? '').trim().isEmpty ? s('stockInvalidName') : null,
          ),
          const SizedBox(height: 12),
          ResponsiveWrapGrid(
            minItemWidth: 200,
            spacing: 12,
            children: [
              TextFormField(
                controller: _referenceController,
                decoration: InputDecoration(labelText: s('stockReferenceLabel')),
              ),
              TextFormField(
                controller: _mmnController,
                decoration: InputDecoration(labelText: s('stockMmnLabel')),
              ),
              TextFormField(
                controller: _prevController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: s('stockPrevConsumptionLabel'), helperText: s('stockPrevConsumptionHint')),
              ),
              TextFormField(
                controller: _pendingController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: s('stockPendingOrderLabel')),
              ),
              TextFormField(
                controller: _unitController,
                decoration: InputDecoration(labelText: s('stockUnitLabel'), hintText: s('stockUnitHint')),
              ),
              TextFormField(
                controller: _quantityController,
                enabled: _isNew,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: s('stockQuantityLabel'),
                  helperText: _isNew ? null : s('stockQuantityEditHint'),
                ),
                validator: (v) {
                  if (!_isNew) return null;
                  final value = parseDecimal(v ?? '');
                  return value == null || value < 0 ? s('stockInvalidQuantity') : null;
                },
              ),
            ],
          ),
          if (stockUnitSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final unit in stockUnitSuggestions)
                  ActionChip(label: Text(unit), onPressed: () => setState(() => _unitController.text = unit)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _thresholdController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: s('stockThresholdLabel'), helperText: s('stockThresholdHelper')),
            validator: (v) {
              final value = parseDecimal(v ?? '');
              return value == null || value < 0 ? s('stockInvalidQuantity') : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _categoryController,
            decoration: InputDecoration(labelText: s('stockCategoryLabel'), hintText: s('stockCategoryHint')),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final category in stockCategorySuggestions)
                ActionChip(label: Text(category), onPressed: () => setState(() => _categoryController.text = category)),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesController,
            maxLines: 2,
            decoration: InputDecoration(labelText: s('stockNotesLabel')),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              child: Text(s('stockSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
