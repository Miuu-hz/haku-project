package com.example.haku.service

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import com.example.haku.LiteRTLMBridge
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * 🎗️ Haku Foreground Service
 *
 * ทำงานเบื้องหลังสำหรับ:
 * - รองรับ BootReceiver / ChargingBroadcastReceiver
 * - แชร์ LLM engine instance ผ่าน HakuServiceBinder
 * - ประมวลผล background tasks (defer to charging ฯลฯ)
 * - สื่อสารกับ Flutter ผ่าน FlutterEngine + MethodChannel
 */
class HakuForegroundService : Service() {

    companion object {
        private const val TAG = "HakuFgService"

        const val ACTION_RESUME_PENDING = "com.example.haku.ACTION_RESUME_PENDING"
        const val ACTION_CHARGING_CONNECTED = "com.example.haku.ACTION_CHARGING_CONNECTED"
        const val ACTION_CHARGING_DISCONNECTED = "com.example.haku.ACTION_CHARGING_DISCONNECTED"

        private const val FOREGROUND_CHANNEL = "com.example.haku/foreground"
    }

    private val binder = HakuServiceBinder(this)

    /** บอกว่า service กำลังประมวลผลอยู่หรือไม่ */
    @Volatile
    var isProcessing: Boolean = false
        private set

    private var llmEngine: LiteRTLMBridge? = null
    private var flutterEngine: FlutterEngine? = null

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
                Log.i(TAG, "📋 Resuming pending tasks...")
                // TODO: รีซูมงานค้างจากตอนแอพถูก kill
            }
            ACTION_CHARGING_CONNECTED -> {
                handleChargingConnected()
            }
            ACTION_CHARGING_DISCONNECTED -> {
                Log.i(TAG, "🔌 Charging disconnected — pausing non-urgent work")
                destroyFlutterEngine()
            }
        }

        return START_STICKY
    }

    /**
     * 🔌 Handle charging connected — สร้าง FlutterEngine แล้วส่ง event ไป Dart
     */
    private fun handleChargingConnected() {
        Log.i(TAG, "🔌 Charging connected — starting background processing")

        // แสดง progress notification ทันที (reliable)
        val notification = BackgroundNotificationHelper.buildTaskCompleteNotification(
            this, "charging", "กำลังประมวลผลสรุปวันนี้..."
        )
        BackgroundNotificationHelper.showNotification(this, 777, notification)

        try {
            // สร้าง FlutterEngine ใหม่สำหรับ background
            val engine = FlutterEngine(this)
            flutterEngine = engine

            val bundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()

            // รัน Dart entrypoint แยกสำหรับ background
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(bundlePath, "chargingBackgroundMain")
            )

            // ⏳ ให้ Dart engine ตั้ง MethodChannel handler ก่อน (3 วินาที)
            // ถ้า invoke ทันทีจะเกิด race condition — handler ยังไม่พร้อม
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    MethodChannel(engine.dartExecutor.binaryMessenger, FOREGROUND_CHANNEL)
                        .invokeMethod("chargingConnected", mapOf("timestamp" to System.currentTimeMillis()))
                    Log.i(TAG, "✅ Sent chargingConnected to Dart engine")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ invokeMethod failed: ${e.message}")
                    destroyFlutterEngine()
                    stopSelf()
                }

                // หยุด engine อัตโนมัติหลัง 120 วินาที (Dart จะทำงานเสร็จภายในนั้น)
                Handler(Looper.getMainLooper()).postDelayed({
                    Log.i(TAG, "⏱ Charging process timeout — stopping engine")
                    destroyFlutterEngine()
                    stopSelf()
                }, 120_000L)

            }, 3_000L)

            Log.i(TAG, "✅ FlutterEngine started, waiting 3s before invokeMethod")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start FlutterEngine for charging: ${e.message}")
            e.printStackTrace()
            stopSelf()
        }
    }

    /**
     * 🧹 ทำลาย FlutterEngine เมื่อไม่ต้องการแล้ว
     */
    private fun destroyFlutterEngine() {
        flutterEngine?.let {
            Log.i(TAG, "🧹 Destroying FlutterEngine")
            it.destroy()
            flutterEngine = null
        }
    }

    override fun onDestroy() {
        Log.i(TAG, "🛑 HakuForegroundService destroyed")
        destroyFlutterEngine()
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
