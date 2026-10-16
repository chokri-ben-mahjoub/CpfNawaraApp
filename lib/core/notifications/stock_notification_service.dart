import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../platform/app_platform.dart';

const _channelId = 'stock_low_alert';

/// Alerte de stock bas (voir `stock_repository.dart`) : contrairement au
/// rappel quotidien de saisie (`reminder_service.dart`), affichée tout de
/// suite plutôt que programmée. Un seul identifiant par article : une
/// nouvelle alerte remplace la précédente au lieu de s'empiler.
class StockNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static bool get isSupported => isAndroid;

  static Future<void> _init(String channelName) async {
    if (_initialized) return;
    const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(AndroidNotificationChannel(_channelId, channelName, importance: Importance.high));
    _initialized = true;
  }

  static Future<void> notifyLowStock({
    required String itemId,
    required String channelName,
    required String title,
    required String body,
  }) async {
    if (!isSupported) return;
    try {
      await _init(channelName);
      await _plugin.show(
        itemId.hashCode & 0x7fffffff,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(_channelId, channelName, importance: Importance.high, priority: Priority.high),
        ),
      );
    } catch (_) {
      // Notifications indisponibles (permission refusée...) : sans
      // conséquence, l'alerte reste visible dans l'écran Stock.
    }
  }
}
