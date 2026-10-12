import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/sync/sync_service.dart';
import '../../core/team/team_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/responsive.dart';
import '../setup/presentation/widgets/team_account_form.dart';

/// Écran du propriétaire de PuitsTrack (Réglages › Clients) : codes
/// d'activation vendus aux clients et entreprises créées.
class OwnerScreen extends ConsumerStatefulWidget {
  const OwnerScreen({super.key});

  @override
  ConsumerState<OwnerScreen> createState() => _OwnerScreenState();
}

class _OwnerScreenState extends ConsumerState<OwnerScreen> {
  bool? _verified;
  bool _busy = false;
  String? _error;
  List<ActivationCode> _codes = const [];
  List<Company> _companies = const [];

  String s(String key) => tr(ref.read(localeProvider), key);

  SyncController get _controller => ref.read(syncControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => _error = s(teamErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final verified = await _controller.ownerVerified();
    var codes = const <ActivationCode>[];
    var companies = const <Company>[];
    if (verified) {
      final team = _controller.team!;
      final session = await _controller.freshSession();
      codes = await team.listActivationCodes(session);
      companies = await team.listCompanies(session);
    }
    if (!mounted) return;
    setState(() {
      _verified = verified;
      _codes = codes;
      _companies = companies;
    });
  });

  Future<void> _sendVerification() => _run(() async {
    await _controller.sendOwnerVerification();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('ownerVerifySent'))));
  });

  Future<void> _newCode() async {
    final label = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s('ownerNewCode')),
        content: TextField(
          controller: label,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: s('ownerClientName'), hintText: s('ownerClientNameHint')),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(s('cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(label.text), child: Text(s('ownerCreate'))),
        ],
      ),
    );
    label.dispose();
    if (name == null || name.trim().isEmpty) return;
    ActivationCode? created;
    await _run(() async {
      created = await _controller.team!.createActivationCode(await _controller.freshSession(), name.trim());
    });
    if (created == null || !mounted) return;
    await _load();
    if (mounted) await _showCode(created!);
  }

  String _message(ActivationCode code) => fill(s('ownerCodeMessage'), {'code': code.displayCode});

  Future<void> _showCode(ActivationCode code) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(code.label),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            code.displayCode,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 3),
          ),
          const SizedBox(height: 12),
          Text(s('ownerCodeHowTo'), textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _message(code)));
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(s('inviteCopied'))));
            }
          },
          icon: const Icon(Icons.copy),
          label: Text(s('ownerCopy')),
        ),
        FilledButton.icon(
          onPressed: () => Share.share(_message(code)),
          icon: const Icon(Icons.share),
          label: Text(s('exportActionShare')),
        ),
      ],
    ),
  );

  Future<void> _delete(ActivationCode code) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s('ownerDeleteTitle')),
        content: Text(fill(s('ownerDeleteBody'), {'code': code.displayCode, 'client': code.label})),
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
    if (ok != true) return;
    await _run(() async => _controller.team!.deleteActivationCode(await _controller.freshSession(), code.code));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final sync = ref.watch(syncControllerProvider);
    final dateFormat = DateFormat('d MMM yyyy', locale.languageCode);
    final companiesById = {for (final c in _companies) c.id: c};
    final available = _codes.where((c) => !c.used).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(s('ownerTitle')),
        actions: [IconButton(tooltip: s('syncNow'), onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: _verified == true
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _newCode,
              icon: const Icon(Icons.add),
              label: Text(s('ownerNewCode')),
            )
          : null,
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 120),
        children: [
          if (_busy) const LinearProgressIndicator(),
          Text(
            fill(s('ownerIntro'), {'email': sync.email ?? ''}),
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
              ),
            ),
          if (_verified == false)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mark_email_unread_outlined, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s('ownerVerifyTitle'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(s('ownerVerifyBody'), style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
                      onPressed: _busy ? null : _sendVerification,
                      icon: const Icon(Icons.send),
                      label: Text(s('ownerVerifySend')),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _load,
                      icon: const Icon(Icons.check),
                      label: Text(s('ownerVerifyDone')),
                    ),
                  ],
                ),
              ),
            ),
          if (_verified == true) ...[
            Row(
              children: [
                for (final (label, value) in [
                  (s('ownerStatCompanies'), _companies.length),
                  (s('ownerStatAvailable'), available),
                  (s('ownerStatUsed'), _codes.length - available),
                ])
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        child: Column(
                          children: [
                            Text(
                              '$value',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: accentColor),
                            ),
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(s('ownerCodes'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            if (_codes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(s('ownerNoCode'), style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            for (final code in _codes)
              Card(
                child: ListTile(
                  leading: Icon(
                    code.used ? Icons.check_circle : Icons.vpn_key_outlined,
                    color: code.used ? Colors.green.shade600 : accentColor,
                  ),
                  title: Text(code.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    code.used
                        ? fill(s('ownerCodeUsed'), {
                            'company': companiesById[code.companyId]?.name ?? code.companyId,
                            'date': code.usedAt == null ? '' : dateFormat.format(code.usedAt!),
                          })
                        : '${code.displayCode} · ${s('ownerCodeAvailable')}',
                  ),
                  trailing: code.used
                      ? null
                      : IconButton(
                          tooltip: s('ownerDeleteTitle'),
                          onPressed: _busy ? null : () => _delete(code),
                          icon: Icon(Icons.delete_outline, color: scheme.error),
                        ),
                  onTap: code.used ? null : () => _showCode(code),
                ),
              ),
            const SizedBox(height: 16),
            Text(s('ownerCompanies'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            for (final company in _companies)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: Text(company.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    _codes.where((c) => c.companyId == company.id).map((c) => c.label).firstOrNull ??
                        s('ownerCompanyNoCode'),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
