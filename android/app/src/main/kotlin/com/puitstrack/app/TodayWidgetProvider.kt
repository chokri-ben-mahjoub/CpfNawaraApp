package com.puitstrack.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widget d'accueil : analyses restant à saisir et articles de stock sous leur
 * seuil. Les textes (déjà traduits) sont écrits par l'app Flutter à chaque
 * saisie ; toucher le widget ouvre l'app.
 */
class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.today_widget).apply {
                setTextViewText(R.id.widget_title, widgetData.getString("w_title", "CPF Laboratory NAWARA"))
                setTextViewText(R.id.widget_todo, widgetData.getString("w_todo", "--"))
                setTextViewText(R.id.widget_stock, widgetData.getString("w_stock", ""))
                val alert = widgetData.getBoolean("w_alert", false)
                setTextColor(R.id.widget_todo, if (alert) Color.parseColor("#FF8A80") else Color.WHITE)
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
