import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../platform/app_platform.dart';

const _channelId = 'daily_entry_reminder';

/// Identifiants réservés aux rappels quotidiens (un par jour programmé).
const _firstId = 1000;

/// Nombre de jours programmés d'avance : la liste est recalculée à chaque
/// ouverture de l'app (et après chaque saisie), ce qui permet de sauter le
/// rappel du jour quand tout est déjà saisi.
const _daysAhead = 14;

/// Rappel quotidien de saisie des analyses (notification locale, aucun
/// serveur nécessaire). Chaque rappel est programmé comme un instant précis
/// (heure locale convertie en UTC) : pas besoin de connaître le fuseau
/// horaire IANA de l'appareil.
class ReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static bool get isSupported => debugForceSupported ?? isAndroid;

  /// Permet aux tests de rendu d'afficher la section Rappels hors Android.
  static bool? debugForceSupported;

  static Future<void> _init(String channelName) async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(AndroidNotificationChannel(_channelId, channelName, importance: Importance.high));
    _initialized = true;
  }

  /// Demande l'autorisation d'afficher des notifications (Android 13+).
  /// Retourne `false` si l'utilisateur refuse.
  static Future<bool> requestPermission(String channelName) async {
    if (!isSupported) return false;
    await _init(channelName);
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    return granted ?? true;
  }

  /// Reprogramme les rappels des [_daysAhead] prochains jours à [time]
  /// (ou les annule tous si [enabled] est faux). [skipToday] : ne pas
  /// rappeler aujourd'hui (tout est déjà saisi).
  static Future<void> reschedule({
    required bool enabled,
    required TimeOfDay time,
    required bool skipToday,
    required String channelName,
    required String title,
    required String body,
    String? bodyToday,
  }) async {
    if (!isSupported) return;
    await _init(channelName);
    for (var i = 0; i < _daysAhead; i++) {
      await _plugin.cancel(_firstId + i);
    }
    if (!enabled) return;

    final now = DateTime.now();
    for (var i = 0; i < _daysAhead; i++) {
      if (i == 0 && skipToday) continue;
      final day = DateTime(now.year, now.month, now.day + i, time.hour, time.minute);
      if (!day.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        _firstId + i,
        title,
        i == 0 ? (bodyToday ?? body) : body,
        tz.TZDateTime.from(day, tz.UTC),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}
