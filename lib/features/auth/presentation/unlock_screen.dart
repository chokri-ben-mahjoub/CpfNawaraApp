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

/// Déverrouillage rapide à chaque réouverture de l'app : code à 4 chiffres
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
    // Désactivable dans Réglages › Sécurité : seul le code est alors proposé.
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final name = ref.watch(profileProvider)?.fullName;
    String s(String key) => tr(locale, key);

    return Scaffold(
      body: Column(
        children: [
          BrandBackdrop(
            bottomRadius: 32,
            child: SizedBox(
              width: double.infinity,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                  child: Column(
                    children: [
                      const ProfileAvatar(radius: 38),
                      const SizedBox(height: 14),
                      Text(
                        name == null || name.isEmpty ? s('unlockTitle') : '${s('unlockTitle')}, $name',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s('unlockSubtitle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                      ),
                      const SizedBox(height: 22),
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
                                duration: const Duration(milliseconds: 140),
                                margin: const EdgeInsets.symmetric(horizontal: 9),
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i < _digits.length ? accentColor : Colors.transparent,
                                  border: Border.all(
                                    color: i < _digits.length ? accentColor : Colors.white.withValues(alpha: 0.5),
                                    width: 1.8,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 28,
                        child: _error != null
                            ? Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: NarrowSafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(),
                    NumericKeypad(
                      onDigit: _onDigit,
                      onBackspace: _onBackspace,
                      onBiometric: _biometricAvailable ? _tryBiometric : null,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _forgotCode,
                      child: Text(s('unlockForgotPin'), style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
