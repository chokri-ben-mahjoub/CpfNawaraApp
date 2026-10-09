import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';

/// Configuration du profil local de cet appareil (nom, service, téléphone) :
/// une seule fois, juste après l'onboarding (mode 100% local, pas de compte
/// cloud pour l'instant — voir README). Enchaîne ensuite sur la création du
/// code à 4 chiffres.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _service;
  bool _serviceTouched = false;
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    if (_service == null) {
      setState(() => _serviceTouched = true);
    }
    if (!valid || _service == null) return;

    setState(() => _loading = true);
    try {
      await ref
          .read(authServiceProvider)
          .createProfile(
            fullName: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            serviceKey: _service!,
          );
      // La redirection vers la création du code / l'accueil est gérée par le
      // routeur (sessionAuthenticatedProvider).
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
      // Retour au choix du mode (équipe / personnel).
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/setup'))),
      body: NarrowSafeArea(
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
                        const SizedBox(height: 12),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.person_add_alt_1_outlined, color: accentColor, size: 26),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          s('signupTitle'),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s('signupSubtitle'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          s('signupNameLabel'),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _service,
                          decoration: InputDecoration(
                            hintText: s('signupServiceHint'),
                            prefixIcon: const Icon(Icons.groups_outlined),
                          ),
                          items: [for (final key in serviceKeys) DropdownMenuItem(value: key, child: Text(s(key)))],
                          onChanged: (value) => setState(() {
                            _service = value;
                            _serviceTouched = true;
                          }),
                        ),
                        if (serviceMissing) ...[
                          const SizedBox(height: 8),
                          Text(s('signupInvalidService'), style: TextStyle(color: scheme.error, fontSize: 12)),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          s('signupPhoneLabel'),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
                          decoration: InputDecoration(
                            hintText: s('phoneHint'),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text('+216', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            prefixIconConstraints: const BoxConstraints(minWidth: 0),
                          ),
                        ),
                        const SizedBox(height: 16),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : Text(s('signupSubmit'), style: const TextStyle(fontWeight: FontWeight.w700)),
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
