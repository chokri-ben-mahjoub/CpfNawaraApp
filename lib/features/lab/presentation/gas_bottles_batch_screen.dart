import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/lab/gas_bottle_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';

const _red = Color(0xFFD32F2F);
const _green = Color(0xFF2E9E5B);

double? _parse(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Relevé quotidien de toutes les bouteilles sur un seul écran : une ligne
/// par bouteille, un seul « Enregistrer ». Le champ passe au rouge sous le
/// seuil de pression basse de la bouteille.
class GasBottlesBatchScreen extends ConsumerStatefulWidget {
  const GasBottlesBatchScreen({super.key});

  @override
  ConsumerState<GasBottlesBatchScreen> createState() => _GasBottlesBatchScreenState();
}

class _GasBottlesBatchScreenState extends ConsumerState<GasBottlesBatchScreen> {
  final Map<String, TextEditingController> _controllers = {};

  TextEditingController _controllerFor(GasBottle b) =>
      _controllers.putIfAbsent(b.id, () => TextEditingController(text: _fmt(b.pressure)));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(List<GasBottle> bottles) async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final values = <String, double>{};
    for (final b in bottles) {
      final v = _parse(_controllerFor(b).text);
      if (v != null && v >= 0) values[b.id] = v;
    }
    final count = await ref.read(gasBottleControllerProvider.notifier).setPressures(values);
    messenger.showSnackBar(
      SnackBar(content: Text(count == 0 ? s('gasBatchNone') : '$count ${s('gasBatchSaved')}')),
    );
    if (count > 0) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final bottles = ref.watch(gasBottleControllerProvider);
    String s(String key) => tr(locale, key);

    return Scaffold(
      appBar: AppBar(title: Text(s('gasBatchTitle'))),
      body: ListView(
        padding: pagePadding(context, top: 12, bottom: 24),
        children: [
          Text(
            s('gasBatchIntro'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          for (final b in bottles)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StatefulBuilder(
                builder: (context, setLocal) {
                  final controller = _controllerFor(b);
                  final value = _parse(controller.text);
                  final low = value != null && b.minPressure > 0 && value < b.minPressure;
                  final color = value == null ? null : (low ? _red : _green);
                  return TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setLocal(() {}),
                    style: TextStyle(fontWeight: FontWeight.w800, color: color),
                    decoration: InputDecoration(
                      labelText: b.label,
                      helperText: b.location.isEmpty ? null : b.location,
                      suffixText: 'bars',
                      suffixIcon: low ? const Icon(Icons.warning_amber_rounded, color: _red) : null,
                      enabledBorder: color == null
                          ? null
                          : OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: color, width: 1.6),
                            ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: bottles.isEmpty ? null : () => _save(bottles),
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              child: Text(s('gasBatchSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
