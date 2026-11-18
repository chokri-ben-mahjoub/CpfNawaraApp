import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import 'app_update.dart';

/// Bandeau « Nouvelle version disponible » : Mettre à jour / Plus tard.
class AppUpdateBanner extends ConsumerStatefulWidget {
  const AppUpdateBanner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppUpdateBanner> createState() => _AppUpdateBannerState();
}

class _AppUpdateBannerState extends ConsumerState<AppUpdateBanner> {
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    startWatchingAppUpdates();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<bool>(
          valueListenable: appUpdateReady,
          builder: (context, ready, _) {
            if (!ready || _dismissed) return const SizedBox.shrink();
            return SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Material(
                      elevation: 6,
                      color: scheme.inverseSurface,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appUpdateVersion() == null
                                  ? tr(locale, 'appUpdateTitle')
                                  : '${tr(locale, 'appUpdateTitle')} · v${appUpdateVersion()}',
                              style: TextStyle(
                                color: scheme.onInverseSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            for (final note in appUpdateNotesFor(
                              locale.languageCode,
                            ).take(6))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  '• $note',
                                  style: TextStyle(
                                    color: scheme.onInverseSurface,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              tr(locale, 'appUpdateBody'),
                              style: TextStyle(color: scheme.onInverseSurface),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => _dismissed = true),
                                    child: Text(tr(locale, 'appUpdateLater')),
                                  ),
                                  FilledButton(
                                    onPressed: applyAppUpdate,
                                    child: Text(tr(locale, 'appUpdateNow')),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
