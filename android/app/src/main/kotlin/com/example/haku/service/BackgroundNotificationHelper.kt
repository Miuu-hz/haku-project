package com.example.haku.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.example.haku.MainActivity
import com.example.haku.R

/**
 * 🔔 Notification Helper สำหรับ Haku Foreground Service
 *
 * จัดการ notification channels และ builder สำหรับ:
 * - Foreground service (persistent)
 * - Proactive trigger notifications
 * - Background task completion
 */
object BackgroundNotificationHelper {

    private const val FOREGROUND_CHANNEL_ID = "haku_foreground_service"
    private const val PROACTIVE_CHANNEL_ID = "haku_proactive_triggers"
    private const val TASK_CHANNEL_ID = "haku_background_tasks"

    private const val FOREGROUND_CHANNEL_NAME = "Haku Background Engine"
    private const val PROACTIVE_CHANNEL_NAME = "Proactive AI Triggers"
    private const val TASK_CHANNEL_NAME = "Background Tasks"

    /**
     * 🚀 สร้าง notification channels (เรียกครั้งเดียวตอน app start)
     */
    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Foreground service channel (low importance — just a status indicator)
            val foregroundChannel = NotificationChannel(
                FOREGROUND_CHANNEL_ID,
                FOREGROUND_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Haku AI running for proactive assistance"
                setShowBadge(false)
            }

            // Proactive trigger channel (high importance — user-facing alerts)
            val proactiveChannel = NotificationChannel(
                PROACTIVE_CHANNEL_ID,
                PROACTIVE_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "AI-triggered reminders and suggestions"
            }

            // Background task channel (default — task completion notices)
            val taskChannel = NotificationChannel(
                TASK_CHANNEL_ID,
                TASK_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Background processing notifications"
            }

            manager.createNotificationChannels(listOf(foregroundChannel, proactiveChannel, taskChannel))
        }
    }

    /**
     * 🏃 สร้าง foreground service notification
     */
    fun buildForegroundNotification(context: Context): Notification {
        val openIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(context, FOREGROUND_CHANNEL_ID)
            .setContentTitle("Haku กำลังทำงานอยู่")
            .setContentText("AI ผู้ช่วยของคุณพร้อมส่งเสียงเตือนและสรุปข้อมูล")
            .setSmallIcon(R.mipmap.ic_launcher_foreground)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(openIntent)
            .build()
    }

    /**
     * 🔔 สร้าง proactive trigger notification
     */
    fun buildProactiveNotification(
        context: Context,
        title: String,
        body: String,
        triggerType: String
    ): Notification {
        val openIntent = PendingIntent.getActivity(
            context,
            triggerType.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("trigger_type", triggerType)
                putExtra("trigger_title", title)
                putExtra("trigger_body", body)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(context, PROACTIVE_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.mipmap.ic_launcher_foreground)
            .setAutoCancel(true)
            .setContentIntent(openIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
    }

    /**
     * ✅ สร้าง background task completion notification
     */
    fun buildTaskCompleteNotification(
        context: Context,
        taskType: String,
        message: String
    ): Notification {
        return NotificationCompat.Builder(context, TASK_CHANNEL_ID)
            .setContentTitle("Haku ประมวลผลเสร็จแล้ว")
            .setContentText(message)
            .setSmallIcon(R.mipmap.ic_launcher_foreground)
            .setAutoCancel(true)
            .build()
    }

    /**
     * 📬 แสดง notification ผ่าน NotificationManager
     */
    fun showNotification(context: Context, id: Int, notification: Notification) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(id, notification)
    }
}
