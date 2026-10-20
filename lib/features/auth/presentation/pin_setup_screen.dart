import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/app_lock.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_backdrop.dart';
import '../../../core/widgets/responsive.dart';
import 'widgets/auth_header.dart';
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

class _PinSetupScreenState extends ConsumerState<PinSetupScreen>
    with SingleTickerProviderStateMixin {
  final List<String> _digits = [];
  String? _firstPin;
  String? _error;
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
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
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final confirming = _firstPin != null;

    return Scaffold(
      backgroundColor: deepNavy,
      body: BrandBackdrop(
        child: NarrowSafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Navigator.of(context).canPop()
                      ? IconButton(
                          tooltip: s('back'),
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        )
                      : const SizedBox(height: 48),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.4),
                        blurRadius: 34,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: Icon(
                    confirming
                        ? Icons.verified_user_outlined
                        : Icons.lock_outline_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  confirming ? s('pinSetupConfirmTitle') : s('pinSetupTitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  confirming
                      ? s('pinSetupConfirmSubtitle')
                      : s('pinSetupSubtitle'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                AnimatedBuilder(
                  animation: _shakeController,
                  builder: (context, child) {
                    final t = _shakeController.value;
                    final offset = (t == 0)
                        ? 0.0
                        : (16 * (1 - t)) * ((t * 10).floor().isEven ? 1 : -1);
                    return Transform.translate(
                      offset: Offset(offset, 0),
                      child: child,
                    );
                  },
                  child: PinDots(
                    length: _codeLength,
                    filled: _digits.length,
                    error: _error != null,
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: Center(
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFFF8A80),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const Spacer(),
                NumericKeypad(
                  glass: true,
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
