package dev.aurora.aurora_music

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.widget.RemoteViews
import java.io.File

/**
 * Home-screen widget showing what is playing, with working transport buttons.
 *
 * State comes from SharedPreferences written by the Flutter side, so no
 * service binding is needed. The buttons send media key events to
 * audio_service's existing MediaButtonReceiver, which means the widget drives
 * the same playback session the notification and the car use.
 */
class AuroraWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context))
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) refresh(context)
    }

    companion object {
        const val ACTION_REFRESH = "dev.aurora.auroraMusic.WIDGET_REFRESH"

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(
                ComponentName(context, AuroraWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return
            val views = buildViews(context)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun buildViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.aurora_widget)
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

            val title = prefs.getString("flutter.aurora_widget_title", null)
            val artist = prefs.getString("flutter.aurora_widget_artist", null)
            val playing = prefs.getBoolean("flutter.aurora_widget_playing", false)
            val artPath = prefs.getString("flutter.aurora_widget_art", null)

            views.setTextViewText(
                R.id.widget_title,
                if (title.isNullOrBlank()) "Aurora Music" else title
            )
            views.setTextViewText(
                R.id.widget_artist,
                if (artist.isNullOrBlank()) "Nothing playing" else artist
            )

            views.setImageViewResource(
                R.id.widget_play,
                if (playing) android.R.drawable.ic_media_pause
                else android.R.drawable.ic_media_play
            )

            val bitmap = artPath?.let { path ->
                runCatching {
                    val file = File(path)
                    if (file.exists()) BitmapFactory.decodeFile(path) else null
                }.getOrNull()
            }
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.widget_art, bitmap)
            } else {
                views.setImageViewResource(R.id.widget_art, R.mipmap.ic_launcher)
            }

            views.setOnClickPendingIntent(
                R.id.widget_play,
                mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 1)
            )
            views.setOnClickPendingIntent(
                R.id.widget_next,
                mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT, 2)
            )
            views.setOnClickPendingIntent(
                R.id.widget_root,
                openApp(context)
            )

            return views
        }

        private fun mediaButton(context: Context, keyCode: Int, slot: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setClassName(
                    context.packageName,
                    "com.ryanheise.audioservice.MediaButtonReceiver"
                )
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_UP, keyCode))
            }
            return PendingIntent.getBroadcast(
                context,
                slot,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun openApp(context: Context): PendingIntent {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent()
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return PendingIntent.getActivity(
                context,
                3,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private const val PREFS = "FlutterSharedPreferences"
    }
}
