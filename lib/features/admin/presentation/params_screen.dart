import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_catalog.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import 'widgets/admin_widgets.dart';

/// Ouvre le formulaire d'un paramètre personnalisé (nouveau si [existing]
/// est nul) ; renvoie la clé enregistrée, ou `null` si annulé.
Future<String?> showPlantParamForm(BuildContext context, {PlantParam? existing}) =>
    showAdminSheet<String>(context, builder: (_) => _ParamForm(existing: existing));

/// Administration › Paramètres et modèles : paramètres personnalisés (en
/// plus des paramètres intégrés) et modèles de paramètres proposés à la
/// création d'un circuit ou d'un point.
class ParamsScreen extends ConsumerWidget {
  const ParamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(s('adminParams')),
            bottom: TabBar(
              tabs: [
                Tab(text: s('paramsTabParams')),
                Tab(text: s('paramsTabProfiles')),
              ],
            ),
          ),
          floatingActionButton: AnimatedBuilder(
            animation: DefaultTabController.of(context),
            builder: (context, _) {
              final profiles = DefaultTabController.of(context).index == 1;
              return FloatingActionButton.extended(
                onPressed: () => profiles
                    ? showAdminSheet<void>(context, builder: (_) => const _ProfileForm())
                    : showPlantParamForm(context),
                icon: const Icon(Icons.add),
                label: Text(s(profiles ? 'profilesAdd' : 'paramsAdd')),
              );
            },
          ),
          body: const TabBarView(children: [_ParamsTab(), _ProfilesTab()]),
        ),
      ),
    );
  }
}

class _ParamsTab extends ConsumerWidget {
  const _ParamsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final plant = ref.watch(plantControllerProvider);
    String s(String key) => tr(locale, key);

    String detail(PlantParam p) {
      final type = p.isNumeric ? s('paramsKindNumber') : '${s('paramsKindChoice')} : ${p.choices.map(s).join(', ')}';
      return p.unit.isEmpty ? type : '${p.unit} · $type';
    }

    return ListView(
      padding: pagePadding(context, top: 12, bottom: 130),
      children: [
        Text(s('paramsIntro'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
        const SizedBox(height: 12),
        AdminSectionTitle(fill(s('paramsCustomTitle'), {'n': '${plant.customParams.length}'})),
        if (plant.customParams.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(s('paramsCustomEmpty'), style: TextStyle(color: scheme.onSurfaceVariant)),
          )
        else
          for (final p in plant.customParams)
            AdminCard(
              leading: IconBadge(p.isNumeric ? Icons.straighten : Icons.list_alt),
              title: p.labelKey,
              subtitle: detail(p),
              onTap: () => showPlantParamForm(context, existing: p),
            ),
        const SizedBox(height: 16),
        AdminSectionTitle(fill(s('paramsBuiltInTitle'), {'n': '${builtInParamCatalog.length}'})),
        Text(s('paramsBuiltInHint'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in builtInParamCatalog)
              Chip(label: Text('${s(p.labelKey)}${p.unit.isEmpty ? '' : ' (${p.displayed().unit})'}')),
          ],
        ),
      ],
    );
  }
}

class _ProfilesTab extends ConsumerWidget {
  const _ProfilesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final plant = ref.watch(plantControllerProvider);
    String s(String key) => tr(locale, key);
    final defs = {for (final d in plant.profileDefs) d.id: d};

    return ListView(
      padding: pagePadding(context, top: 12, bottom: 130),
      children: [
        Text(s('profilesIntro'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
        const SizedBox(height: 12),
        for (final e in plantProfileLabelKeys.entries)
          AdminCard(
            leading: IconBadge(
              Icons.checklist_rtl,
              color: builtInPlantProfiles.containsKey(e.key) ? accentColor : Colors.teal,
            ),
            title: s(e.value),
            subtitle: [
              fill(s('profilesParamCount'), {'n': '${paramsForProfile(e.key).length}'}),
              if (!builtInPlantProfiles.containsKey(e.key))
                s('profilesAdded')
              else if (defs.containsKey(e.key))
                s('profilesModified'),
            ].join(' · '),
            onTap: () => showAdminSheet<void>(context, builder: (_) => _ProfileForm(id: e.key)),
          ),
      ],
    );
  }
}

/// Formulaire d'un paramètre personnalisé : nom, unité, type, choix.
class _ParamForm extends ConsumerStatefulWidget {
  final PlantParam? existing;
  const _ParamForm({this.existing});

