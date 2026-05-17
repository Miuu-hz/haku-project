package com.example.haku.receiver

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.example.haku.service.HakuForegroundService
import java.util.Calendar

/**
 * 🔄 Boot Receiver
 *
 * รับ event เมื่อเครื่อง boot เสร็จ แล้ว:
 * - สร้าง notification channels
 * - reschedule daily alarms (09:00 morning + 20:00 evening)
 * - ไม่ start service อัตโนมัติ (ประหยัดแบต) ยกเว้นมี pending background tasks
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "HakuBoot"
        private const val PREFS_NAME = "haku_background"
        private const val PREF_HAS_PENDING_TASKS = "has_pending_tasks"

        // Alarm request codes
        private const val REQ_MORNING = 901
        private const val REQ_EVENING = 902
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        Log.i(TAG, "🔄 Boot completed — setting up Haku background infrastructure")

        // สร้าง notification channels
        com.example.haku.service.BackgroundNotificationHelper.createChannels(context)

        // 🕘 Reschedule daily alarms (morning 09:00 + evening 20:00)
        rescheduleDailyAlarms(context)

        // ตรวจสอบว่ามี pending tasks จากตอนแอพปิดหรือไม่
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val hasPendingTasks = prefs.getBoolean(PREF_HAS_PENDING_TASKS, false)

        if (hasPendingTasks) {
            Log.i(TAG, "📋 Found pending tasks — starting service to resume")
            val serviceIntent = Intent(context, HakuForegroundService::class.java).apply {
                action = HakuForegroundService.ACTION_RESUME_PENDING
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to start service on boot: ${e.message}")
            }
        }
    }

    /**
     * ⏰ Reschedule daily repeating alarms via AlarmManager
     */
    private fun rescheduleDailyAlarms(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // Morning alarm: 09:00
        scheduleAlarm(context, alarmManager, 9, 0, REQ_MORNING, "สวัสดีตอนเช้า ☀️", "เช็ก agenda วันนี้กัน!")

        // Evening alarm: 20:00
        scheduleAlarm(context, alarmManager, 20, 0, REQ_EVENING, "เย็นแล้ว 🌙", "สรุปวันนี้กับ Haku")

        Log.i(TAG, "⏰ Daily alarms rescheduled: 09:00 + 20:00")
    }

    private fun scheduleAlarm(
        context: Context,
        alarmManager: AlarmManager,
        hour: Int,
        minute: Int,
        requestCode: Int,
        title: String,
        body: String
    ) {
        val intent = Intent(context, NotificationAlarmReceiver::class.java).apply {
            putExtra(NotificationAlarmReceiver.EXTRA_TITLE, title)
            putExtra(NotificationAlarmReceiver.EXTRA_BODY, body)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // ยกเลิก alarm เดิมก่อน (idempotent)
        alarmManager.cancel(pendingIntent)

        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            // ถ้าเวลานี้ผ่านไปแล้ว ให้ตั้งเป็นวันถัดไป
            if (before(Calendar.getInstance())) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }

        val triggerTime = calendar.timeInMillis

        // ใช้ setExactAndAllowWhileIdle สำหรับความแม่นยำ (Android 6+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                pendingIntent
            )
        }

        Log.i(TAG, "⏰ Alarm scheduled: ${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')} (req=$requestCode)")
    }
}
