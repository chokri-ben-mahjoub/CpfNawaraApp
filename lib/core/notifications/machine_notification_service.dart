import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../machines/machine_schedule.dart';
import '../platform/app_platform.dart';

const _channelId = 'machine_alerts';

/// Alertes machines (non conforme, recalibration due) : notification Android
/// immédiate, une seule fois par alerte et par session. Sur le web, les
/// alertes restent visibles dans l'écran « Test machines ».
class MachineNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static final Set<String> _sent = {};

  static bool get isSupported => isAndroid;

  static Future<void> _init() async {
    if (_initialized) return;
    const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(_channelId, 'Alertes machines', importance: Importance.high));
    _initialized = true;
  }

  /// Notifie les alertes critiques et d'avertissement pas encore envoyées.
  static Future<void> notify(List<MachineAlert> alerts) async {
    if (!isSupported) return;
    try {
      for (final a in alerts.where((a) => a.level != AlertLevel.info)) {
        if (!_sent.add(a.key)) continue;
        await _init();
        await _plugin.show(
          a.key.hashCode & 0x7fffffff,
          '${a.title} — ${a.machine}',
          a.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(_channelId, 'Alertes machines', importance: Importance.high, priority: Priority.high),
          ),
        );
      }
    } catch (_) {
      // Permission refusée : l'alerte reste visible dans l'écran.
    }
  }
}
