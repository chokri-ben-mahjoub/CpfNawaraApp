import 'package:home_widget/home_widget.dart';

import '../platform/app_platform.dart';

const _androidProvider = 'com.puitstrack.app.TodayWidgetProvider';

/// Widget d'accueil Android : « 5 analyses à saisir » et le stock en alerte,
/// visibles sans ouvrir l'app. Les textes sont fournis déjà traduits ; toute
/// erreur est ignorée (plateforme sans widget, widget non posé...).
class HomeWidgetService {
  static Future<void> update({
    required String title,
    required String todo,
    required String stock,
    required bool alert,
  }) async {
    if (!isAndroid) return;
    try {
      await HomeWidget.saveWidgetData<String>('w_title', title);
      await HomeWidget.saveWidgetData<String>('w_todo', todo);
      await HomeWidget.saveWidgetData<String>('w_stock', stock);
      await HomeWidget.saveWidgetData<bool>('w_alert', alert);
      await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
    } catch (_) {}
  }
}
