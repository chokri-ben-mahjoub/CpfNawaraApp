import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_backdrop.dart';
import '../../../core/widgets/responsive.dart';
import 'widgets/language_switch.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);

    return Scaffold(
      backgroundColor: deepNavy,
      body: BrandBackdrop(
        child: NarrowSafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Align(alignment: Alignment.topRight, child: LanguageSwitch()),
                const Spacer(),
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1.5),
                    boxShadow: [BoxShadow(color: accentColor.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: -6)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Image.asset('assets/icon/icon.png', fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  s('onboardingTitle'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  s('onboardingBody'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                    height: 1.5,
                  ),
                ),
                const Spacer(flex: 2),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _saving ? null : _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            s('onboardingCta'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    await ref.read(onboardingDoneProvider.notifier).complete();
    if (!mounted) return;
    context.go('/setup');
  }
}
