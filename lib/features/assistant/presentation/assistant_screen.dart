import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_client.dart';
import '../../../core/ai/labo_context.dart';
import '../../../core/data/stock_repository.dart';
import '../../../core/data/wells_repository.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/plant/plant_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';

/// Assistant « Demande à ton labo » : questions en langage naturel sur les
/// données de l'app (valeurs récentes, seuils, stock) et résumé du jour.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <AiMessage>[];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final key = ref.read(aiKeyProvider);
    final question = text.trim();
    if (key == null || question.isEmpty || _busy) return;
    final locale = ref.read(localeProvider);
    String s(String k) => tr(locale, k);

    setState(() {
      _messages.add(AiMessage(true, question));
      _busy = true;
      _error = null;
      _input.clear();
    });
    _scrollDown();

    final context = buildLaboContext(
      data: ref.read(wellsControllerProvider),
      plantState: ref.read(plantControllerProvider),
      plant: ref.read(plantControllerProvider.notifier),
      stock: ref.read(stockControllerProvider),
      today: DateTime.now(),
      s: s,
    );
    try {
      final answer = await askAssistant(
        apiKey: key,
        system: '$assistantSystemPrompt$context',
        messages: _messages,
      );
      if (!mounted) return;
      setState(() => _messages.add(AiMessage(false, answer)));
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _error = s(e.messageKey));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _editKey() async {
    final locale = ref.read(localeProvider);
    String s(String k) => tr(locale, k);
    final controller = TextEditingController(text: ref.read(aiKeyProvider) ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s('aiKeyTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s('aiKeyBody'), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'sk-ant-…', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          if (ref.read(aiKeyProvider) != null)
            TextButton(onPressed: () => Navigator.pop(dialogContext, ''), child: Text(s('aiKeyRemove'))),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: Text(s('entrySave'))),
        ],
      ),
    );
    if (result != null) await ref.read(aiKeyProvider.notifier).save(result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final key = ref.watch(aiKeyProvider);
    String s(String k) => tr(locale, k);
    final suggestions = [s('aiSuggestSummary'), s('aiSuggestOut'), s('aiSuggestTrends'), s('aiSuggestStock')];

    return Scaffold(
      appBar: AppBar(
        title: Text(s('aiTitle')),
        actions: [IconButton(tooltip: s('aiKeyTitle'), icon: const Icon(Icons.key_outlined), onPressed: _editKey)],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: key == null
                ? ListView(
                    padding: pagePadding(context, top: 16, bottom: 24),
                    children: [
                      Icon(Icons.auto_awesome, size: 56, color: accentColor),
                      const SizedBox(height: 16),
                      Text(
                        s('aiIntroTitle'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s('aiIntroBody'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _editKey,
                        icon: const Icon(Icons.key_outlined),
                        label: Text(s('aiKeyTitle')),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(
                        child: _messages.isEmpty
                            ? ListView(
                                padding: pagePadding(context, top: 16, bottom: 12),
                                children: [
                                  Text(
                                    s('aiAskHint'),
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final text in suggestions)
                                        ActionChip(label: Text(text), onPressed: () => _send(text)),
                                    ],
                                  ),
                                ],
                              )
                            : ListView(
                                controller: _scroll,
                                padding: pagePadding(context, top: 12, bottom: 12),
                                children: [
                                  for (final m in _messages) _Bubble(message: m),
                                  if (_busy)
                                    const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                                      ),
                                    ),
                                  if (_error != null)
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
                                    ),
                                ],
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.send,
                                onSubmitted: _send,
                                decoration: InputDecoration(
                                  hintText: s('aiInputHint'),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              tooltip: s('aiSend'),
                              onPressed: _busy ? null : () => _send(_input.text),
                              icon: const Icon(Icons.send_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final AiMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = message.fromUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: user ? accentColor.withValues(alpha: 0.16) : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: SelectableText(message.text, style: const TextStyle(height: 1.4)),
      ),
    );
  }
}
