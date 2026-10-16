import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/stock_repository.dart';
import '../../../../core/data/wells_repository.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/models/stock_item.dart';
import '../../../admin/presentation/widgets/admin_widgets.dart';

/// Ouvre la feuille d'un mouvement de stock (entrée ou sortie) pour [item].
Future<void> showStockMovementSheet(BuildContext context, {required StockItem item, required bool isEntry}) {
  return showAdminSheet<void>(context, builder: (_) => _StockMovementSheet(item: item, isEntry: isEntry));
}

class _StockMovementSheet extends ConsumerStatefulWidget {
  final StockItem item;
  final bool isEntry;
  const _StockMovementSheet({required this.item, required this.isEntry});

  @override
  ConsumerState<_StockMovementSheet> createState() => _StockMovementSheetState();
}

class _StockMovementSheetState extends ConsumerState<_StockMovementSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  String? _wellId;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final quantity = parseDecimal(_quantityController.text) ?? 0;
    final locale = ref.read(localeProvider);
    final profile = ref.read(profileProvider);
    String s(String key) => tr(locale, key);
    final messenger = ScaffoldMessenger.of(context);

    await ref.read(stockControllerProvider.notifier).addMovement(
          itemId: widget.item.id,
          delta: widget.isEntry ? quantity : -quantity,
          reason: _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
          wellId: _wellId,
          operatorName: profile?.fullName ?? '',
        );
    messenger.showSnackBar(SnackBar(content: Text(s(widget.isEntry ? 'stockEntryAdded' : 'stockExitAdded'))));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final wells = ref.watch(wellsControllerProvider).wells.where((w) => w.active).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    String s(String key) => tr(locale, key);
    final color = widget.isEntry ? Colors.green.shade600 : Theme.of(context).colorScheme.error;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.isEntry ? s('stockEntryTitle') : s('stockExitTitle'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.item.name} · ${s('stockQuantityLabel')} : ${widget.item.quantity == widget.item.quantity.roundToDouble() ? widget.item.quantity.toInt() : widget.item.quantity.toStringAsFixed(2)} ${widget.item.unit}',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _quantityController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: s('stockMovementQuantityLabel'), suffixText: widget.item.unit),
            validator: (v) {
              final value = parseDecimal(v ?? '');
              if (value == null || value <= 0) return s('stockInvalidQuantity');
              if (!widget.isEntry && value > widget.item.quantity) return s('stockExitTooMuch');
              return null;
            },
          ),
          const SizedBox(height: 12),
          if (!widget.isEntry)
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: _wellId,
              decoration: InputDecoration(labelText: s('stockUsedByWell')),
              items: [
                DropdownMenuItem(value: null, child: Text(s('stockUsedByWellNone'))),
                for (final well in wells) DropdownMenuItem(value: well.id, child: Text(well.name)),
              ],
              onChanged: (v) => setState(() => _wellId = v),
            ),
          if (!widget.isEntry) const SizedBox(height: 12),
          TextFormField(
            controller: _reasonController,
            decoration: InputDecoration(labelText: s('stockMovementReasonLabel'), hintText: s('stockMovementReasonHint')),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
              child: Text(
                widget.isEntry ? s('stockEntry') : s('stockExit'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
