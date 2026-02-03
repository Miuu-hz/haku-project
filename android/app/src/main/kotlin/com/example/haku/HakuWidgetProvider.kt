package com.example.haku

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.net.Uri
import android.app.PendingIntent

/**
 * 🎌 Haku Widget Provider - วิดเจ็ตหน้า Home สำหรับ Android
 * 
 * รองรับ 2 ขนาด:
 * - 4x2: แสดงคำถามสำเร็จรูปแบบลัด
 * - 4x3: แสดงประวัติแชทล่าสุด + คำถาม
 */

class HakuWidgetProvider : AppWidgetProvider() {
    
    companion object {
        const val ACTION_ASK_QUESTION = "com.example.haku.ASK_QUESTION"
        const val ACTION_OPEN_CHAT = "com.example.haku.OPEN_CHAT"
        const val ACTION_NEW_ENTRY = "com.example.haku.NEW_ENTRY"
        const val EXTRA_QUESTION = "extra_question"
        
        // 📝 คำถามสำเร็จรูปที่แสดงในวิดเจ็ต
        val QUICK_QUESTIONS = listOf(
            "🍜 กินอะไรมา?",
            "😊 วันนี้เป็นยังไง?",
            "📍 ไปไหนมาบ้าง?",
            "🎵 อารมณ์ดีไหม?",
            "📅 เมื่อวานทำอะไร?",
            "💤 นอนดีไหม?"
        )
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        when (intent.action) {
            ACTION_ASK_QUESTION -> {
                val question = intent.getStringExtra(EXTRA_QUESTION) ?: return
                // เปิดแอพพร้อมส่งคำถามไปให้ AI
                openAppWithQuestion(context, question)
            }
            ACTION_OPEN_CHAT -> {
                openApp(context, "chat")
            }
            ACTION_NEW_ENTRY -> {
                openApp(context, "new_entry")
            }
        }
    }

    private fun openAppWithQuestion(context: Context, question: String) {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        intent?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("widget_action", "ask")
            putExtra("question", question)
        }
        context.startActivity(intent)
    }

    private fun openApp(context: Context, action: String) {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        intent?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("widget_action", action)
        }
        context.startActivity(intent)
    }
}

/**
 * อัพเดท Widget ตามขนาดที่กำหนด
 */
fun updateAppWidget(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int
) {
    val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
    val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
    val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
    
    // เลือก layout ตามขนาด
    val layoutId = when {
        height >= 180 -> R.layout.widget_4x3  // สูงพอสำหรับ 4x3
        else -> R.layout.widget_4x2           // ปกติใช้ 4x2
    }
    
    val views = RemoteViews(context.packageName, layoutId)
    
    // 🎨 ตั้งค่าสีตามธีม
    setupWidgetViews(context, views, layoutId)
    
    appWidgetManager.updateAppWidget(appWidgetId, views)
}

/**
 * ตั้งค่า View ต่างๆ ในวิดเจ็ต
 */
private fun setupWidgetViews(context: Context, views: RemoteViews, layoutId: Int) {
    // 🔘 ปุ่มเปิดแชท
    val chatIntent = Intent(context, HakuWidgetProvider::class.java).apply {
        action = HakuWidgetProvider.ACTION_OPEN_CHAT
    }
    val chatPendingIntent = PendingIntent.getBroadcast(
        context, 0, chatIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    views.setOnClickPendingIntent(R.id.btn_chat, chatPendingIntent)
    
    // 🔘 ปุ่มเขียนใหม่
    val newEntryIntent = Intent(context, HakuWidgetProvider::class.java).apply {
        action = HakuWidgetProvider.ACTION_NEW_ENTRY
    }
    val newEntryPendingIntent = PendingIntent.getBroadcast(
        context, 1, newEntryIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    views.setOnClickPendingIntent(R.id.btn_new_entry, newEntryPendingIntent)
    
    // 📝 ตั้งค่าปุ่มคำถามสำเร็จรูป (สูงสุด 6 คำถาม)
    val questionIds = listOf(
        R.id.btn_q1, R.id.btn_q2, R.id.btn_q3,
        R.id.btn_q4, R.id.btn_q5, R.id.btn_q6
    )
    
    HakuWidgetProvider.QUICK_QUESTIONS.forEachIndexed { index, question ->
        if (index < questionIds.size) {
            val questionIntent = Intent(context, HakuWidgetProvider::class.java).apply {
                action = HakuWidgetProvider.ACTION_ASK_QUESTION
                putExtra(HakuWidgetProvider.EXTRA_QUESTION, question)
            }
            val questionPendingIntent = PendingIntent.getBroadcast(
                context, 100 + index, questionIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            views.setTextViewText(questionIds[index], question)
            views.setOnClickPendingIntent(questionIds[index], questionPendingIntent)
        }
    }
}
