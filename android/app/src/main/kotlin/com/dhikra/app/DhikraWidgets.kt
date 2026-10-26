package com.dhikra.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** ويدجت ورد الحديث: تقدّم اليوم وبداية الحديث التالي، والضغط يفتح القارئ. */
class WirdWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_wird).apply {
                setTextViewText(R.id.wird_progress, widgetData.getString("wird_progress", "") ?: "")
                setTextViewText(R.id.wird_sub, widgetData.getString("wird_sub", "افتح التطبيق لبدء الورد") ?: "")
                setTextViewText(R.id.wird_text, widgetData.getString("wird_text", "") ?: "")
                setOnClickPendingIntent(R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("dhikra://wird")))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

/** ويدجت الفوائد: فائدة اليوم من الدفتر، والضغط يفتح دفتر الفوائد. */
class BenefitWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_benefit).apply {
                setTextViewText(R.id.benefit_title, widgetData.getString("benefit_title", "فائدة") ?: "فائدة")
                setTextViewText(R.id.benefit_body, widgetData.getString("benefit_body", "دفتر الفوائد فارغ بعد") ?: "")
                setTextViewText(R.id.benefit_source, widgetData.getString("benefit_source", "") ?: "")
                setOnClickPendingIntent(R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("dhikra://benefits")))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
