import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/feature_carousel.dart';
import 'widgets/language_switch.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(pendingPhoneProvider.notifier).state = _phoneController.text.trim();
    context.push('/login/code');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const Align(alignment: Alignment.topRight, child: LanguageSwitch()),
                        const SizedBox(height: 8),
                        const _Brand(),
                        const SizedBox(height: 6),
                        Text(
                          s('appTagline'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 22),
                        FeatureCarousel(
                          accentColor: accentColor,
                          slides: [
                            CarouselSlide(
                              icon: Icons.water_drop_outlined,
                              title: s('slide1Title'),
                              subtitle: s('slide1Subtitle'),
                            ),
                            CarouselSlide(
                              icon: Icons.fact_check_outlined,
                              title: s('slide2Title'),
                              subtitle: s('slide2Subtitle'),
                            ),
                            CarouselSlide(
                              icon: Icons.show_chart_rounded,
                              title: s('slide3Title'),
                              subtitle: s('slide3Subtitle'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            s('loginSubtitle'),
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
                          decoration: InputDecoration(
                            labelText: s('loginPhoneLabel'),
                            hintText: s('loginPhoneHint'),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text('+216', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            prefixIconConstraints: const BoxConstraints(minWidth: 0),
                          ),
                          validator: (value) {
                            final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                            if (digits.length < 8) return s('loginInvalidPhone');
                            return null;
                          },
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => context.push('/forgot-password'),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            child: Text(
                              s('forgotPasswordLink'),
                              style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            s('loginMultiNumberHint'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      s('loginContinue'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/signup'),
                    child: Text.rich(
                      TextSpan(
                        text: '${s('loginNoAccount')} ',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                        children: [
                          TextSpan(
                            text: s('loginCreateAccount'),
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
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
}

class _Brand extends ConsumerWidget {
  const _Brand();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.oil_barrel_outlined, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          tr(locale, 'appName'),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
