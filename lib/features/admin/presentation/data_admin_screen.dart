import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/app_lock.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/data/stock_repository.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/excel_exporter.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/export_table.dart';
import '../../../core/export/report_tables.dart';
import '../../../core/import/analysis_importer.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/well.dart';
import '../../../core/plant/plant_catalog.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/app_loader.dart';
import '../../settings/presentation/settings_screen.dart' show SectionCard;

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Données : import CSV/Excel des analyses (téléphone ou PC), modèles de
/// fichier, export complet et sauvegarde de toutes les collections.
class DataAdminScreen extends ConsumerStatefulWidget {
  const DataAdminScreen({super.key});

  @override
  ConsumerState<DataAdminScreen> createState() => _DataAdminScreenState();
}

class _DataAdminScreenState extends ConsumerState<DataAdminScreen> {
  ImportPlan? _plan;
  String? _fileName;
  bool _busy = false;

  String s(String key) => tr(ref.read(localeProvider), key);

  Future<void> _pickFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final FilePickerResult? picked;
    try {
      picked = await LockGuard.run(
        () => FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['csv', 'xlsx', 'txt'],
          withData: true,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s('importReadError'))));
      return;
    }
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;
    setState(() => _busy = true);
    try {
      // Laisse s'afficher la fenêtre de chargement avant la lecture.
      final tables = await runWithLoading(context, s('loadingFile'), () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return readTables(file.name, bytes);
      });
      final settings = ref.read(appSettingsProvider);
      final profile = ref.read(profileProvider);
      final service = settings.defaultService == defaultServiceFromProfile
          ? (profile?.serviceKey ?? '')
          : settings.defaultService == defaultServiceNone
          ? ''
          : settings.defaultService;
      final importer = AnalysisImporter(
        wells: ref.read(wellsControllerProvider),
        plant: ref.read(plantControllerProvider),
        locale: ref.read(localeProvider),
        defaultService: service.isEmpty ? serviceKeys.first : service,
        operatorName: profile?.fullName ?? '',
      );
      setState(() {
        _fileName = file.name;
        _plan = importer.analyze(tables);
      });
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s('importReadError'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final plan = _plan;
    if (plan == null || plan.total == 0) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await runWithLoading(context, s('loadingImport'), () async {
        await AnalysisImporter.apply(plan);
        await ref.read(wellsControllerProvider.notifier).reload();
        await ref.read(plantControllerProvider.notifier).reload();
        await ref.read(stockControllerProvider.notifier).reload();
      });
      messenger.showSnackBar(SnackBar(content: Text(fill(s('importDone'), {'n': '${plan.total}'}))));
      setState(() {
        _plan = null;
        _fileName = null;
      });
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s('importFailed'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _template({required bool plant}) async {
    final locale = ref.read(localeProvider);
    final today = DateOnly(DateTime.now());
    final List<ExportTable> tables;
    if (plant) {
      final points = ref.read(plantControllerProvider).points.where((p) => p.active).toList();
      final params = <String, PlantParam>{
        for (final p in points)
          for (final param in p.params) param.key: param,
      }.values.toList();
      tables = [
        ExportTable(
          name: s('navPlant'),
          headers: [
            s('colDate'),
            s('plantColPoint'),
            for (final p in params) p.unit.isEmpty ? s(p.labelKey) : '${s(p.labelKey)} (${p.unit})',
            s('colComment'),
          ],
          rows: [
            for (final point in points.take(3)) [today, point.code, for (final _ in params) null, ''],
          ],
        ),
      ];
    } else {
      final data = ref.read(wellsControllerProvider);
      final wells = data.wells.where((w) => w.active).toList();
      final types = data.analysisTypes;
      tables = [
        ExportTable(
          name: s('importTemplateLong'),
          headers: [
            s('colDate'),
            s('colWell'),
            s('colType'),
            s('colValue'),
            s('colService'),
            s('colOperator'),
            s('colComment'),
          ],
          rows: [
            if (wells.isNotEmpty && types.isNotEmpty)
              [today, wells.first.code, types.first.label, 0.0, s(serviceKeys.first), '', ''],
          ],
        ),
        ExportTable(
          name: s('importTemplateWide'),
          headers: [
            s('colDate'),
            s('colWell'),
            for (final t in types) t.unit.isEmpty ? t.label : '${t.label} (${t.unit})',
          ],
          rows: [
            for (final w in wells.take(3)) [today, w.code, for (final _ in types) null],
          ],
        ),
      ];
    }
    final bytes = ExcelExporter.encode(tables);
    if (bytes == null || !mounted) return;
    await saveOrShareFile(
      context: context,
      locale: locale,
      baseName: plant ? 'modele_import_usine' : 'modele_import_puits',
      extension: 'xlsx',
      mimeType: _xlsxMime,
      bytes: bytes,
    );
  }

  Future<void> _exportAll() async {
    final locale = ref.read(localeProvider);
    final data = ref.read(wellsControllerProvider);
    final plant = ref.read(plantControllerProvider);
    final controller = ref.read(plantControllerProvider.notifier);
    final params = <String, PlantParam>{
      for (final p in plant.points)
        for (final param in p.params) param.key: param,
    }.values.toList();
    await runExport(
      context: context,
      locale: locale,
      baseName: 'puitstrack_donnees',
      tables: [
        ExportTable(
          name: s('navWells'),
          headers: [
            s('wellsManageCodeLabel'),
            s('wellsManageNameLabel'),
            s('wellsManageGroupLabel'),
            s('wellTypeLabel'),
            s('wellStatusLabel'),
            s('wellLatitude'),
            s('wellLongitude'),
          ],
          rows: [
            for (final w in data.wells)
              [w.code, w.name, w.group, s(wellTypeLabelKey(w.type)), s(w.status.labelKey), w.latitude, w.longitude],
          ],
        ),
        analysesTable(data, data.records, s, includeWell: true),
        interventionsTable(data, data.interventions, s),
        ExportTable(
          name: s('adminPoints'),
          headers: [s('pointsCode'), s('pointsName'), s('pointsCircuit'), s('pointsEquipment'), s('pointsParams')],
          rows: [
            for (final p in plant.points)
              [p.code, p.name, s(p.circuit.labelKey), p.equipment, p.params.map((x) => s(x.labelKey)).join(', ')],
          ],
        ),
        ExportTable(
          name: s('navPlant'),
          headers: [
            s('colDate'),
            s('plantColPoint'),
            for (final p in params) p.unit.isEmpty ? s(p.labelKey) : '${s(p.labelKey)} (${p.unit})',
            s('colOperator'),
            s('colComment'),
          ],
          rows: [
            for (final a in plant.analyses)
              [
                DateOnly(a.date),
                controller.point(a.pointId)?.code ?? a.pointId,
                for (final p in params)
                  p.isNumeric ? a.number(p.key) : (a.values[p.key] == null ? null : s('${a.values[p.key]}')),
                a.operatorName,
                a.comment ?? '',
              ],
          ],
        ),
        ExportTable(
          name: s('adminThresholds'),
          headers: [
            s('plantColPoint'),
            s('pointsParams'),
            s('thresholdsMin'),
            s('thresholdsMax'),
            s('thresholdsAlert'),
          ],
          rows: [
            for (final point in plant.points)
              for (final param in point.params)
                if (controller.threshold(point.id, param.key) case final t?)
                  [point.code, s(param.labelKey), t.min, t.max, s(t.alertEnabled ? 'yes' : 'no')],
          ],
        ),
      ],
    );
  }

  Future<void> _backup() async {
    final locale = ref.read(localeProvider);
    final bytes = await BackupService.encode();
    if (!mounted) return;
    await saveOrShareFile(
      context: context,
      locale: locale,
      baseName: BackupService.fileName(DateTime.now()).replaceAll('.json', ''),
      extension: 'json',
      mimeType: backupMimeType,
      bytes: bytes,
    );
    await ref.read(appSettingsProvider.notifier).markBackupDone(automatic: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String t(String key) => tr(locale, key);
    final plan = _plan;

    return Scaffold(
      appBar: AppBar(title: Text(t('adminData'))),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 40, maxWidth: 900),
        children: [
          SectionCard(
            title: t('importTitle'),
            icon: Icons.upload_file_rounded,
            children: [
              Text(t('importIntro'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
                  onPressed: _busy ? null : _pickFile,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.folder_open_rounded),
                  label: Text(t('importPick'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _template(plant: false),
                    icon: const Icon(Icons.grid_on_rounded, size: 18),
                    label: Text(t('importTemplateWells')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _template(plant: true),
                    icon: const Icon(Icons.grid_on_rounded, size: 18),
                    label: Text(t('importTemplatePlant')),
                  ),
                ],
              ),
              if (plan != null) ...[
                const Divider(height: 28),
                Text(_fileName ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CountChip(
                      icon: Icons.check_circle_outline,
                      color: Colors.green.shade600,
                      text: fill(t('importReady'), {'n': '${plan.total}'}),
                    ),
                    if (plan.duplicates > 0)
                      _CountChip(
                        icon: Icons.content_copy_rounded,
                        color: scheme.onSurfaceVariant,
                        text: fill(t('importDuplicates'), {'n': '${plan.duplicates}'}),
                      ),
                    if (plan.issues.isNotEmpty)
                      _CountChip(
                        icon: Icons.error_outline,
                        color: scheme.error,
                        text: fill(t('importIssues'), {'n': '${plan.issues.length}'}),
                      ),
                  ],
                ),
                if (plan.total > 0) ...[
                  const SizedBox(height: 12),
                  Text(t('importPreview'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final row in plan.preview(locale))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        row.join('  ·  '),
                        style: const TextStyle(fontSize: 12.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                if (plan.issues.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    t('importIssuesTitle'),
                    style: TextStyle(fontWeight: FontWeight.w700, color: scheme.error),
                  ),
                  const SizedBox(height: 6),
                  for (final issue in plan.issues.take(12))
                    Text(
                      '${issue.table} · ${t('importLine')} ${issue.line} : ${t(issue.messageKey)}'
                      '${issue.detail.isEmpty ? '' : ' (${issue.detail})'}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  if (plan.issues.length > 12)
                    Text(
                      '… +${plan.issues.length - 12}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
                        onPressed: _busy || plan.total == 0 ? null : _import,
                        icon: const Icon(Icons.download_done_rounded),
                        label: Text(fill(t('importConfirm'), {'n': '${plan.total}'})),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(onPressed: () => setState(() => _plan = null), child: Text(t('cancel'))),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: t('exportAllTitle'),
            icon: Icons.table_view_rounded,
            children: [
              Text(t('exportAllHint'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _exportAll,
                icon: const Icon(Icons.download_outlined),
                label: Text(t('exportAllAction')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: t('settingsBackup'),
            icon: Icons.backup_outlined,
            children: [
              Text(t('backupAllHint'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _backup,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: Text(t('backupAllAction')),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.settings_backup_restore),
                    label: Text(t('backupRestore')),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _CountChip({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(100)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
      ],
    ),
  );
}
