import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/lab/sample_manifest_repository.dart';
import '../../../core/plant/plant_repository.dart' show plantDayProvider;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../admin/presentation/widgets/admin_widgets.dart';
import '../../plant/presentation/plant_screen.dart' show plantDayLabel;

Color _sampleStatusColor(String status) {
  switch (status) {
    case 'sent':
      return const Color(0xFF2F6FDE);
    case 'received':
      return const Color(0xFF2E9E5B);
    default:
      return const Color(0xFFE08A00);
  }
}

/// Pastille de statut : un tap passe au statut suivant (préparé → envoyé → reçu).
class _SampleStatusPill extends StatelessWidget {
  final String status;
  final String Function(String) s;
  final VoidCallback onTap;
  const _SampleStatusPill({required this.status, required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final key = status.isEmpty ? 'prepared' : status;
    final color = _sampleStatusColor(key);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Text(s('sampleStatus_$key'), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    );
  }
}

/// Échantillons envoyés au labo pour le jour sélectionné (même jour que
/// l'écran Usine) : type, conditionnement, label, code OMV CPF — repris en
/// page « Scope of Work » en début de rapport usine (voir Réglages ›
/// Exports PDF).
class SampleManifestScreen extends ConsumerWidget {
  const SampleManifestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final day = ref.watch(plantDayProvider);
    final entries = ref.watch(sampleManifestControllerProvider(day));
    String s(String key) => tr(locale, key);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    final controller = ref.read(sampleManifestControllerProvider(day).notifier);
    Future<void> copyPreviousDay() async {
      final messenger = ScaffoldMessenger.of(context);
      final n = await controller.copyFromDay(day.subtract(const Duration(days: 1)));
      messenger.showSnackBar(SnackBar(content: Text(n == 0 ? s('sampleCopyNone') : '$n ${s('sampleCopyDone')}')));
    }

