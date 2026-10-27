import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/analysis/series.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_catalog.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/units/unit_system.dart';
import '../../../core/widgets/responsive.dart';
import 'plant_schema_screens.dart' show pickSchemaImage;
import '../../../core/voice/spoken_number.dart';
import '../../../core/voice/voice_number_button.dart';

/// Saisie d'une nouvelle analyse d'un point pour un jour (plusieurs
/// prélèvements possibles le même jour), ou correction d'une analyse
/// précise si [analysisId] est fourni (depuis l'historique) : un champ par
/// paramètre, valeur hors seuil signalée en direct.
class PlantEntryScreen extends ConsumerStatefulWidget {
  final String pointId;
  final DateTime? initialDate;
  final String? analysisId;

  const PlantEntryScreen({super.key, required this.pointId, this.initialDate, this.analysisId});

  @override
  ConsumerState<PlantEntryScreen> createState() => _PlantEntryScreenState();
}

class _PlantEntryScreenState extends ConsumerState<PlantEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final _choices = <String, String?>{};
  final _comment = TextEditingController();

  /// Commentaire par paramètre, saisi pour justifier une valeur hors seuil
  /// (créé à la demande, un seul par paramètre numérique).
  final _paramComments = <String, TextEditingController>{};
  late DateTime _date;
  TimeOfDay? _samplingTime;
  late final TextEditingController _sourceController;
  String? _photo;
  bool _saving = false;

  /// `null` : nouvelle analyse (sera ajoutée, sans remplacer celles déjà
  /// saisies ce jour-là). Sinon : identifiant de l'analyse en cours de
  /// correction, qui sera remplacée à l'enregistrement.
  String? get _editingId => widget.analysisId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final d = widget.initialDate ?? now;
    _date = DateTime(d.year, d.month, d.day);
    final point = ref.read(plantControllerProvider.notifier).point(widget.pointId);
    for (final param in point?.params ?? const <PlantParam>[]) {
      if (param.computed) continue;
      if (param.isNumeric) {
        _fields[param.key] = TextEditingController()..addListener(() => setState(() {}));
      } else {
        _choices[param.key] = null;
      }
    }
    final locale = ref.read(localeProvider);
    _sourceController = TextEditingController(text: tr(locale, plantSources.first));
    if (_editingId != null) {
      _loadExisting();
    } else {
      _prefillCondensateDensity();
    }
  }

  bool _densityPrefilled = false;

  /// Densité du condensat reprise de la dernière analyse d'un point du circuit
  /// condensat (seulement en unités SI : la valeur affichée est alors celle
  /// enregistrée, en kg/m³).
  void _prefillCondensateDensity() {
    final field = _fields['cond_density'];
    if (field == null || Units.unit('kg/m³') != 'kg/m³') return;
    final plant = ref.read(plantControllerProvider.notifier);
    PlantAnalysis? best;
    for (final a in ref.read(plantControllerProvider).analyses) {
      final point = plant.point(a.pointId);
      if (point == null || point.profile != 'condensate' || a.number('density') == null) continue;
      if (best == null || a.date.isAfter(best.date)) best = a;
    }
    final v = best?.number('density');
    if (v == null) return;
    field.text = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    _densityPrefilled = true;
  }

  /// Pré-remplit avec l'analyse à corriger (mode édition uniquement : la
  /// saisie d'une nouvelle analyse démarre toujours vierge).
  void _loadExisting() {
    final controller = ref.read(plantControllerProvider.notifier);
    final existing = controller.byId(_editingId!);
    if (existing == null) return;
    _date = existing.date;
    for (final entry in _fields.entries) {
      final v = existing.number(entry.key);
      entry.value.text = v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
    }
    for (final key in _choices.keys.toList()) {
      _choices[key] = existing.values[key] as String?;
    }
    _comment.text = existing.comment ?? '';
    for (final entry in existing.paramComments.entries) {
      if (entry.value.isEmpty) continue;
      (_paramComments[entry.key] ??= TextEditingController()).text = entry.value;
    }
    // Les anciennes analyses stockent une clé de traduction (plantSourceLab
    // etc.) ; les nouvelles un texte libre tel quel — `tr` renvoie la clé
    // inchangée si elle n'est pas dans le dictionnaire, donc les deux cas
    // s'affichent correctement sans distinction.
    _sourceController.text = tr(ref.read(localeProvider), existing.source);
    _samplingTime = _parseTime(existing.startTime);
    _photo = existing.photo;
  }

  Future<void> _pickPhoto() async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final image = await pickSchemaImage(context, s);
    if (image != null && mounted) setState(() => _photo = image.base64);
  }

  static TimeOfDay? _parseTime(String? text) {
    if (text == null) return null;
    final parts = text.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String? _formatTime(TimeOfDay? time) =>
      time == null ? null : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _comment.dispose();
    for (final c in _paramComments.values) {
      c.dispose();
    }
    _sourceController.dispose();
    super.dispose();
  }

  double? _parse(String text) => double.tryParse(text.trim().replaceAll(',', '.').replaceAll(' ', ''));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final values = <String, Object?>{
      for (final e in _fields.entries)
        if (_parse(e.value.text) != null) e.key: _parse(e.value.text),
      for (final e in _choices.entries)
        if (e.value != null) e.key: e.value,
    };
    final computed = plantComputedValues({
      for (final e in values.entries)
        if (e.value is num) e.key: (e.value as num).toDouble(),
    });
    final point = ref.read(plantControllerProvider.notifier).point(widget.pointId);
    for (final param in point?.params ?? const <PlantParam>[]) {
      if (param.computed && computed[param.key] != null) values[param.key] = computed[param.key];
    }
    if (values.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('plantEntryEmpty'))));
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(plantControllerProvider.notifier)
        .saveAnalysis(
          pointId: widget.pointId,
          day: _date,
          values: values,
          source: _sourceController.text.trim(),
          operatorName: ref.read(profileProvider)?.fullName ?? '',
          comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
          id: _editingId,
          startTime: _formatTime(_samplingTime),
          photo: _photo,
          paramComments: {
            for (final e in _paramComments.entries)
              if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
          },
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(s('plantEntrySaved'))));
  }

  Future<void> _delete(PlantAnalysis existing) async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s('plantDeleteConfirmTitle')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s('recordDelete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(plantControllerProvider.notifier).deleteAnalysis(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    ref.watch(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    String s(String key) => tr(locale, key);
    final point = controller.point(widget.pointId);
    if (point == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(s('plantPointNotFound'))),
      );
    }
    final editing = _editingId == null ? null : controller.byId(_editingId!);
    // En mode ajout, les autres analyses déjà saisies ce jour-là (hors
    // l'éventuelle analyse en cours de correction) : affichées à titre
    // d'information, elles ne sont pas remplacées.
    final sameDayOthers = controller
        .analysesOnDay(point.id, _date)
        .where((a) => a.id != _editingId)
        .toList();
    final now = DateTime.now();

    Widget numberField(PlantParam param) {
      final value = _parse(_fields[param.key]!.text);
      final out = controller.isOut(point.id, param, value);
      final t = controller.threshold(point.id, param.key);
      final field = TextFormField(
        controller: _fields[param.key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(
          labelText: s(param.labelKey),
          suffixText: param.unit,
          suffixIcon: VoiceNumberButton(
            onNumber: (v) => setState(() => _fields[param.key]!.text = spokenNumberText(v)),
          ),
          helperText: t == null ? null : '${s('trendThreshold')} : ${t.label(formatNumber)}',
          errorText: out == true ? s('plantValueOut') : null,
          errorStyle: TextStyle(color: scheme.error, fontWeight: FontWeight.w700),
        ),
        validator: (v) => (v ?? '').trim().isEmpty || _parse(v!) != null ? null : s('entryInvalidValue'),
      );
      if (out != true) return field;
      // Valeur hors seuil : champ pour expliquer pourquoi (imprimé en gras
      // rouge avec ce commentaire dans le PDF, si activé dans les réglages).
      final commentField = _paramComments.putIfAbsent(param.key, () => TextEditingController());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          field,
          const SizedBox(height: 6),
          TextFormField(
            controller: commentField,
            minLines: 1,
            maxLines: 2,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              labelText: s('plantOutOfRangeCommentLabel'),
              isDense: true,
              prefixIcon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 18),
            ),
          ),
        ],
      );
    }

    final numeric = point.params.where((p) => p.isNumeric && !p.computed).toList();
    final computedParams = point.params.where((p) => p.computed).toList();
    final liveComputed = plantComputedValues({
      for (final e in _fields.entries)
        if (_parse(e.value.text) != null) e.key: _parse(e.value.text)!,
    });
    final composition = numeric.where((p) => gasCompositionKeys.contains(p.key)).toList();
    final others = numeric
        .where((p) => !gasCompositionKeys.contains(p.key) && p.key != 'water_flow' && p.key != 'cond_density' && !(p.key == 'tph' && computedParams.isNotEmpty))
        .toList();
    final flowParam = numeric.where((p) => p.key == 'water_flow').firstOrNull;
    final densityParam = numeric.where((p) => p.key == 'cond_density').firstOrNull;
    final tphParam = numeric.where((p) => p.key == 'tph').firstOrNull;
    final compositionSum = composition.fold<double>(0, (sum, p) => sum + (_parse(_fields[p.key]!.text) ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: Text('${s('plantEnter')} · ${point.code}'),
        actions: [
          if (editing != null)
            IconButton(
              tooltip: s('recordDelete'),
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: () => _delete(editing),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: pagePadding(context, top: 8, bottom: 40, maxWidth: 700),
          children: [
            Text(point.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              '${s(point.circuit.labelKey)} · ${point.equipment}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(now.year, now.month, now.day),
                );
                if (picked == null) return;
                // En mode édition, changer la date déplace l'analyse corrigée
                // vers ce nouveau jour plutôt que d'en recharger une autre.
                setState(() => _date = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: s('plantSampleDate'),
                  prefixIcon: const Icon(Icons.event_outlined),
                ),
                child: Text(DateFormat('EEEE d MMMM yyyy', locale.languageCode).format(_date)),
              ),
            ),
            const SizedBox(height: 10),
            _TimeField(
              label: s('plantSamplingTime'),
              value: _samplingTime,
              onChanged: (t) => setState(() => _samplingTime = t),
            ),
            if (editing != null) ...[
              const SizedBox(height: 6),
              Text(
                s('plantEntryEditing'),
                style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ] else if (sameDayOthers.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${sameDayOthers.length} ${s('plantEntryOthersToday')}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 14),
            if (composition.isNotEmpty) ...[
              Text(s('plantComposition'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ResponsiveWrapGrid(
                minItemWidth: 150,
                spacing: 10,
                children: [for (final p in composition) numberField(p)],
              ),
              const SizedBox(height: 6),
              Text(
                '${s('plantCompositionSum')} : ${formatNumber(compositionSum)} mol %',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: compositionSum > 0 && (compositionSum < 98 || compositionSum > 102)
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
            ResponsiveWrapGrid(minItemWidth: 260, spacing: 10, children: [for (final p in others) numberField(p)]),
            if (computedParams.isNotEmpty) ...[
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calculate_outlined, color: accentColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s('plantCalcTitle'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(s('plantCalcHint'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.35)),
                    const SizedBox(height: 14),
                    Text(s('plantCalcInputs'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ResponsiveWrapGrid(
                      minItemWidth: 240,
                      spacing: 10,
                      children: [
                        if (flowParam != null) numberField(flowParam),
                        if (tphParam != null) numberField(tphParam),
                        if (densityParam != null) numberField(densityParam),
                      ],
                    ),
                    if (_densityPrefilled)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(s('plantCalcPrefilled'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                      ),
                    const Divider(height: 26),
                    Text(s('plantCalcResults'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (liveComputed.isEmpty)
                      Text(s('plantCalcNeedMore'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))
                    else ...[
                      for (final p in computedParams)
                        if (liveComputed[p.key] != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(child: Text(s(p.labelKey), style: const TextStyle(fontSize: 13.5))),
                                Text(
                                  '${formatNumber(liveComputed[p.key]!)} ${p.unit}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: accentColor),
                                ),
                              ],
                            ),
                          ),
                      const SizedBox(height: 6),
                      Text(s('plantCalcStepMass'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                      Text(s('plantCalcStepVolume'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ],
            for (final param in point.params.where((p) => !p.isNumeric)) ...[
              const SizedBox(height: 16),
              Text(s(param.labelKey), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in param.choices)
                    ChoiceChip(
                      label: Text(s(choice)),
                      selected: _choices[param.key] == choice,
                      selectedColor: (param.okChoices.contains(choice) ? Colors.green : scheme.error).withValues(
                        alpha: 0.18,
                      ),
                      onSelected: (selected) => setState(() => _choices[param.key] = selected ? choice : null),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            TextFormField(
              controller: _sourceController,
              decoration: InputDecoration(labelText: s('plantColSource')),
              validator: (v) => (v ?? '').trim().isEmpty ? s('plantSourceRequired') : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final key in plantSources)
                  ActionChip(label: Text(s(key)), onPressed: () => setState(() => _sourceController.text = s(key))),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _comment,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: s('entryCommentLabel')),
            ),
            const SizedBox(height: 18),
            Text(s('plantPhotoLabel'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_photo == null)
              OutlinedButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(s('plantPhotoAdd')),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Image.memory(base64Decode(_photo!), height: 180, width: double.infinity, fit: BoxFit.cover),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Row(
                        children: [
                          _PhotoActionButton(icon: Icons.sync, tooltip: s('plantPhotoReplace'), onPressed: _pickPhoto),
                          const SizedBox(width: 6),
                          _PhotoActionButton(
                            icon: Icons.delete_outline,
                            tooltip: s('plantPhotoRemove'),
                            onPressed: () => setState(() => _photo = null),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(s('wellsManageSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Petit bouton rond superposé à la photo (remplacer / retirer).
class _PhotoActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _PhotoActionButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Champ "heure" facultatif (ouvre un sélecteur, effaçable une fois rempli).
class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay?> onChanged;

  const _TimeField({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: value ?? TimeOfDay.now());
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule_outlined),
          suffixIcon: value == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(value == null ? '—' : value!.format(context)),
      ),
    );
  }
}
