import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/stock_repository.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/export/export_service.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/qr/qr_labels_pdf.dart';
import '../../../core/qr/qr_links.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../setup/presentation/qr_scan_screen.dart';

/// Scan d'un QR code du terrain (ouvre la saisie du puits, du point ou
/// l'article de stock) et impression des étiquettes à coller.
class QrScreen extends ConsumerStatefulWidget {
  const QrScreen({super.key});

  @override
  ConsumerState<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends ConsumerState<QrScreen> {
  final _kinds = {...QrKind.values};

  String _kindLabel(String Function(String) s, QrKind kind) => switch (kind) {
    QrKind.well => s('qrKindWell'),
    QrKind.point => s('qrKindPoint'),
    QrKind.stock => s('qrKindStock'),
  };

  Future<void> scan() async {
    final locale = ref.read(localeProvider);
    String s(String k) => tr(locale, k);
    final role = ref.read(currentRoleProvider);
    final code = await scanQrCode(context);
    if (code == null || !mounted) return;
    final route = routeForQr(code, canEnter: role.canEnterData, todayKey: plantDateKey(DateTime.now()));
    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('qrUnknown'))));
      return;
    }
    context.push(route);
  }

  Future<void> printLabels() async {
    final locale = ref.read(localeProvider);
    String s(String k) => tr(locale, k);
    final data = ref.read(wellsControllerProvider);
    final plant = ref.read(plantControllerProvider);
    final stock = ref.read(stockControllerProvider);
    final labels = [
      if (_kinds.contains(QrKind.well))
        for (final w in data.wells.where((w) => w.active))
          QrLabel(kind: QrKind.well, id: w.id, title: w.name, subtitle: w.code),
      if (_kinds.contains(QrKind.point))
        for (final p in plant.points.where((p) => p.active))
          QrLabel(kind: QrKind.point, id: p.id, title: p.name, subtitle: p.code),
      if (_kinds.contains(QrKind.stock))
        for (final i in stock.items) QrLabel(kind: QrKind.stock, id: i.id, title: i.name, subtitle: i.category),
    ];
    if (labels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('qrNothing'))));
      return;
    }
    final bytes = await buildQrLabelsPdf(
      labels: labels,
      title: s('qrLabelsTitle'),
      kindLabel: (k) => _kindLabel(s, k),
    );
    if (!mounted) return;
    await saveOrShareFile(
      context: context,
      locale: locale,
      baseName: 'etiquettes_qr',
      extension: 'pdf',
      mimeType: 'application/pdf',
      bytes: bytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String k) => tr(locale, k);

    return Scaffold(
      appBar: AppBar(title: Text(s('qrTitle'))),
      body: ListView(
        padding: pagePadding(context, top: 16, bottom: 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.qr_code_scanner, color: accentColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s('qrScanTitle'),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(s('qrScanBody'), style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: canScanQrCode ? scan : null,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(canScanQrCode ? s('qrScanButton') : s('qrScanPhoneOnly')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.qr_code_2, color: accentColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s('qrLabelsTitle'),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(s('qrLabelsBody'), style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final kind in QrKind.values)
                        FilterChip(
                          label: Text(_kindLabel(s, kind)),
                          selected: _kinds.contains(kind),
                          onSelected: (on) => setState(() => on ? _kinds.add(kind) : _kinds.remove(kind)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: _kinds.isEmpty ? null : printLabels,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(s('qrLabelsButton')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