    Widget pill(SampleManifestEntry e) => _SampleStatusPill(
      status: e.status,
      s: s,
      onTap: () => controller.update(e.copyWith(status: nextSampleStatus(e.status))),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(s('sampleManifestTitle')),
        actions: [
          IconButton(
            tooltip: s('sampleCopyYesterday'),
            onPressed: copyPreviousDay,
            icon: const Icon(Icons.content_copy_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAdminSheet<void>(context, builder: (_) => _SampleFormSheet(day: day)),
        icon: const Icon(Icons.add),
        label: Text(s('sampleManifestAdd')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => ref.read(plantDayProvider.notifier).state = day.subtract(const Duration(days: 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: day,
                        firstDate: DateTime(2000),
                        lastDate: todayOnly,
                      );
                      if (picked != null) ref.read(plantDayProvider.notifier).state = picked;
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.event_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(plantDayLabel(day, locale, s), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: day.isBefore(todayOnly) ? () => ref.read(plantDayProvider.notifier).state = day.add(const Duration(days: 1)) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.biotech_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(s('sampleManifestEmpty'), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: copyPreviousDay,
                            icon: const Icon(Icons.content_copy_outlined),
                            label: Text(s('sampleCopyYesterday')),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: pagePadding(context, top: 12, bottom: 100),
                    children: [
                      Text(s('sampleManifestHint'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                      const SizedBox(height: 14),
                      AdminTable<SampleManifestEntry>(
                        items: entries,
                        onTap: (e) => showAdminSheet<void>(context, builder: (_) => _SampleFormSheet(day: day, existing: e)),
                        columns: [
                          AdminColumn(s('sampleManifestColTestItem'), (e) => Text(e.testItem, style: const TextStyle(fontWeight: FontWeight.w700))),
                          AdminColumn(s('sampleManifestColConditioning'), (e) => Text(e.conditioning.isEmpty ? '—' : e.conditioning)),
                          AdminColumn(s('sampleManifestColQuantity'), (e) => Text('${e.quantity}'), numeric: true),
                          AdminColumn(s('sampleManifestColLabel'), (e) => Text(e.label.isEmpty ? '—' : e.label)),
                          AdminColumn(s('sampleManifestColCpfCode'), (e) => Text(e.cpfCode.isEmpty ? '—' : e.cpfCode)),
                          AdminColumn(s('sampleManifestColSamplingTime'), (e) => Text(e.samplingTime.isEmpty ? '—' : e.samplingTime)),
                          AdminColumn(s('sampleStatusTitle'), pill),
                        ],
                        card: (context, e) => AdminCard(
                          leading: const IconBadge(Icons.biotech_outlined, color: accentColor),
                          title: e.testItem,
                          subtitle: '${e.conditioning} · ${e.label.isEmpty ? '—' : e.label} · ${e.cpfCode.isEmpty ? '—' : e.cpfCode}',
                          trailing: pill(e),
                          onTap: () => showAdminSheet<void>(context, builder: (_) => _SampleFormSheet(day: day, existing: e)),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SampleFormSheet extends ConsumerStatefulWidget {
  final DateTime day;
  final SampleManifestEntry? existing;
  const _SampleFormSheet({required this.day, this.existing});

  @override
  ConsumerState<_SampleFormSheet> createState() => _SampleFormSheetState();
}

class _SampleFormSheetState extends ConsumerState<_SampleFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _testItem;
  late final TextEditingController _conditioning;
  late final TextEditingController _quantity;
  late final TextEditingController _label;
  late final TextEditingController _cpfCode;
  late final TextEditingController _samplingTime;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _testItem = TextEditingController(text: e?.testItem ?? '');
    _conditioning = TextEditingController(text: e?.conditioning ?? '');
    _quantity = TextEditingController(text: '${e?.quantity ?? 1}');
    _label = TextEditingController(text: e?.label ?? '');
    _cpfCode = TextEditingController(text: e?.cpfCode ?? '');
    _samplingTime = TextEditingController(text: e?.samplingTime ?? '');
  }

  @override
  void dispose() {
    _testItem.dispose();
    _conditioning.dispose();
    _quantity.dispose();
    _label.dispose();
    _cpfCode.dispose();
    _samplingTime.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(sampleManifestControllerProvider(widget.day).notifier);
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final messenger = ScaffoldMessenger.of(context);
    final quantity = int.tryParse(_quantity.text.trim()) ?? 1;

    if (_isNew) {
      await controller.add(
        testItem: _testItem.text.trim(),
        conditioning: _conditioning.text.trim(),
        quantity: quantity,
        label: _label.text.trim(),
        cpfCode: _cpfCode.text.trim(),
        samplingTime: _samplingTime.text.trim(),
      );
      messenger.showSnackBar(SnackBar(content: Text(s('sampleManifestAdded'))));
    } else {
      await controller.update(
        widget.existing!.copyWith(
          testItem: _testItem.text.trim(),
          conditioning: _conditioning.text.trim(),
          quantity: quantity,
          label: _label.text.trim(),
          cpfCode: _cpfCode.text.trim(),
          samplingTime: _samplingTime.text.trim(),
        ),
      );
      messenger.showSnackBar(SnackBar(content: Text(s('sampleManifestUpdated'))));
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickSamplingTime() async {
    final parts = _samplingTime.text.split(':');
    final now = TimeOfDay.now();
    final initial = parts.length == 2
        ? TimeOfDay(hour: int.tryParse(parts[0]) ?? now.hour, minute: int.tryParse(parts[1]) ?? now.minute)
        : now;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() => _samplingTime.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _delete() async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final confirmed = await confirmDanger(
      context,
      title: s('sampleManifestDeleteConfirmTitle'),
      body: s('sampleManifestDeleteConfirmBody'),
      confirm: s('sampleManifestDelete'),
      cancel: s('cancel'),
    );
    if (!confirmed) return;
    await ref.read(sampleManifestControllerProvider(widget.day).notifier).delete(widget.existing!.id);
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
            _isNew ? s('sampleManifestNew') : s('sampleManifestEdit'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _testItem,
            decoration: InputDecoration(labelText: s('sampleManifestColTestItem'), hintText: s('sampleManifestTestItemHint')),
            validator: (v) => (v ?? '').trim().isEmpty ? s('sampleManifestInvalidTestItem') : null,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final item in sampleTestItemSuggestions)
                ActionChip(label: Text(item), onPressed: () => setState(() => _testItem.text = item)),
            ],
          ),
          const SizedBox(height: 12),
          ResponsiveWrapGrid(
            minItemWidth: 200,
            spacing: 12,
            children: [
              TextFormField(
                controller: _conditioning,
                decoration: InputDecoration(labelText: s('sampleManifestColConditioning')),
              ),
              TextFormField(
                controller: _quantity,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s('sampleManifestColQuantity')),
                validator: (v) {
                  final value = int.tryParse((v ?? '').trim());
                  return value == null || value <= 0 ? s('sampleManifestInvalidQuantity') : null;
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in sampleConditioningSuggestions)
                ActionChip(label: Text(c), onPressed: () => setState(() => _conditioning.text = c)),
            ],
          ),
          const SizedBox(height: 12),
          ResponsiveWrapGrid(
            minItemWidth: 200,
            spacing: 12,
            children: [
              TextFormField(
                controller: _label,
                decoration: InputDecoration(labelText: s('sampleManifestColLabel')),
              ),
              TextFormField(
                controller: _cpfCode,
                decoration: InputDecoration(labelText: s('sampleManifestColCpfCode')),
              ),
              TextFormField(
                controller: _samplingTime,
                readOnly: true,
                onTap: _pickSamplingTime,
                decoration: InputDecoration(
                  labelText: s('sampleManifestColSamplingTime'),
                  prefixIcon: const Icon(Icons.schedule_outlined),
                  suffixIcon: _samplingTime.text.isEmpty
                      ? null
                      : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _samplingTime.clear())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              child: Text(s('sampleManifestSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _delete,
                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                label: Text(s('sampleManifestDelete'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
