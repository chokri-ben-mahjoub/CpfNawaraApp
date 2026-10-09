import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/auth/app_lock.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/sync/firebase_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../qr_scan_screen.dart';

/// Ouvre un lien (console Firebase...) dans le navigateur.
Future<void> openExternalLink(String url) async {
  try {
    await LockGuard.run(() => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
  } catch (_) {
    // Pas de navigateur disponible : sans conséquence.
  }
}

/// Choix du projet Firebase : projet intégré (un clic), configuration collée
/// depuis la console, ou QR code affiché par l'administrateur.
class FirebaseProjectPicker extends ConsumerStatefulWidget {
  final ValueChanged<FirebaseRestConfig> onSelected;

  /// Propose le projet PuitsTrack intégré à l'app.
  final bool showBuiltIn;

  const FirebaseProjectPicker({super.key, required this.onSelected, this.showBuiltIn = true});

  @override
  ConsumerState<FirebaseProjectPicker> createState() => _FirebaseProjectPickerState();
}

class _FirebaseProjectPickerState extends ConsumerState<FirebaseProjectPicker> {
  final _text = TextEditingController();
  bool _showPaste = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String s(String key) => tr(ref.read(localeProvider), key);

  void _apply(String raw) {
    final config = FirebaseRestConfig.parse(raw);
    if (config == null) {
      setState(() => _error = s('setupConfigInvalid'));
      return;
    }
    setState(() => _error = null);
    widget.onSelected(config);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    _text.text = text;
    setState(() => _showPaste = true);
    _apply(text);
  }

  Future<void> _scan() async {
    final value = await scanQrCode(context);
    if (value == null || !mounted) return;
    _apply(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String t(String key) => tr(locale, key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showBuiltIn) ...[
          _ChoiceTile(
            icon: Icons.bolt_rounded,
            title: t('setupBuiltInTitle'),
            subtitle: fill(t('setupBuiltInBody'), {'project': FirebaseRestConfig.builtIn.projectId}),
            highlighted: true,
            onTap: () => widget.onSelected(FirebaseRestConfig.builtIn),
          ),
          const SizedBox(height: 10),
        ],
        if (canScanQrCode) ...[
          _ChoiceTile(
            icon: Icons.qr_code_scanner_rounded,
            title: t('setupScanTitle'),
            subtitle: t('setupScanBody'),
            onTap: _scan,
          ),
          const SizedBox(height: 10),
        ],
        _ChoiceTile(
          icon: Icons.content_paste_rounded,
          title: t('setupPasteTitle'),
          subtitle: t('setupPasteBody'),
          onTap: () => setState(() => _showPaste = !_showPaste),
        ),
        if (_showPaste) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 5,
            maxLines: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            decoration: InputDecoration(hintText: t('setupPasteHint'), errorText: _error, errorMaxLines: 3),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_go_outlined),
                  label: Text(t('setupPasteClipboard')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
                  onPressed: () => _apply(_text.text),
                  icon: const Icon(Icons.check),
                  label: Text(t('setupPasteApply')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(t('setupPasteWhere'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.35)),
        ] else if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: highlighted ? accentColor.withValues(alpha: 0.08) : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: highlighted ? accentColor.withValues(alpha: 0.5) : scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.3)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
