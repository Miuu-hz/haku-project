package com.example.haku.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.example.haku.service.HakuForegroundService

/**
 * 🔌 Charging Broadcast Receiver
 *
 * รับ event เมื่อเสียบ/ถอดชาร์จ แล้วสั่งให้ HakuForegroundService ทำงาน
 * ทำงานได้แม้แอพปิด (OS-level broadcast)
 */
class ChargingBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "HakuCharging"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_POWER_CONNECTED -> {
                Log.i(TAG, "🔌 Power connected — starting background service")
                startService(context, HakuForegroundService.ACTION_CHARGING_CONNECTED)
            }
            Intent.ACTION_POWER_DISCONNECTED -> {
                Log.i(TAG, "🔌 Power disconnected — stopping non-urgent work")
                startService(context, HakuForegroundService.ACTION_CHARGING_DISCONNECTED)
            }
        }
    }

    private fun startService(context: Context, action: String) {
        val serviceIntent = Intent(context, HakuForegroundService::class.java).apply {
            this.action = action
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start service: ${e.message}")
        }
    }
}
