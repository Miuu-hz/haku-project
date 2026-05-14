package com.example.haku.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.example.haku.service.HakuForegroundService

/**
 * 🔄 Boot Receiver
 *
 * รับ event เมื่อเครื่อง boot เสร็จ แล้ว:
 * - สร้าง notification channels
 * - reschedule daily alarms (ถ้ามี)
 * - ไม่ start service อัตโนมัติ (ประหยัดแบต) ยกเว้นมี pending background tasks
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "HakuBoot"
        private const val PREFS_NAME = "haku_background"
        private const val PREF_HAS_PENDING_TASKS = "has_pending_tasks"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        Log.i(TAG, "🔄 Boot completed — setting up Haku background infrastructure")

        // สร้าง notification channels
        com.example.haku.service.BackgroundNotificationHelper.createChannels(context)

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

        // TODO: Reschedule daily alarms via AlarmScheduler (Milestone 2)
    }
}
