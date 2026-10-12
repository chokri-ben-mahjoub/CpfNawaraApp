import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/app_lock.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/plant/schema_image.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/responsive.dart';
import 'widgets/plant_diagram.dart';

IconData plantSchemaIcon(PlantSchemaKind kind) => switch (kind) {
  PlantSchemaKind.pfd => Icons.account_tree_outlined,
  PlantSchemaKind.image => Icons.image_outlined,
  PlantSchemaKind.blank => Icons.grid_4x4,
};

/// Choisit une image (photo, scan, capture du PFD) et la compresse pour un
/// schéma. `null` si annulé ; un message explique l'échec éventuel.
Future<SchemaImage?> pickSchemaImage(BuildContext context, String Function(String) s) async {
  final messenger = ScaffoldMessenger.of(context);
  FilePickerResult? picked;
  try {
    picked = await LockGuard.run(() => FilePicker.platform.pickFiles(type: FileType.image, withData: true));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(s('schemaImageError'))));
    return null;
  }
  final bytes = picked?.files.single.bytes;
  if (bytes == null || !context.mounted) return null;
  final image = await runWithLoading(context, s('schemaImageLoading'), () => compute(compressSchemaImage, bytes));
  if (image == null) messenger.showSnackBar(SnackBar(content: Text(s('schemaImageError'))));
  return image;
}

/// Ajoute un schéma (image importée ou fond quadrillé) puis ouvre sa
/// configuration pour y placer les points.
Future<void> addPlantSchema(BuildContext context, WidgetRef ref) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final nameController = TextEditingController();
  final kind = await showDialog<PlantSchemaKind>(
    context: context,
    builder: (dialogContext) {
      void submit(PlantSchemaKind k) {
        if (nameController.text.trim().isEmpty) return;
        Navigator.of(dialogContext).pop(k);
      }

      return AlertDialog(
        title: Text(s('schemaAdd')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: s('schemaName'), hintText: s('schemaNameHint')),
              ),
              const SizedBox(height: 16),
              Text(s('schemaKindTitle'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: Text(s('schemaKindImage')),
                subtitle: Text(s('schemaKindImageHint')),
                onTap: () => submit(PlantSchemaKind.image),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.grid_4x4),
                title: Text(s('schemaKindBlank')),
                subtitle: Text(s('schemaKindBlankHint')),
                onTap: () => submit(PlantSchemaKind.blank),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(s('cancel')))],
      );
    },
  );
  final name = nameController.text.trim();
  nameController.dispose();
  if (kind == null || name.isEmpty || !context.mounted) return;
  SchemaImage? image;
  if (kind == PlantSchemaKind.image) {
    image = await pickSchemaImage(context, s);
    if (image == null) return;
  }
  final id = await ref
      .read(plantControllerProvider.notifier)
      .saveSchema(
        PlantSchema(
          id: '',
          name: name,
          kind: kind,
          image: image?.base64,
          imageWidth: image?.width,
          imageHeight: image?.height,
        ),
      );
  ref.read(plantSchemaIdProvider.notifier).state = id;
  if (context.mounted) await context.push('/plant/schema/$id');
}

/// Administration › Schémas de l'usine : liste, ajout, accès à la
/// configuration de chaque schéma.
class PlantSchemasScreen extends ConsumerWidget {
  const PlantSchemasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final plant = ref.watch(plantControllerProvider);
    String s(String key) => tr(locale, key);
    final active = plant.points.where((p) => p.active).toList();

