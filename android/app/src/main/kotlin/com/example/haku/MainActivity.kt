package com.example.haku

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.util.Log
import com.example.haku.receiver.NotificationAlarmReceiver
import kotlinx.coroutines.*

/**
 * 🎌 MainActivity ของ Haku
 * 
 * รองรับ:
 * - การรับข้อมูลจาก Widget
 * - LLM MethodChannel (com.example.haku/llm)
 */

class MainActivity: FlutterFragmentActivity() {
    
    companion object {
        private const val TAG = "HakuMain"
        private const val WIDGET_CHANNEL = "com.example.haku/widget"
        private const val LLM_CHANNEL = "com.example.haku/llm"
        private const val SCHEDULER_CHANNEL = "com.example.haku/scheduler"
        private const val BATTERY_CHANNEL = "com.example.haku/battery"
        private const val DEVICE_CHANNEL = "com.example.haku/device"
        private const val REQUEST_BATTERY_OPTIMIZATION = 1001
    }
    
    private var pendingWidgetAction: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        setupWidgetChannel(flutterEngine)
        setupLLMChannel(flutterEngine)
        setupSchedulerChannel(flutterEngine)
        setupBatteryChannel(flutterEngine)
        setupDeviceCommandChannel(flutterEngine)
    }

    /**
     * 📅 Setup Scheduler MethodChannel
     */
    private fun setupSchedulerChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCHEDULER_CHANNEL).setMethodCallHandler {
            call, result ->
            try {
                when (call.method) {
                    "createEvent" -> {
                        val title = call.argument<String>("title")
                        val description = call.argument<String>("description") ?: ""
                        val startTime = call.argument<Long>("startTime")
                        val endTime = call.argument<Long>("endTime")
                        val location = call.argument<String>("location")
                        val addReminder = call.argument<Boolean>("addReminder") ?: true
                        val reminderMinutes = call.argument<Int>("reminderMinutes") ?: 15
                        
                        if (title == null || startTime == null || endTime == null) {
                            result.error("INVALID_PARAMS", "Missing required parameters", null)
                            return@setMethodCallHandler
                        }
                        
                        // Check permission
                        if (!SchedulerBridge.hasCalendarPermission(this)) {
                            SchedulerBridge.requestCalendarPermission(this)
                            result.error("NO_PERMISSION", "Calendar permission not granted", null)
                            return@setMethodCallHandler
                        }
                        
                        Log.i(TAG, "📅 Creating event: $title")
                        val eventId = SchedulerBridge.createCalendarEvent(
                            this,
                            title,
                            description,
                            startTime,
                            endTime,
                            location
                        )
                        
                        if (eventId != null && addReminder) {
                            SchedulerBridge.addReminder(this, eventId, reminderMinutes)
                        }
                        
                        result.success(eventId)
                    }
                    
                    "addReminder" -> {
                        val eventId = call.argument<Long>("eventId")
                        val minutesBefore = call.argument<Int>("minutesBefore") ?: 15
                        
                        if (eventId == null) {
                            result.error("INVALID_PARAMS", "eventId is null", null)
                            return@setMethodCallHandler
                        }
                        
                        val success = SchedulerBridge.addReminder(this, eventId, minutesBefore)
                        result.success(success)
                    }
                    
                    "deleteEvent" -> {
                        val eventId = call.argument<Long>("eventId")
                        
                        if (eventId == null) {
                            result.error("INVALID_PARAMS", "eventId is null", null)
                            return@setMethodCallHandler
                        }
                        
                        val success = SchedulerBridge.deleteEvent(this, eventId)
                        result.success(success)
                    }
                    
                    "getEvents" -> {
                        val startTime = call.argument<Long>("startTime")
                        val endTime = call.argument<Long>("endTime")
                        
                        if (startTime == null || endTime == null) {
                            result.error("INVALID_PARAMS", "Missing time range", null)
                            return@setMethodCallHandler
                        }
                        
                        val events = SchedulerBridge.getEvents(this, startTime, endTime)
                        result.success(events)
                    }
                    
                    "hasPermission" -> {
                        result.success(SchedulerBridge.hasCalendarPermission(this))
                    }
                    
                    "requestPermission" -> {
                        SchedulerBridge.requestCalendarPermission(this)
                        result.success(null)
                    }
                    
                    "setAlarm" -> {
                        val hour = call.argument<Int>("hour")
                        val minute = call.argument<Int>("minute")
                        val label = call.argument<String>("label") ?: "Haku: เวลาตื่นแล้ว!"
                        
                        if (hour == null || minute == null) {
                            result.error("INVALID_PARAMS", "Missing hour or minute", null)
                            return@setMethodCallHandler
                        }
                        
                        Log.i(TAG, "⏰ Setting alarm: $hour:$minute")
                        val success = SchedulerBridge.setAlarm(this, hour, minute, label)
                        result.success(success)
                    }
                    
                    "scheduleReminder" -> {
                        val title = call.argument<String>("title") ?: "Haku"
                        val body = call.argument<String>("body") ?: ""
                        val triggerMinutes = call.argument<Int>("triggerMinutes") ?: 15

                        val triggerMs = System.currentTimeMillis() + (triggerMinutes * 60 * 1000L)
                        val alarmIntent = Intent(this, NotificationAlarmReceiver::class.java).apply {
                            putExtra(NotificationAlarmReceiver.EXTRA_TITLE, title)
                            putExtra(NotificationAlarmReceiver.EXTRA_BODY, body)
                        }
                        val pendingIntent = PendingIntent.getBroadcast(
                            this,
                            triggerMs.toInt(),
                            alarmIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP, triggerMs, pendingIntent
                        )
                        Log.i(TAG, "⏰ Reminder scheduled in $triggerMinutes min: $title")
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error in Scheduler method ${call.method}: ${e.message}")
                result.error("SCHEDULER_ERROR", e.message, e.stackTraceToString())
            }
        }
    }
    
    /**
     * 🔌 Setup Widget MethodChannel
     */
    private fun setupWidgetChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "getWidgetAction" -> {
                    // ส่งข้อมูล action จาก widget ไปให้ Flutter
                    result.success(pendingWidgetAction)
                    pendingWidgetAction = null  // เคลียร์หลังอ่าน
                }
                "updateWidget" -> {
                    // อัพเดท widget จาก Flutter
                    updateWidgets()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    /**
     * 🤖 Setup LLM MethodChannel — LiteRT-LM (แทน MediaPipe ที่ deprecated)
     *
     * Methods:
     *   loadModel(modelPath, maxTokens, systemInstruction?)  → bool
     *   generate(prompt)                                     → String   [stateless, one-shot]
     *   generateTurn(prompt)                                 → String   [stateful, KV cache]
     *   resetConversation()                                  → null     [เริ่ม session ใหม่]
     *   setSystemInstruction(instruction?)                   → null
     *   unloadModel()                                        → null
     *   isModelLoaded()                                      → bool
     *   getModelInfo()                                       → Map
     */
    private fun setupLLMChannel(flutterEngine: FlutterEngine) {
        val llmBridge = LiteRTLMBridge.getInstance(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LLM_CHANNEL).setMethodCallHandler {
            call, result ->

            try {
                when (call.method) {
                    "loadModel" -> {
                        val modelPath = call.argument<String>("modelPath")
                        val maxTokens = call.argument<Int>("maxTokens") ?: 1024
                        val systemInstruction = call.argument<String>("systemInstruction")
                        val accelerator = call.argument<String>("accelerator") ?: "GPU"

                        if (modelPath == null) {
                            result.error("INVALID_PATH", "Model path is null", null)
                            return@setMethodCallHandler
                        }

                        Log.i(TAG, "📥 Loading LiteRT-LM model: $modelPath (accelerator=$accelerator)")

                        CoroutineScope(Dispatchers.Main).launch {
                            val success = llmBridge.loadModel(
                                modelPath = modelPath,
                                maxTokens = maxTokens,
                                systemInstruction = systemInstruction,
                                accelerator = accelerator,
                            )
                            result.success(success)
                        }
                    }

                    "generate" -> {
                        val prompt = call.argument<String>("prompt")

                        if (prompt == null) {
                            result.error("INVALID_PROMPT", "Prompt is null", null)
                            return@setMethodCallHandler
                        }

                        if (!llmBridge.isInitialized) {
                            result.error("NOT_INITIALIZED", "LiteRT-LM not initialized", null)
                            return@setMethodCallHandler
                        }

                        // อ่าน sampler parameters จาก Dart (optional)
                        val temperature = call.argument<Double>("temperature")
                        val topK = call.argument<Int>("topK")
                        val topP = call.argument<Double>("topP")
                        llmBridge.setSamplerParams(temperature, topK, topP)

                        CoroutineScope(Dispatchers.Main).launch {
                            val response = llmBridge.generate(prompt)
                            result.success(response)
                        }
                    }

                    // 💬 Stateful generate — ใช้ KV cache ต่อ session
                    "generateTurn" -> {
                        val prompt = call.argument<String>("prompt")

                        if (prompt == null) {
                            result.error("INVALID_PROMPT", "Prompt is null", null)
                            return@setMethodCallHandler
                        }

                        if (!llmBridge.isInitialized) {
                            result.error("NOT_INITIALIZED", "LiteRT-LM not initialized", null)
                            return@setMethodCallHandler
                        }

                        val temperature = call.argument<Double>("temperature")
                        val topK = call.argument<Int>("topK")
                        val topP = call.argument<Double>("topP")
                        llmBridge.setSamplerParams(temperature, topK, topP)

                        CoroutineScope(Dispatchers.Main).launch {
                            val response = llmBridge.generateTurn(prompt)
                            result.success(response)
                        }
                    }

                    // 🔄 รีเซ็ต Conversation — เริ่ม session ใหม่
                    "resetConversation" -> {
                        llmBridge.resetConversation()
                        result.success(null)
                    }

                    // ตั้ง system prompt โดยไม่ต้อง reload โมเดล (รีเซ็ต conversation อัตโนมัติ)
                    "setSystemInstruction" -> {
                        val instruction = call.argument<String>("instruction")
                        llmBridge.setSystemInstruction(instruction)
                        result.success(null)
                    }

                    "unloadModel" -> {
                        llmBridge.unloadModel()
                        result.success(null)
                    }

                    "isModelLoaded" -> {
                        result.success(llmBridge.isInitialized)
                    }

                    "getModelInfo" -> {
                        result.success(llmBridge.getModelInfo())
                    }

                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error in LLM method ${call.method}: ${e.message}")
                result.error("LLM_ERROR", e.message, e.stackTraceToString())
            }
        }
    }

    /**
     * 🔋 Setup Battery Optimization MethodChannel
     */
    private fun setupBatteryChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).setMethodCallHandler {
            call, result ->
            try {
                when (call.method) {
                    "checkStatus" -> {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            powerManager.isIgnoringBatteryOptimizations(packageName)
                        } else {
                            true // API < 23 ไม่มี battery optimization
                        }
                        val canRequest = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M

                        result.success(mapOf(
                            "isIgnoringBatteryOptimizations" to isIgnoring,
                            "canRequest" to canRequest,
                            "manufacturer" to Build.MANUFACTURER
                        ))
                    }

                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivityForResult(intent, REQUEST_BATTERY_OPTIMIZATION)
                            // จริงๆ ควรรอ onActivityResult แต่เพื่อความง่าย return true แล้วให้ Dart ตรวจสอบเอง
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    }

                    "openBatterySettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Fallback ถ้า settings ไม่รองรับ
                            val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(fallbackIntent)
                            result.success(true)
                        }
                    }

                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error in battery method ${call.method}: ${e.message}")
                result.error("BATTERY_ERROR", e.message, e.stackTraceToString())
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_BATTERY_OPTIMIZATION) {
            // User กลับมาจาก system dialog
            // Dart จะตรวจสอบสถานะเองผ่าน checkStatus()
            Log.i(TAG, "🔋 Battery optimization dialog returned: resultCode=$resultCode")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleWidgetIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleWidgetIntent(intent)
    }

    /**
     * 🔧 Setup Device Command MethodChannel
     *
     * ให้ Flutter สั่งงาน smartphone ได้: flashlight, open app, dial, SMS, settings, etc.
     */
    private fun setupDeviceCommandChannel(flutterEngine: FlutterEngine) {
        val handler = DeviceCommandHandler(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL).setMethodCallHandler {
            call, result ->
            try {
                when (call.method) {
                    "execute" -> {
                        val command = call.argument<String>("command")
                        val params = call.argument<Map<String, Any>>("params")
                        if (command != null) {
                            val outcome = handler.execute(command, params ?: emptyMap())
                            result.success(outcome)
                        } else {
                            result.error("INVALID", "Missing command", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error in device command ${call.method}: ${e.message}")
                result.error("DEVICE_ERROR", e.message, e.stackTraceToString())
            }
        }
    }

    /**
     * 📱 จัดการ Intent ที่ส่งมาจาก Widget
     */
    private fun handleWidgetIntent(intent: Intent?) {
        intent?.let {
            val action = it.getStringExtra("widget_action")
            val question = it.getStringExtra("question")
            
            if (action != null) {
                pendingWidgetAction = mapOf(
                    "action" to action,
                    "question" to (question ?: "")
                )
            }
        }
    }

    /**
     * 🔄 บังคับอัพเดท widget ทั้งหมด
     */
    private fun updateWidgets() {
        val appWidgetManager = AppWidgetManager.getInstance(this)
        val componentName = ComponentName(this, HakuWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        
        // ส่ง broadcast ให้ widget อัพเดต
        val intent = Intent(this, HakuWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
        }
        sendBroadcast(intent)
    }
    
    override fun onDestroy() {
        super.onDestroy()
    }
}
