import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/app_strings.dart';
import 'spoken_number.dart';

/// Bouton micro : dicter une valeur (« zéro virgule huit ») au lieu de la
/// taper — mains libres, avec des gants. Appelle [onNumber] avec le nombre
/// reconnu ; un message invite à réessayer si rien d'exploitable n'est entendu.
class VoiceNumberButton extends ConsumerStatefulWidget {
  final ValueChanged<double> onNumber;
  const VoiceNumberButton({super.key, required this.onNumber});

  @override
  ConsumerState<VoiceNumberButton> createState() => _VoiceNumberButtonState();
}

class _VoiceNumberButtonState extends ConsumerState<VoiceNumberButton> {
  final _speech = SpeechToText();
  bool _ready = false;
  bool _listening = false;

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _toggle() async {
    final locale = ref.read(localeProvider);
    String s(String k) => tr(locale, k);
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_ready) {
      try {
        _ready = await _speech.initialize(
          onStatus: (status) {
            if ((status == 'done' || status == 'notListening') && mounted) setState(() => _listening = false);
          },
          onError: (_) {
            if (mounted) setState(() => _listening = false);
          },
        );
      } catch (_) {
        _ready = false;
      }
      if (!_ready) {
        if (mounted) _toast(s('voiceUnavailable'));
        return;
      }
    }
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: locale.languageCode == 'fr' ? 'fr_FR' : 'en_US',
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 2),
        partialResults: false,
        listenMode: ListenMode.confirmation,
      ),
      onResult: (result) {
        if (!result.finalResult) return;
        final number = parseSpokenNumber(result.recognizedWords);
        if (!mounted) return;
        setState(() => _listening = false);
        if (number == null) {
          _toast(fill(s('voiceNotUnderstood'), {'text': result.recognizedWords}));
        } else {
          widget.onNumber(number);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tr(locale, 'voiceTooltip'),
      onPressed: _toggle,
      icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? scheme.error : scheme.primary),
    );
  }
}
