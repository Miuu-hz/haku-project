package com.example.haku.service

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import android.util.Log
import com.example.haku.LiteRTLMBridge

/**
 * 🎗️ Haku Foreground Service
 *
 * ทำงานเบื้องหลังสำหรับ:
 * - รองรับ BootReceiver / ChargingBroadcastReceiver
 * - แชร์ LLM engine instance ผ่าน HakuServiceBinder
 * - ประมวลผล background tasks (defer to charging ฯลฯ)
 */
class HakuForegroundService : Service() {

    companion object {
        private const val TAG = "HakuFgService"

        const val ACTION_RESUME_PENDING = "com.example.haku.ACTION_RESUME_PENDING"
        const val ACTION_CHARGING_CONNECTED = "com.example.haku.ACTION_CHARGING_CONNECTED"
        const val ACTION_CHARGING_DISCONNECTED = "com.example.haku.ACTION_CHARGING_DISCONNECTED"
    }

    private val binder = HakuServiceBinder(this)

    /** บอกว่า service กำลังประมวลผลอยู่หรือไม่ */
    @Volatile
    var isProcessing: Boolean = false
        private set

    private var llmEngine: LiteRTLMBridge? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "🚀 HakuForegroundService created")
        BackgroundNotificationHelper.createChannels(this)
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        Log.i(TAG, "📥 onStartCommand: $action")

        // สร้าง foreground notification ตาม requirement ของ Android 8+
        val notification = BackgroundNotificationHelper.buildForegroundNotification(this)
        startForeground(1, notification)

        when (action) {
            ACTION_RESUME_PENDING -> {
                // TODO: ร.resume pending background tasks
                Log.i(TAG, "📋 Resuming pending tasks...")
            }
            ACTION_CHARGING_CONNECTED -> {
                // TODO: เริ่มประมวลผล heavy tasks ที่ defer ไว้
                Log.i(TAG, "🔌 Charging connected — ready for heavy tasks")
            }
            ACTION_CHARGING_DISCONNECTED -> {
                // TODO: หยุด heavy tasks ที่ไม่จำเป็น
                Log.i(TAG, "🔌 Charging disconnected — pausing non-urgent work")
            }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "🛑 HakuForegroundService destroyed")
        super.onDestroy()
    }

    /**
     * ดึง/สร้าง LLM engine instance (lazy singleton)
     */
    fun getLLMEngine(): LiteRTLMBridge? {
        if (llmEngine == null) {
            llmEngine = LiteRTLMBridge.getInstance(this)
        }
        return llmEngine
    }

    /**
     * ตั้งค่า processing state (เรียกจาก background workers)
     */
    fun setProcessing(processing: Boolean) {
        isProcessing = processing
    }
}
