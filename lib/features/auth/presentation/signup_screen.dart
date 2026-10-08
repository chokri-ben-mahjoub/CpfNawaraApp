import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';

/// Clés de service stables (indépendantes de la langue) utilisées comme
/// valeur du menu déroulant ; la traduction affichée vient de [tr].
const _serviceKeys = [
  'serviceLaboratoire',
  'serviceProduction',
  'serviceExploitation',
  'serviceReservoir',
  'serviceHse',
];

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _service;
  bool _serviceTouched = false;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    if (_service == null) {
      setState(() => _serviceTouched = true);
    }
    if (!valid || _service == null) return;

    final locale = ref.read(localeProvider);
    String s(String key) => tr(locale, key);

    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            fullName: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            serviceKey: _service!,
          );
      // Compte créé et session ouverte dans la foulée (Firebase) : la
      // redirection vers la création du code / l'accueil est gérée par le
      // routeur (sessionAuthenticatedProvider), comme pour la connexion.
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('signupError'))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    String s(String key) => tr(locale, key);
    final serviceMissing = _serviceTouched && _service == null;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.person_add_alt_1_outlined,
                              color: accentColor, size: 26),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          s('signupTitle'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s('signupSubtitle'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          s('signupNameLabel'),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: s('signupNameHint'),
                            prefixIcon: const Icon(Icons.badge_outlined),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().length < 3) {
                              return s('signupInvalidName');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        Text(
                          s('signupServiceLabel'),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _service,
                          decoration: InputDecoration(
                            hintText: s('signupServiceHint'),
                            prefixIcon: const Icon(Icons.groups_outlined),
                          ),
                          items: [
                            for (final key in _serviceKeys)
                              DropdownMenuItem(value: key, child: Text(s(key))),
                          ],
                          onChanged: (value) =>
                              setState(() {
                                _service = value;
                                _serviceTouched = true;
                              }),
                        ),
                        if (serviceMissing) ...[
                          const SizedBox(height: 8),
                          Text(
                            s('signupInvalidService'),
                            style: TextStyle(color: scheme.error, fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          s('loginEmailLabel'),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: s('loginEmailHint'),
                            prefixIcon: const Icon(Icons.mail_outline),
                          ),
                          validator: (value) {
                            final v = (value ?? '').trim();
                            if (!v.contains('@') || !v.contains('.')) return s('loginInvalidEmail');
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        Text(
                          s('signupPhoneLabel'),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
                          decoration: InputDecoration(
                            hintText: s('loginPhoneHint'),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text('+216', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            prefixIconConstraints: const BoxConstraints(minWidth: 0),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          s('signupPasswordLabel'),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').length < 8) return s('signupInvalidPassword');
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: () => context.pop(),
                            child: Text.rich(
                              TextSpan(
                                text: '${s('signupHaveAccount')} ',
                                style: TextStyle(color: scheme.onSurfaceVariant),
                                children: [
                                  TextSpan(
                                    text: s('signupLogin'),
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
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : Text(
                            s('signupSubmit'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
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
