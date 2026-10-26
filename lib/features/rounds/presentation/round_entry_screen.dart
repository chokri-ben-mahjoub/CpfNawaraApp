import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/rounds_repository.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/well_round.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';

/// Saisie d'une tournée de l'opérateur pour un puits (ou pour le site si
/// [wellId] est vide) : un champ par paramètre, regroupés par section, avec
/// la dernière valeur relevée en rappel. Nouvelle tournée, ou correction si
/// [roundId] est fourni.
class RoundEntryScreen extends ConsumerStatefulWidget {
  final String wellId;
  final DateTime day;
  final String? roundId;
  const RoundEntryScreen({super.key, required this.wellId, required this.day, this.roundId});

  @override
  ConsumerState<RoundEntryScreen> createState() => _RoundEntryScreenState();
}

class _RoundEntryScreenState extends ConsumerState<RoundEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final _choices = <String, String?>{};
  final _comment = TextEditingController();
  late TimeOfDay _time;
  bool _saving = false;

  bool get _isSite => widget.wellId == siteRoundId;
  List<RoundField> get _defs => _isSite ? siteRoundFields : wellRoundFields;

  @override
  void initState() {
    super.initState();
    _time = TimeOfDay.now();
    for (final f in _defs) {
      if (f.isNumber) {
        _fields[f.key] = TextEditingController();
      } else {
        _choices[f.key] = null;
      }
    }
    final existing = widget.roundId == null ? null : ref.read(roundsControllerProvider.notifier).byId(widget.roundId!);
    if (existing != null) {
      for (final e in _fields.entries) {
        final v = existing.number(e.key);
        e.value.text = v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
      }
      for (final k in _choices.keys.toList()) {
        _choices[k] = existing.choice(k);
      }
      _comment.text = existing.comment ?? '';
      final parts = existing.time.split(':');
      if (parts.length == 2) {
        _time = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _comment.dispose();
    super.dispose();
  }

  double? _parse(String text) => double.tryParse(text.trim().replaceAll(',', '.').replaceAll(' ', ''));

  String get _timeText => '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final locale = ref.read(localeProvider);
    final values = <String, Object?>{
      for (final e in _fields.entries)
        if (_parse(e.value.text) != null) e.key: _parse(e.value.text),
      for (final e in _choices.entries)
        if (e.value != null) e.key: e.value,
    };
    if (values.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(locale, 'plantEntryEmpty'))));
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(roundsControllerProvider.notifier)
        .save(
          id: widget.roundId,
          wellId: widget.wellId,
          day: widget.day,
          time: _timeText,
          values: values,
          operatorName: ref.read(profileProvider)?.fullName ?? '',
          comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(tr(locale, 'roundsSaved'))));
  }

  Future<void> _delete() async {
    final locale = ref.read(localeProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(locale, 'roundsDeleteTitle')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr(locale, 'cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr(locale, 'recordDelete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(roundsControllerProvider.notifier).delete(widget.roundId!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final rounds = ref.watch(roundsControllerProvider);
    final previous = rounds.previous(widget.wellId, widget.day, excludeId: widget.roundId);
    final well = _isSite
        ? null
        : ref.watch(wellsControllerProvider).wells.where((w) => w.id == widget.wellId).firstOrNull;
    final title = _isSite ? s('roundsSite') : (well == null ? widget.wellId : '${well.name} · ${well.code}');

    // Sections dans l'ordre d'apparition des champs.
    final sections = <String>[];
    for (final f in _defs) {
      if (!sections.contains(f.section)) sections.add(f.section);
    }

    Widget numberField(RoundField f) {
      final prev = previous?.number(f.key);
      return TextFormField(
        controller: _fields[f.key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        textInputAction: TextInputAction.next,
        scrollPadding: const EdgeInsets.only(bottom: 140),
        decoration: InputDecoration(
          labelText: s(f.labelKey),
          suffixText: f.unit,
          helperText: prev == null ? null : '${s('roundsPrevious')} : ${prev == prev.roundToDouble() ? prev.toInt() : prev}',
        ),
        validator: (v) => (v ?? '').trim().isEmpty || _parse(v!) != null ? null : s('entryInvalidValue'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.roundId != null)
            IconButton(
              tooltip: s('recordDelete'),
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: pagePadding(context, top: 8, bottom: 40, maxWidth: 700),
          children: [
            Text(
              DateFormat('EEEE d MMMM yyyy', locale.languageCode).format(widget.day),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final picked = await showTimePicker(context: context, initialTime: _time);
                if (picked != null) setState(() => _time = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(labelText: s('roundsColTime'), prefixIcon: const Icon(Icons.schedule_outlined)),
                child: Text(_timeText),
              ),
            ),
            for (final section in sections) ...[
              const SizedBox(height: 20),
              Text(s('rs_$section'), style: const TextStyle(fontWeight: FontWeight.w800, color: accentColor, fontSize: 15)),
              const Divider(height: 14),
              ResponsiveWrapGrid(
                minItemWidth: 220,
                spacing: 10,
                children: [for (final f in _defs.where((x) => x.section == section && x.isNumber)) numberField(f)],
              ),
              for (final f in _defs.where((x) => x.section == section && !x.isNumber)) ...[
                const SizedBox(height: 10),
                Text(s(f.labelKey), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in f.choices)
                      ChoiceChip(
                        label: Text(s(c)),
                        selected: _choices[f.key] == c,
                        selectedColor: (c == 'roundClosed' || c == 'roundNotOk' || c == 'roundStopped'
                                ? scheme.error
                                : Colors.green)
                            .withValues(alpha: 0.18),
                        onSelected: (sel) => setState(() => _choices[f.key] = sel ? c : null),
                      ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _comment,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: s('entryCommentLabel')),
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
