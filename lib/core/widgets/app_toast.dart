import 'dart:async';

import 'package:flutter/material.dart';

/// Type d'une notification : couleur et icône.
enum ToastType { success, error, warning, info }

class _ToastData {
  _ToastData(this.id, this.message, this.type, this.duration);
  final int id;
  final String message;
  final ToastType type;
  final Duration duration;
}

/// Notification (toast) affichée en haut de l'écran : création, modification,
/// suppression, erreur... Utilisable sans `BuildContext`, y compris après un
/// `await` :
///
///     AppToast.show(s('stockItemAdded'), type: ToastType.success);
///
/// Nécessite [AppToastHost] au-dessus du routeur (voir `main.dart`).
class AppToast {
  AppToast._();

  static final ValueNotifier<_ToastData?> _current = ValueNotifier(null);
  static int _seq = 0;

  static void show(
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(milliseconds: 3200),
  }) {
    if (message.trim().isEmpty) return;
    _current.value = _ToastData(++_seq, message, type, duration);
  }

  static void success(String message) => show(message, type: ToastType.success);
  static void error(String message) =>
      show(message, type: ToastType.error, duration: const Duration(seconds: 5));
  static void warning(String message) => show(message, type: ToastType.warning);
  static void info(String message) => show(message, type: ToastType.info);

  static void dismiss() => _current.value = null;
}

/// Couche qui affiche les toasts par-dessus toute l'application.
class AppToastHost extends StatelessWidget {
  const AppToastHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: ValueListenableBuilder<_ToastData?>(
                  valueListenable: AppToast._current,
                  builder: (context, data, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    reverseDuration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, -0.6), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                    ),
                    child: data == null
                        ? const SizedBox.shrink(key: ValueKey('toast-none'))
                        : _ToastCard(key: ValueKey(data.id), data: data),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({super.key, required this.data});

  final _ToastData data;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this, duration: widget.data.duration)..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.data.duration, _close);
  }

  void _close() {
    if (AppToast._current.value?.id == widget.data.id) AppToast.dismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  (IconData, Color) get _style => switch (widget.data.type) {
        ToastType.success => (Icons.check_circle_rounded, const Color(0xFF2E9E6B)),
        ToastType.error => (Icons.error_rounded, const Color(0xFFD64545)),
        ToastType.warning => (Icons.warning_amber_rounded, const Color(0xFFE59A1F)),
        ToastType.info => (Icons.info_rounded, const Color(0xFF3B82C4)),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (icon, accent) = _style;
    final bg = dark ? const Color(0xFF2A2522) : Colors.white;
    return Dismissible(
      key: ValueKey('toast-dismiss-${widget.data.id}'),
      direction: DismissDirection.up,
      onDismissed: (_) => _close(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Material(
          color: bg,
          elevation: 10,
          shadowColor: Colors.black45,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _close,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: Icon(icon, color: accent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          widget.data.message,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedBuilder(
                  animation: _progress,
                  builder: (context, _) => LinearProgressIndicator(
                    value: 1 - _progress.value,
                    minHeight: 3,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.12),
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