    return Scaffold(
      appBar: AppBar(title: Text(s('adminSchemas'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addPlantSchema(context, ref),
        icon: const Icon(Icons.add),
        label: Text(s('schemaAdd')),
      ),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 130),
        children: [
          Text(s('schemasIntro'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
          const SizedBox(height: 12),
          for (final schema in plant.visibleSchemas)
            Card(
              child: ListTile(
                leading: Icon(plantSchemaIcon(schema.kind), color: scheme.primary),
                title: Text(s(schema.name), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  fill(s('schemaPlacedCount'), {
                    'n': '${active.where((p) => schema.positionOf(p) != null).length}',
                    'total': '${active.length}',
                  }),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/plant/schema/${schema.id}'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Configuration d'un schéma : glisser les points pour les placer, ajouter
/// ceux qui manquent, retirer, renommer, changer l'image, supprimer.
class PlantSchemaEditorScreen extends ConsumerStatefulWidget {
  final String schemaId;
  const PlantSchemaEditorScreen({super.key, required this.schemaId});

  @override
  ConsumerState<PlantSchemaEditorScreen> createState() => _PlantSchemaEditorScreenState();
}

class _PlantSchemaEditorScreenState extends ConsumerState<PlantSchemaEditorScreen> {
  PlantSchema? _schema;
  final _positions = <String, Offset?>{};
  String? _selected;
  String? _pending;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final schema = ref.read(plantControllerProvider.notifier).schema(widget.schemaId);
    _schema = schema;
    if (schema != null) _positions.addAll(schema.positions);
  }

  String s(String key) => tr(ref.read(localeProvider), key);

  void _change(VoidCallback update) => setState(() {
    update();
    _dirty = true;
  });

  Future<void> _save() async {
    final schema = _schema;
    if (schema == null) return;
    await ref.read(plantControllerProvider.notifier).saveSchema(schema.copyWith(positions: Map.of(_positions)));
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('schemaSaved'))));
    context.pop();
  }

  Future<void> _rename() async {
    final schema = _schema!;
    final controller = TextEditingController(text: s(schema.name));
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s('schemaRename')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: s('schemaName')),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(s('cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: Text(s('adminSave'))),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    _change(() => _schema = schema.copyWith(name: name.trim()));
  }

  Future<void> _changeImage() async {
    final image = await pickSchemaImage(context, s);
    if (image == null) return;
    _change(() => _schema = _schema!.copyWith(image: image.base64, imageWidth: image.width, imageHeight: image.height));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s('schemaDeleteTitle')),
        content: Text(fill(s('schemaDeleteBody'), {'name': s(_schema!.name)})),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s('schemaDeleteConfirm')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final deleted = await ref.read(plantControllerProvider.notifier).deleteSchema(_schema!.id);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('schemaDeleteLast'))));
      return;
    }
    ref.read(plantSchemaIdProvider.notifier).state = null;
    setState(() => _dirty = false);
    context.pop();
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(s('schemaDiscardTitle')),
          content: Text(s('schemaDiscardBody')),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s('cancel'))),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(s('schemaDiscard'))),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    ref.watch(localeProvider);
    final plant = ref.watch(plantControllerProvider);
    final day = ref.watch(plantDayProvider);
    final schema = _schema;
    if (schema == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(s('schemaNotFound'))),
      );
    }
    final shown = schema.copyWith(positions: _positions);
    final active = plant.points.where((p) => p.active).toList();
    final unplaced = active.where((p) => shown.positionOf(p) == null).toList();
    SamplePoint? selected;
    for (final p in active) {
      if (p.id == _selected) selected = p;
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          setState(() => _dirty = false);
          if (context.mounted) context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(s(schema.name)),
          actions: [
            IconButton(tooltip: s('schemaRename'), onPressed: _rename, icon: const Icon(Icons.edit_outlined)),
            if (schema.kind == PlantSchemaKind.image)
              IconButton(
                tooltip: s('schemaChangeImage'),
                onPressed: _changeImage,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'reset') _change(_positions.clear);
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => [
                if (schema.kind == PlantSchemaKind.pfd) PopupMenuItem(value: 'reset', child: Text(s('schemaReset'))),
                PopupMenuItem(value: 'delete', child: Text(s('schemaDelete'))),
              ],
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(s('adminSave')),
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _pending != null ? s('schemaPlaceHint') : s('schemaEditHint'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: _pending != null ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: _pending != null ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 8),
              // Pas de défilement autour du schéma : le glisser des points ne
              // doit pas être pris pour un défilement de la page.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = schema.canvasSize;
                    final width = [
                      constraints.maxWidth,
                      constraints.maxHeight * size.width / size.height,
                    ].reduce((a, b) => a < b ? a : b);
                    return Center(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: PlantSchemaCanvas(
                          schema: schema,
                          day: day,
                          width: width,
                          positions: _positions,
                          selectedId: _selected,
                          onMarkerTap: (p) => setState(() {
                            _pending = null;
                            _selected = _selected == p.id ? null : p.id;
                          }),
                          onMarkerMoved: (p, pos) => _change(() {
                            _positions[p.id] = pos;
                            _selected = p.id;
                          }),
                          onBackgroundTap: (pos) {
                            final pending = _pending;
                            if (pending == null) {
                              setState(() => _selected = null);
                              return;
                            }
                            _change(() {
                              _positions[pending] = pos;
                              _selected = pending;
                              _pending = null;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (selected != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _change(() {
                        _positions[selected!.id] = null;
                        _selected = null;
                      }),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: Text(s('schemaRemovePoint')),
                    ),
                  ],
                ),
              Text(
                unplaced.isEmpty ? s('schemaAllPlaced') : fill(s('schemaUnplaced'), {'n': '${unplaced.length}'}),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              if (unplaced.isNotEmpty)
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final p in unplaced)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            selected: _pending == p.id,
                            avatar: CircleAvatar(backgroundColor: p.circuit.color, radius: 6),
                            label: Text(p.code),
                            tooltip: p.name,
                            onSelected: (on) => setState(() {
                              _pending = on ? p.id : null;
                              _selected = null;
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
