import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_lock.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_backdrop.dart';
import '../../../core/widgets/responsive.dart';
import 'widgets/numeric_keypad.dart';
import '../../../core/widgets/profile_avatar.dart';

const _codeLength = 4;

/// DÃ©verrouillage rapide Ã  chaque rÃ©ouverture de l'app : code Ã  4 chiffres
/// ou empreinte.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> with SingleTickerProviderStateMixin {
  final List<String> _digits = [];
  String? _error;
  bool _biometricAvailable = false;
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    await ref.read(appSettingsProvider.notifier).ready;
    // DÃ©sactivable dans RÃ©glages â€º SÃ©curitÃ© : seul le code est alors proposÃ©.
    final available = ref.read(appSettingsProvider).biometricEnabled && await BiometricAuth.isAvailable;
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available) unawaited(_tryBiometric());
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _forgotCode() async {
    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s('unlockForgotPinConfirmTitle')),
        content: Text(s('unlockForgotPinConfirmBody')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(s('cancel'))),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s('unlockForgotPin')),
          ),
        ],
      ),
    );
    if (confirmed == true) ref.read(appLockProvider.notifier).clearPin();
  }

  Future<void> _tryBiometric() async {
    final locale = ref.read(localeProvider);
    final ok = await BiometricAuth.authenticate(tr(locale, 'unlockBiometricReason'));
    if (ok && mounted) ref.read(appLockProvider.notifier).unlock();
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
    if (ref.read(appLockProvider.notifier).verifyPin(entered)) {
      ref.read(appLockProvider.notifier).unlock();
      return;
    }
    await _shakeController.forward(from: 0);
    final locale = ref.read(localeProvider);
    setState(() {
      _error = tr(locale, 'unlockWrongPin');
      _digits.clear();
    });
  }

  String _greeting(String Function(String) s) {
    final hour = DateTime.now().hour;
    return s(hour < 12 ? 'unlockGreetMorning' : (hour < 18 ? 'unlockGreetAfternoon' : 'unlockGreetEvening'));
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final name = ref.watch(profileProvider)?.fullName;
    String s(String key) => tr(locale, key);
    final firstName = (name ?? '').trim().split(' ').first;

    return Scaffold(
      backgroundColor: deepNavy,
      body: BrandBackdrop(
        child: NarrowSafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 28),
                // Avatar : anneau dÃ©gradÃ© et halo orange.
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accentColor, Color(0xFFFFC107)],
                    ),
                    boxShadow: [BoxShadow(color: accentColor.withValues(alpha: 0.45), blurRadius: 36, spreadRadius: -4)],
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: deepNavy),
                    child: const ProfileAvatar(radius: 40),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _greeting(s),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 15, letterSpacing: 0.4),
                ),
                const SizedBox(height: 2),
                Text(
                  firstName.isEmpty ? s('unlockTitle') : firstName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15),
                ),
                const SizedBox(height: 26),
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
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutBack,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: i < _digits.length ? 34 : 14,
                          height: 14,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: _error != null
                                ? const Color(0xFFFF6B6B)
                                : (i < _digits.length ? accentColor : Colors.white.withValues(alpha: 0.18)),
                            boxShadow: i < _digits.length && _error == null
                                ? [BoxShadow(color: accentColor.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: -2)]
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: Center(
                    child: Text(
                      _error ?? s('unlockSubtitle'),
                      style: TextStyle(
                        color: _error != null ? const Color(0xFFFF8A80) : Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                        fontWeight: _error != null ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                NumericKeypad(
                  glass: true,
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  onBiometric: _biometricAvailable ? _tryBiometric : null,
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _forgotCode,
                  child: Text(
                    s('unlockForgotPin'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 13, color: Colors.white.withValues(alpha: 0.4)),
                      const SizedBox(width: 6),
                      Text(
                        currentAppName,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11.5, letterSpacing: 0.3),
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
