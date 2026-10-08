import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_theme.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final name = ref.watch(pendingNameProvider);
    final phone = ref.watch(pendingPhoneProvider);
    final service = ref.watch(pendingServiceProvider);
    final role = ref.watch(currentRoleProvider);
    String s(String key) => tr(locale, key);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: accentColor.withValues(alpha: 0.14),
                  child: Text(
                    (name == null || name.isEmpty ? s('accountNoName') : name)[0].toUpperCase(),
                    style: const TextStyle(color: accentColor, fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name == null || name.isEmpty ? s('accountNoName') : name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      if (phone != null && phone.isNotEmpty)
                        Text('+216 $phone', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                      if (service != null) Text(s(service), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(s('accountRoleLabel'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(s('accountRoleHint'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 10),
        SegmentedButton<UserRole>(
          segments: [
            for (final r in UserRole.values) ButtonSegment(value: r, label: Text(s(r.labelKey)))
          ],
          selected: {role},
          onSelectionChanged: (selection) => ref.read(currentRoleProvider.notifier).state = selection.first,
        ),
        if (role == UserRole.reader) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: scheme.onSecondaryContainer, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(s('roleReaderNotice'), style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (role.canConfigure)
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune, color: accentColor),
              title: Text(s('accountAdminSettings'), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/admin/analysis-types'),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(s('logout'), style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              ref.read(sessionAuthenticatedProvider.notifier).state = false;
              ref.read(pendingPhoneProvider.notifier).state = null;
              ref.read(pendingNameProvider.notifier).state = null;
              ref.read(pendingServiceProvider.notifier).state = null;
            },
          ),
        ),
      ],
    );
  }
}
