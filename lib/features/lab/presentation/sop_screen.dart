import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_lock.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/export/share_files.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/lab/sop_repository.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../admin/presentation/widgets/admin_widgets.dart';

/// Procédures d'analyse (SOP) : liste de PDF consultables par tous, ajoutés
/// et modifiés par l'admin, l'ingénieur et l'opérateur.
class SopScreen extends ConsumerStatefulWidget {
  const SopScreen({super.key});

  @override
  ConsumerState<SopScreen> createState() => _SopScreenState();
}

class _SopScreenState extends ConsumerState<SopScreen> {
  String _query = '';

  Future<void> _open(Sop sop) async {
    await shareFiles([ShareableFile(sop.fileName, 'application/pdf', base64Decode(sop.data))]);
  }

  Future<void> _edit([Sop? existing]) async {
    await showDialog<void>(context: context, builder: (_) => _SopDialog(existing: existing));
  }

  Future<void> _delete(Sop sop, String Function(String) s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s('sopDeleteTitle')),
        content: Text(sop.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s('sopDelete'))),
        ],
      ),
    );
    if (ok == true) await ref.read(sopControllerProvider.notifier).delete(sop.id);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final role = ref.watch(currentRoleProvider);
    final canEdit = role.canManageOps;
    final all = ref.watch(sopControllerProvider);
    final q = _query.trim().toLowerCase();
    final sops = q.isEmpty
        ? all
        : all.where((e) => e.title.toLowerCase().contains(q) || e.category.toLowerCase().contains(q)).toList();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(s('sopTitle'))),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(onPressed: _edit, icon: const Icon(Icons.add), label: Text(s('sopAdd')))
          : null,
      body: all.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_outlined, size: 56, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(s(canEdit ? 'sopEmpty' : 'sopEmptyReader'), textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : ListView(
              padding: pagePadding(context, top: 12, bottom: 100),
              children: [
                TextField(
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s('sopSearch')),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                for (final sop in sops)
                  Card(
                    child: ListTile(
                      leading: const IconBadge(Icons.picture_as_pdf_outlined, color: accentColor),
                      title: Text(sop.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        [if (sop.category.isNotEmpty) sop.category, sop.fileName].join(' · '),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _open(sop),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(tooltip: s('sopOpen'), icon: const Icon(Icons.open_in_new), onPressed: () => _open(sop)),
                          if (canEdit)
                            PopupMenuButton<String>(
                              onSelected: (v) => v == 'edit' ? _edit(sop) : _delete(sop, s),
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'edit', child: Text(s('sopEdit'))),
                                PopupMenuItem(value: 'delete', child: Text(s('sopDelete'))),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (sops.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(s('sopNoResult')))),
              ],
            ),
    );
  }
}

class _SopDialog extends ConsumerStatefulWidget {
  final Sop? existing;
  const _SopDialog({this.existing});

  @override
  ConsumerState<_SopDialog> createState() => _SopDialogState();
}

class _SopDialogState extends ConsumerState<_SopDialog> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _category = TextEditingController(text: widget.existing?.category ?? '');
  String? _data;
  String? _fileName;
  String? _error;

  @override
  void initState() {
    super.initState();
    _data = widget.existing?.data;
    _fileName = widget.existing?.fileName;
  }

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _pick(String Function(String) s) async {
    FilePickerResult? picked;
    try {
      picked = await LockGuard.run(
        () => FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'], withData: true),
      );
    } catch (_) {
      return;
    }
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    // Limite Firestore (~1 Mo par champ) : base64 = 4/3 de la taille du fichier.
    if (bytes.length > 700 * 1024) {
      setState(() => _error = s('stockAttachmentTooBig'));
      return;
    }
    setState(() {
      _data = base64Encode(bytes);
      _fileName = file.name;
      _error = null;
      if (_title.text.trim().isEmpty) _title.text = file.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    });
  }

  Future<void> _save(String Function(String) s) async {
    if (_title.text.trim().isEmpty || _data == null || _fileName == null) {
      setState(() => _error = s('sopNeedFile'));
      return;
    }
    await ref.read(sopControllerProvider.notifier).save(
      id: widget.existing?.id,
      title: _title.text.trim(),
      category: _category.text.trim(),
      fileName: _fileName!,
      data: _data!,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    return AlertDialog(
      title: Text(s(widget.existing == null ? 'sopAdd' : 'sopEdit')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _title, decoration: InputDecoration(labelText: s('sopFieldTitle'))),
              const SizedBox(height: 12),
              TextField(controller: _category, decoration: InputDecoration(labelText: s('sopFieldCategory'))),
              const SizedBox(height: 12),
              if (_fileName == null)
                OutlinedButton.icon(
                  onPressed: () => _pick(s),
                  icon: const Icon(Icons.attach_file_outlined),
                  label: Text(s('sopPickPdf')),
                )
              else
                InputChip(
                  avatar: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(_fileName!, overflow: TextOverflow.ellipsis),
                  onPressed: () => _pick(s),
                  onDeleted: () => setState(() {
                    _data = null;
                    _fileName = null;
                  }),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s('cancel'))),
        FilledButton(onPressed: () => _save(s), child: Text(s('sopSave'))),
      ],
    );
  }
}
