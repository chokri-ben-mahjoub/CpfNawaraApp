import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/export/download_saver.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/share_files.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/platform/app_platform.dart';

/// Destinataire enregistré du rapport (e-mail et/ou WhatsApp).
class ReportRecipient {
  final String name;
  final String email;
  final String phone;
  const ReportRecipient({required this.name, this.email = '', this.phone = ''});

  Map<String, Object?> toJson() => {'name': name, 'email': email, 'phone': phone};

  static ReportRecipient fromJson(Map<String, Object?> j) =>
      ReportRecipient(name: '${j['name'] ?? ''}', email: '${j['email'] ?? ''}', phone: '${j['phone'] ?? ''}');

  /// Numéro au format international sans « + » ni espaces (lien wa.me).
  String get whatsappNumber {
    var digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+')) digits = digits.substring(1);
    if (digits.startsWith('00')) digits = digits.substring(2);
    return digits;
  }
}

/// Liste des destinataires, enregistrée sur l'appareil.
class RecipientsController extends StateNotifier<List<ReportRecipient>> {
  RecipientsController() : super(const []) {
    _load();
  }

  static const _key = 'report_recipients';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      state = [
        for (final item in jsonDecode(raw) as List) ReportRecipient.fromJson(Map<String, Object?>.from(item as Map)),
      ];
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([for (final r in state) r.toJson()]));
    } catch (_) {}
  }

  Future<void> add(ReportRecipient r) async {
    state = [...state, r];
    await _save();
  }

  Future<void> remove(ReportRecipient r) async {
    state = state.where((x) => x != r).toList();
    await _save();
  }
}

final reportRecipientsProvider = StateNotifierProvider<RecipientsController, List<ReportRecipient>>(
  (ref) => RecipientsController(),
);

/// Affiche la feuille « Rapport prêt » : choix des destinataires enregistrés,
/// envoi par e-mail ou WhatsApp, ou enregistrement / partage classique.
Future<void> showReportSendSheet({
  required BuildContext context,
  required Locale locale,
  required String fileName,
  required List<int> bytes,
  required String subject,
  required String body,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _ReportSendSheet(locale: locale, fileName: fileName, bytes: bytes, subject: subject, body: body),
  );
}

class _ReportSendSheet extends ConsumerStatefulWidget {
  final Locale locale;
  final String fileName;
  final List<int> bytes;
  final String subject;
  final String body;
  const _ReportSendSheet({
    required this.locale,
    required this.fileName,
    required this.bytes,
    required this.subject,
    required this.body,
  });

  @override
  ConsumerState<_ReportSendSheet> createState() => _ReportSendSheetState();
}

class _ReportSendSheetState extends ConsumerState<_ReportSendSheet> {
  final _selected = <ReportRecipient>{};
  bool _busy = false;
  bool _initialized = false;

  String s(String key) => tr(widget.locale, key);

  String get _sizeText {
    final kb = widget.bytes.length / 1024;
    return kb >= 1024 ? '${(kb / 1024).toStringAsFixed(1)} Mo' : '${kb.toStringAsFixed(0)} Ko';
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<String> _writeTempFile() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${widget.fileName}';
    await File(path).writeAsBytes(widget.bytes, flush: true);
    return path;
  }

  /// Sur le web et le PC, on ne peut pas joindre un fichier à un lien : le
  /// PDF est enregistré (téléchargement) pour que l'utilisateur le joigne.
  Future<void> _saveForManualAttach() async {
    try {
      await DownloadSaver.save(fileName: widget.fileName, mimeType: 'application/pdf', bytes: widget.bytes);
    } catch (_) {}
  }

