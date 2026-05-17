package com.example.haku.receiver

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.haku.R

/**
 * 🔔 NotificationAlarmReceiver
 *
 * รับ AlarmManager broadcast → แสดง local notification
 * ใช้สำหรับ scheduleReminder จาก SchedulerService (Dart)
 */
class NotificationAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "HakuAlarm"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val CHANNEL_ID = "haku_proactive_triggers"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Haku"
        val body = intent.getStringExtra(EXTRA_BODY) ?: ""

        Log.i(TAG, "🔔 Firing scheduled notification: $title")

        val notificationManager = context.getSystemService(NotificationManager::class.java)

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    }
}