  @override
  ConsumerState<_ParamForm> createState() => _ParamFormState();
}

class _ParamFormState extends ConsumerState<_ParamForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _unit;
  late final TextEditingController _choices;
  late ParamKind _kind;
  late Set<String> _ok;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _label = TextEditingController(text: p?.labelKey ?? '');
    _unit = TextEditingController(text: p?.unit ?? '');
    _choices = TextEditingController(text: p?.choices.join('\n') ?? '');
    _kind = p?.kind ?? ParamKind.number;
    _ok = {...?p?.okChoices};
  }

  @override
  void dispose() {
    _label.dispose();
    _unit.dispose();
    _choices.dispose();
    super.dispose();
  }

  List<String> get _choiceList => <String>{
    for (final line in _choices.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  }.toList();

  String s(String key) => tr(ref.read(localeProvider), key);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final label = _label.text.trim();
    final choices = _choiceList;
    if (_kind == ParamKind.choice && choices.length < 2) {
      setState(() => _error = s('paramsChoicesInvalid'));
      return;
    }
    final existing = widget.existing;
    final taken = plantParamCatalog.any(
      (p) => p.key != existing?.key && s(p.labelKey).toLowerCase() == label.toLowerCase(),
    );
    if (taken) {
      setState(() => _error = s('paramsDuplicate'));
      return;
    }
    final key = await ref
        .read(plantControllerProvider.notifier)
        .saveParam(
          customPlantParam(
            key: existing?.key ?? '',
            label: label,
            unit: _kind == ParamKind.number ? _unit.text.trim() : '',
            kind: _kind,
            choices: _kind == ParamKind.choice ? choices : const [],
            okChoices: _kind == ParamKind.choice
                ? [
                    for (final c in choices)
                      if (_ok.contains(c)) c,
                  ]
                : const [],
          ),
          sortOrder: existing == null ? null : ref.read(plantControllerProvider).customParams.indexOf(existing) + 1,
        );
    if (!mounted) return;
    Navigator.of(context).pop(key);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('paramsSaved'))));
  }

  Future<void> _delete() async {
    final controller = ref.read(plantControllerProvider.notifier);
    final key = widget.existing!.key;
    final usage = controller.paramUsage(key);
    if (usage.isNotEmpty) {
      setState(() => _error = fill(s('paramsInUse'), {'list': usage.map(s).join(', ')}));
      return;
    }
    final ok = await confirmDanger(
      context,
      title: s('paramsDeleteTitle'),
      body: s('paramsDeleteBody'),
      confirm: s('schemaDeleteConfirm'),
      cancel: s('cancel'),
    );
    if (!ok) return;
    await controller.deleteParam(key);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    ref.watch(localeProvider);
    final choices = _choiceList;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s(widget.existing == null ? 'paramsNew' : 'paramsEdit'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (widget.existing != null)
                IconButton(
                  tooltip: s('paramsDelete'),
                  onPressed: _delete,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _label,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: s('paramsName'), hintText: s('paramsNameHint')),
            validator: (v) => (v ?? '').trim().isEmpty ? s('paramsNameInvalid') : null,
          ),
          const SizedBox(height: 16),
          SegmentedButton<ParamKind>(
            segments: [
              ButtonSegment(
                value: ParamKind.number,
                icon: const Icon(Icons.pin_outlined),
                label: Text(s('paramsKindNumber')),
              ),
              ButtonSegment(
                value: ParamKind.choice,
                icon: const Icon(Icons.list_alt),
                label: Text(s('paramsKindChoice')),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() {
              _kind = v.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
          if (_kind == ParamKind.number)
            TextFormField(
              controller: _unit,
              decoration: InputDecoration(labelText: s('paramsUnit'), hintText: s('paramsUnitHint')),
            )
          else ...[
            TextFormField(
              controller: _choices,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: s('paramsChoices'), hintText: s('paramsChoicesHint')),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (choices.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(s('paramsOkChoices'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(s('paramsOkChoicesHint'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in choices)
                    FilterChip(
                      label: Text(c),
                      selected: _ok.contains(c),
                      selectedColor: Colors.green.withValues(alpha: 0.18),
                      onSelected: (on) => setState(() => on ? _ok.add(c) : _ok.remove(c)),
                    ),
                ],
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              onPressed: _save,
              child: Text(s('adminSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Formulaire d'un modèle : nom et paramètres cochés (dans l'ordre du
/// catalogue). [id] nul = nouveau modèle.
class _ProfileForm extends ConsumerStatefulWidget {
  final String? id;
  const _ProfileForm({this.id});

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late String _originalLabel;
  late List<String> _keys;
  String? _error;

  bool get _builtIn => widget.id != null && builtInPlantProfiles.containsKey(widget.id);

  String s(String key) => tr(ref.read(localeProvider), key);

  @override
  void initState() {
    super.initState();
    final id = widget.id;
    _originalLabel = id == null ? '' : plantProfileLabelKeys[id] ?? id;
    _label = TextEditingController(text: id == null ? '' : s(_originalLabel));
    _keys = id == null ? [] : [for (final p in paramsForProfile(id)) p.key];
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_keys.isEmpty) {
      setState(() => _error = s('pointsNoParam'));
      return;
    }
    final typed = _label.text.trim();
    // Nom inchangé : on garde la clé de traduction (modèle intégré).
    final label = widget.id != null && typed == s(_originalLabel) ? _originalLabel : typed;
    final plant = ref.read(plantControllerProvider);
    final existing = plant.profileDefs.where((d) => d.id == widget.id).firstOrNull;
    final ordered = [
      for (final p in plantParamCatalog)
        if (_keys.contains(p.key)) p.key,
    ];
    // Ordre : paramètres déjà présents d'abord (dans leur ordre), puis les
    // nouveaux dans l'ordre du catalogue.
    final current = widget.id == null ? <String>[] : [for (final p in paramsForProfile(widget.id!)) p.key];
    final keys = [...current.where(_keys.contains), ...ordered.where((k) => !current.contains(k))];
    await ref
        .read(plantControllerProvider.notifier)
        .saveProfile(
          PlantProfileDef(
            id: widget.id ?? '',
            label: label,
            paramKeys: keys,
            sortOrder: existing?.sortOrder ?? plant.profileDefs.length + 1,
          ),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('profilesSaved'))));
  }

  Future<void> _deleteOrReset() async {
    final controller = ref.read(plantControllerProvider.notifier);
    final id = widget.id!;
    if (!_builtIn) {
      final usage = controller.profileUsage(id);
      if (usage.isNotEmpty) {
        setState(() => _error = fill(s('profilesInUse'), {'list': usage.map(s).join(', ')}));
        return;
      }
    }
    final ok = await confirmDanger(
      context,
      title: s(_builtIn ? 'profilesResetTitle' : 'profilesDeleteTitle'),
      body: s(_builtIn ? 'profilesResetBody' : 'profilesDeleteBody'),
      confirm: s(_builtIn ? 'profilesReset' : 'schemaDeleteConfirm'),
      cancel: s('cancel'),
    );
    if (!ok) return;
    await controller.deleteProfile(id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plant = ref.watch(plantControllerProvider);
    final modified = plant.profileDefs.any((d) => d.id == widget.id);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s(widget.id == null ? 'profilesNew' : 'profilesEdit'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (widget.id != null && (!_builtIn || modified))
                IconButton(
                  tooltip: s(_builtIn ? 'profilesReset' : 'profilesDelete'),
                  onPressed: _deleteOrReset,
                  icon: Icon(_builtIn ? Icons.restart_alt : Icons.delete_outline, color: scheme.error),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _label,
            autofocus: widget.id == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: s('profilesName'), hintText: s('profilesNameHint')),
            validator: (v) => (v ?? '').trim().isEmpty ? s('paramsNameInvalid') : null,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(s('pointsParams'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              TextButton.icon(
                onPressed: () async {
                  final key = await showPlantParamForm(context);
                  if (key != null && mounted) setState(() => _keys.add(key));
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text(s('paramsAdd')),
              ),
            ],
          ),
          Text(s('profilesParamsHint'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in plantParamCatalog)
                SelectableEditableChip(
                  label: '${s(p.labelKey)}${p.unit.isEmpty ? '' : ' (${p.displayed().unit})'}',
                  selected: _keys.contains(p.key),
                  onSelected: (on) => setState(() {
                    _error = null;
                    on ? _keys.add(p.key) : _keys.remove(p.key);
                  }),
                  onEdit: !isCustomPlantParam(p.key)
                      ? null
                      : () async {
                          await showPlantParamForm(context, existing: p);
                          if (!mounted) return;
                          final validKeys = plantParamCatalog.map((e) => e.key).toSet();
                          setState(() => _keys.removeWhere((k) => !validKeys.contains(k)));
                        },
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              onPressed: _save,
              child: Text(s('adminSave'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