  Future<void> _sendEmail() async {
    final to = [for (final r in _selected) if (r.email.trim().isNotEmpty) r.email.trim()];
    if (to.isEmpty) {
      _toast(s('reportNoEmailSelected'));
      return;
    }
    setState(() => _busy = true);
    try {
      if (isAndroid || isIOS) {
        final path = await _writeTempFile();
        await FlutterEmailSender.send(
          Email(recipients: to, subject: widget.subject, body: widget.body, attachmentPaths: [path]),
        );
      } else {
        await _saveForManualAttach();
        final uri = Uri(
          scheme: 'mailto',
          path: to.join(','),
          query: 'subject=${Uri.encodeComponent(widget.subject)}&body=${Uri.encodeComponent('${widget.body}\n\n${s('reportAttachHint')}')}',
        );
        await launchUrl(uri);
        _toast(s('reportAttachHint'));
      }
    } catch (_) {
      _toast(s('reportSendError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendWhatsApp() async {
    final withPhone = _selected.where((r) => r.whatsappNumber.isNotEmpty).toList();
    setState(() => _busy = true);
    try {
      if (isAndroid || isIOS) {
        // Le volet de partage joint le PDF ; on y choisit WhatsApp puis le
        // contact (WhatsApp n'accepte pas de fichier via un simple lien).
        await shareFiles([ShareableFile(widget.fileName, 'application/pdf', widget.bytes)], subject: widget.subject);
      } else {
        await _saveForManualAttach();
        final number = withPhone.isEmpty ? '' : withPhone.first.whatsappNumber;
        final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(widget.body)}');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _toast(s('reportAttachHint'));
      }
    } catch (_) {
      _toast(s('reportSendError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveOrShare() async {
    await saveOrShareFile(
      context: context,
      locale: widget.locale,
      baseName: widget.fileName.replaceAll('.pdf', ''),
      extension: 'pdf',
      mimeType: 'application/pdf',
      bytes: widget.bytes,
      shareSubject: widget.subject,
    );
  }

  Future<void> _addRecipient() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final created = await showDialog<ReportRecipient>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s('reportAddRecipient')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: InputDecoration(labelText: s('reportRecipientName'))),
              const SizedBox(height: 10),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: s('reportRecipientEmail'), prefixIcon: const Icon(Icons.mail_outline)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: s('reportRecipientPhone'),
                  hintText: '+216 …',
                  prefixIcon: const Icon(Icons.chat_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(s('cancel'))),
          FilledButton(
            onPressed: () {
              final n = name.text.trim();
              final e = email.text.trim();
              final p = phone.text.trim();
              if (n.isEmpty || (e.isEmpty && p.isEmpty)) return;
              Navigator.of(dialogContext).pop(ReportRecipient(name: n, email: e, phone: p));
            },
            child: Text(s('ok')),
          ),
        ],
      ),
    );
    name.dispose();
    email.dispose();
    phone.dispose();
    if (created != null) {
      await ref.read(reportRecipientsProvider.notifier).add(created);
      setState(() => _selected.add(created));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recipients = ref.watch(reportRecipientsProvider);
    if (!_initialized && recipients.isNotEmpty) {
      _initialized = true;
      _selected.addAll(recipients);
    }
    const whatsapp = Color(0xFF25D366);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.primary.withValues(alpha: 0.72)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s('reportReadyTitle'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.fileName} · $_sizeText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(s('reportRecipients'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              TextButton.icon(
                onPressed: _addRecipient,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(s('reportAddRecipient')),
              ),
            ],
          ),
          if (recipients.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
              child: Text(
                s('reportNoRecipients'),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.4),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in recipients)
                  InputChip(
                    avatar: CircleAvatar(
                      backgroundColor: scheme.primary.withValues(alpha: 0.15),
                      child: Text(
                        r.name.isEmpty ? '?' : r.name[0].toUpperCase(),
                        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                    label: Text(r.name),
                    tooltip: [if (r.email.isNotEmpty) r.email, if (r.phone.isNotEmpty) r.phone].join(' · '),
                    selected: _selected.contains(r),
                    showCheckmark: false,
                    onSelected: (v) => setState(() => v ? _selected.add(r) : _selected.remove(r)),
                    onDeleted: () async {
                      _selected.remove(r);
                      await ref.read(reportRecipientsProvider.notifier).remove(r);
                    },
                  ),
              ],
            ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : _sendEmail,
              icon: const Icon(Icons.mail_rounded),
              label: Text(s('reportSendEmail'), style: const TextStyle(fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : _sendWhatsApp,
              icon: const Icon(Icons.chat_rounded),
              label: Text(s('reportSendWhatsApp'), style: const TextStyle(fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: whatsapp,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _saveOrShare,
              icon: const Icon(Icons.download_rounded),
              label: Text(s('reportSaveShare')),
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
          ),
        ],
      ),
    );
  }
}
