package com.example.haku

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.Intent
import android.os.Bundle
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.util.Log
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
    }
    
    private var pendingWidgetAction: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        setupWidgetChannel(flutterEngine)
        setupLLMChannel(flutterEngine)
        setupSchedulerChannel(flutterEngine)
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
     * 🤖 Setup LLM MethodChannel สำหรับ MediaPipe
     * 
     * ใช้ MediaPipe GenAI แทน llama.cpp + Vulkan
     */
    private fun setupLLMChannel(flutterEngine: FlutterEngine) {
        val mediaPipeBridge = MediaPipeLLMBridge.getInstance(this)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LLM_CHANNEL).setMethodCallHandler {
            call, result ->
            
            try {
                when (call.method) {
                    "loadModel" -> {
                        val modelPath = call.argument<String>("modelPath")
                        val maxTokens = call.argument<Int>("maxTokens") ?: 1024
                        
                        if (modelPath == null) {
                            result.error("INVALID_PATH", "Model path is null", null)
                            return@setMethodCallHandler
                        }
                        
                        Log.i(TAG, "📥 Loading MediaPipe model: $modelPath")
                        
                        CoroutineScope(Dispatchers.Main).launch {
                            val success = mediaPipeBridge.loadModel(
                                modelPath = modelPath,
                                maxTokens = maxTokens
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
                        
                        if (!mediaPipeBridge.isInitialized) {
                            result.error("NOT_INITIALIZED", "MediaPipe not initialized", null)
                            return@setMethodCallHandler
                        }
                        
                        CoroutineScope(Dispatchers.Main).launch {
                            val response = mediaPipeBridge.generate(prompt)
                            result.success(response)
                        }
                    }
                    
                    "unloadModel" -> {
                        mediaPipeBridge.unloadModel()
                        result.success(null)
                    }
                    
                    "isModelLoaded" -> {
                        result.success(mediaPipeBridge.isInitialized)
                    }
                    
                    "getModelInfo" -> {
                        result.success(mediaPipeBridge.getModelInfo())
                    }
                    
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error in MediaPipe method ${call.method}: ${e.message}")
                result.error("MEDIAPIPE_ERROR", e.message, e.stackTraceToString())
            }
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
        // 📝 llama.cpp ถูกปิดการใช้งานแล้ว ไม่ต้อง unload model
    }
}
