import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/sync/firebase_config.dart';
import '../../../core/sync/firebase_config_provider.dart';
import '../../../core/sync/firebase_rest.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/team/firestore_rules.dart';
import '../../../core/team/team_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../settings/presentation/settings_screen.dart' show SectionCard;
import '../../settings/presentation/sync_section.dart';
import '../../setup/presentation/widgets/firebase_project_picker.dart';
import '../../setup/presentation/widgets/team_account_form.dart';
import 'widgets/admin_widgets.dart';

enum _Check { pending, ok, failed }

/// Projet Firebase : configuration, QR code pour les autres appareils,
/// test de la connexion et des règles, règles à copier.
class FirebaseProjectScreen extends ConsumerStatefulWidget {
  const FirebaseProjectScreen({super.key});

  @override
  ConsumerState<FirebaseProjectScreen> createState() => _FirebaseProjectScreenState();
}

class _FirebaseProjectScreenState extends ConsumerState<FirebaseProjectScreen> {
  bool _testing = false;
  _Check? _network;
  _Check? _account;
  _Check? _database;
  _Check? _rules;
  _Check? _functions;
  ProjectProblem? _problem;
  bool _showRules = false;

  String s(String key) => tr(ref.read(localeProvider), key);

  Future<void> _test() async {
    final controller = ref.read(syncControllerProvider.notifier);
    final team = controller.team;
    if (team == null) return;
    setState(() {
      _testing = true;
      _network = _Check.pending;
      _account = null;
      _database = null;
      _rules = null;
      _functions = null;
      _problem = null;
    });
    try {
      final session = await controller.freshSession();
      setState(() {
        _network = _Check.ok;
        _account = _Check.ok;
      });
      final status = await team.probeRules(session);
      setState(() {
        _database = status == RulesStatus.databaseMissing ? _Check.failed : _Check.ok;
        _rules = status == RulesStatus.ok ? _Check.ok : _Check.failed;
        _problem = switch (status) {
          RulesStatus.ok => null,
          RulesStatus.notPublished => ProjectProblem.rulesNotPublished,
          RulesStatus.databaseMissing => ProjectProblem.databaseMissing,
        };
      });
      if (status == RulesStatus.ok) {
        final functions = await team.functionsAvailable(session);
        setState(() => _functions = functions ? _Check.ok : _Check.failed);
        await controller.refreshMember();
      }
    } on SyncNetworkException {
      setState(() => _network = _Check.failed);
    } on SyncAuthException {
      setState(() {
        _network = _Check.ok;
        _account = _Check.failed;
      });
    } catch (e) {
      setState(() => _problem = projectProblemOf(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _changeProject() async {
    final ok = await confirmDanger(
      context,
      title: s('projectChangeTitle'),
      body: s('projectChangeBody'),
      confirm: s('setupChangeProject'),
      cancel: s('cancel'),
    );
    if (!ok || !mounted) return;
    await showFirebaseProjectSheet(context);
  }

  Future<void> _forgetProject() async {
    final ok = await confirmDanger(
      context,
      title: s('projectForgetTitle'),
      body: s('projectForgetBody'),
      confirm: s('projectForget'),
      cancel: s('cancel'),
    );
    if (!ok) return;
    await ref.read(syncControllerProvider.notifier).signOut();
    await ref.read(firebaseConfigProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final config = ref.watch(firebaseConfigProvider);
    final sync = ref.watch(syncControllerProvider);
    String t(String key) => tr(locale, key);
    final hint = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4);

    if (config == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('adminFirebase'))),
        body: ListView(
          padding: pagePadding(context, top: 8, bottom: 40, maxWidth: 640),
          children: [
            Text(t('projectNoneBody'), style: hint),
            const SizedBox(height: 16),
            FirebaseProjectPicker(onSelected: (c) => ref.read(firebaseConfigProvider.notifier).set(c)),
          ],
        ),
      );
    }

    final projectCard = SectionCard(
      title: t('setupProject'),
      icon: Icons.cloud_outlined,
      children: [
        _InfoRow(t('projectId'), config.projectId),
        _InfoRow(t('projectApiKey'), config.maskedApiKey),
        if (config.authDomain.isNotEmpty) _InfoRow('Auth domain', config.authDomain),
        if (config.appId.isNotEmpty) _InfoRow('App ID', config.appId),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => openExternalLink(config.consoleUrl('overview')),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(t('projectOpenConsole')),
            ),
            OutlinedButton.icon(
              onPressed: _changeProject,
              icon: const Icon(Icons.swap_horiz),
              label: Text(t('setupChangeProject')),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(config.toJson())));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('projectConfigCopied'))));
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(t('projectCopyConfig')),
            ),
            if (ref.watch(firebaseConfigProvider.notifier).isCustom)
              TextButton(
                onPressed: _forgetProject,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: Text(t('projectForget')),
              ),
          ],
        ),
      ],
    );

    final functionsCard = SectionCard(
      title: t('functionsTitle'),
      icon: Icons.dns_outlined,
      children: [
        Text(t('functionsBody'), style: hint),
        const SizedBox(height: 10),
        _CheckRow(
          _functions == null
              ? t('functionsUnknown')
              : _functions == _Check.ok
              ? t('functionsOn')
              : t('functionsOff'),
          _functions,
        ),
        if (_functions == _Check.failed) ...[
          const SizedBox(height: 6),
          Text(t('functionsHowTo'), style: hint),
        ],
      ],
    );

    final testCard = SectionCard(
      title: t('projectTestTitle'),
      icon: Icons.health_and_safety_outlined,
      children: [
        if (!sync.isSignedIn)
          Text(t('projectTestSignIn'), style: hint)
        else ...[
          Text(t('projectTestBody'), style: hint),
          const SizedBox(height: 10),
          _CheckRow(t('projectCheckNetwork'), _network),
          _CheckRow(t('projectCheckAccount'), _account),
          _CheckRow(t('projectCheckDatabase'), _database),
          _CheckRow(t('projectCheckRules'), _rules),
          _CheckRow(t('projectCheckFunctions'), _functions),
          if (_problem != null) ...[const SizedBox(height: 10), ProjectProblemCard(problem: _problem!, config: config)],
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(t('projectTestRun')),
          ),
        ],
      ],
    );

    final rulesCard = SectionCard(
      title: t('rulesTitle'),
      icon: Icons.shield_outlined,
      children: [
        Text(t('rulesBody'), style: hint),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: firestoreRules));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('rulesCopied'))));
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(t('rulesCopy')),
            ),
            OutlinedButton.icon(
              onPressed: () => openExternalLink(config.consoleUrl('firestore/rules')),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(t('rulesOpenConsole')),
            ),
            TextButton(
              onPressed: () => setState(() => _showRules = !_showRules),
              child: Text(t(_showRules ? 'rulesHide' : 'rulesShow')),
            ),
          ],
        ),
        if (_showRules) ...[
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 360),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(
              child: SelectableText(firestoreRules, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
            ),
          ),
        ],
        const Divider(height: 28),
        Text(t('consoleChecklistTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        _ConsoleStep(1, t('consoleStepAuth'), config.consoleUrl('authentication/providers')),
        _ConsoleStep(2, t('consoleStepFirestore'), config.consoleUrl('firestore')),
        _ConsoleStep(3, t('consoleStepRules'), config.consoleUrl('firestore/rules')),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(t('adminFirebase'))),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 40),
        children: [
          ResponsiveWrapGrid(
            minItemWidth: 420,
            maxColumns: 2,
            spacing: 16,
            children: [projectCard, testCard, functionsCard, rulesCard],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

class _CheckRow extends StatelessWidget {
  final String label;
  final _Check? state;
  const _CheckRow(this.label, this.state);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (state) {
      null => Icon(Icons.radio_button_unchecked, size: 20, color: scheme.outline),
      _Check.pending => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      _Check.ok => Icon(Icons.check_circle_rounded, size: 20, color: Colors.green.shade600),
      _Check.failed => Icon(Icons.cancel_rounded, size: 20, color: scheme.error),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _ConsoleStep extends ConsumerWidget {
  final int n;
  final String text;
  final String url;
  const _ConsoleStep(this.n, this.text, this.url);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: accentColor.withValues(alpha: 0.15),
            child: Text(
              '$n',
              style: const TextStyle(color: accentColor, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          IconButton(
            tooltip: tr(ref.watch(localeProvider), 'problemOpenConsole'),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            onPressed: () => openExternalLink(url),
          ),
        ],
      ),
    );
  }
}

/// Configuration affichée en QR code (utile aux tests).
String qrPayloadOf(FirebaseRestConfig config) => config.qrPayload;
