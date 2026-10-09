import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/app_lock.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import 'widgets/numeric_keypad.dart';

const _codeLength = 4;

/// Première définition du code à 4 chiffres après une connexion email + mot
/// de passe : ensuite, l'app se déverrouille avec ce code (ou l'empreinte)
/// sans redemander l'email/mot de passe.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> with SingleTickerProviderStateMixin {
  final List<String> _digits = [];
  String? _firstPin;
  String? _error;
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigit(String d) {
    if (_digits.length >= _codeLength) return;
    setState(() {
      _digits.add(d);
      _error = null;
    });
    if (_digits.length == _codeLength) {
      Future.delayed(const Duration(milliseconds: 150), _onComplete);
    }
  }

  void _onBackspace() {
    if (_digits.isEmpty) return;
    setState(() => _digits.removeLast());
  }

  Future<void> _onComplete() async {
    final entered = _digits.join();
    if (_firstPin == null) {
      setState(() {
        _firstPin = entered;
        _digits.clear();
      });
      return;
    }
    if (entered == _firstPin) {
      await ref.read(appLockProvider.notifier).setPin(entered);
      if (!mounted) return;
      // 1ère définition (juste après connexion) : le routeur bascule seul
      // vers /home. Changement volontaire depuis le compte : on revient en
      // arrière nous-mêmes.
      if (context.canPop()) context.pop();
      return;
    }
    await _shakeController.forward(from: 0);
    final locale = ref.read(localeProvider);
    setState(() {
      _error = tr(locale, 'pinMismatch');
      _firstPin = null;
      _digits.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final confirming = _firstPin != null;

    return Scaffold(
      appBar: AppBar(),
      body: NarrowSafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.pin_outlined, color: accentColor, size: 28),
              ),
              const SizedBox(height: 20),
              Text(
                confirming ? s('pinSetupConfirmTitle') : s('pinSetupTitle'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                confirming ? s('pinSetupConfirmSubtitle') : s('pinSetupSubtitle'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              AnimatedBuilder(
                animation: _shakeController,
                builder: (context, child) {
                  final t = _shakeController.value;
                  final offset = (t == 0) ? 0.0 : (16 * (1 - t)) * ((t * 10).floor().isEven ? 1 : -1);
                  return Transform.translate(offset: Offset(offset, 0), child: child);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _codeLength; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _digits.length ? accentColor : scheme.surfaceContainerHigh,
                          border: Border.all(color: i < _digits.length ? accentColor : scheme.outlineVariant),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 20,
                child: _error != null ? Text(_error!, style: TextStyle(color: scheme.error, fontSize: 13)) : null,
              ),
              const Spacer(),
              NumericKeypad(onDigit: _onDigit, onBackspace: _onBackspace),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
