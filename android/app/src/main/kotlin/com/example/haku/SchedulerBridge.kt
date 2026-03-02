package com.example.haku

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.CalendarContract
import android.util.Log
import java.util.TimeZone

/**
 * 📅 SchedulerBridge - จัดการ Calendar Events และ Reminders
 * 
 * ทำหน้าที่เป็น bridge ระหว่าง Flutter (Dart) -> Android Calendar API
 */
object SchedulerBridge {
    
    private const val TAG = "HakuScheduler"
    
    /**
     * 📅 สร้าง Event ใน Calendar
     * 
     * @param context Application context
     * @param title ชื่อกิจกรรม
     * @param description รายละเอียด
     * @param startTime เวลาเริ่มต้น (milliseconds since epoch)
     * @param endTime เวลาสิ้นสุด (milliseconds since epoch)
     * @param location สถานที่ (optional)
     * @return event ID ถ้าสำเร็จ, null ถ้าไม่สำเร็จ
     */
    fun createCalendarEvent(
        context: Context,
        title: String,
        description: String,
        startTime: Long,
        endTime: Long,
        location: String? = null
    ): Long? {
        try {
            Log.i(TAG, "📅 Creating calendar event: $title")
            
            val values = ContentValues().apply {
                put(CalendarContract.Events.DTSTART, startTime)
                put(CalendarContract.Events.DTEND, endTime)
                put(CalendarContract.Events.TITLE, title)
                put(CalendarContract.Events.DESCRIPTION, description)
                put(CalendarContract.Events.CALENDAR_ID, getPrimaryCalendarId(context))
                put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                
                if (!location.isNullOrEmpty()) {
                    put(CalendarContract.Events.EVENT_LOCATION, location)
                }
            }
            
            val uri: Uri? = context.contentResolver.insert(
                CalendarContract.Events.CONTENT_URI,
                values
            )
            
            if (uri != null) {
                val eventId = uri.lastPathSegment?.toLongOrNull()
                Log.i(TAG, "✅ Event created with ID: $eventId")
                return eventId
            } else {
                Log.e(TAG, "❌ Failed to insert event")
                return null
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error creating event: ${e.message}")
            return null
        }
    }
    
    /**
     * ⏰ ตั้ง Reminder สำหรับ Event
     * 
     * @param context Application context
     * @param eventId ID ของ event
     * @param minutesBefore จำนวนนาทีก่อนเริ่ม event (default: 15 นาที)
     * @return true ถ้าสำเร็จ
     */
    fun addReminder(
        context: Context,
        eventId: Long,
        minutesBefore: Int = 15
    ): Boolean {
        try {
            Log.i(TAG, "⏰ Adding reminder for event $eventId ($minutesBefore min before)")
            
            val values = ContentValues().apply {
                put(CalendarContract.Reminders.EVENT_ID, eventId)
                put(CalendarContract.Reminders.MINUTES, minutesBefore)
                put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
            }
            
            val uri: Uri? = context.contentResolver.insert(
                CalendarContract.Reminders.CONTENT_URI,
                values
            )
            
            return if (uri != null) {
                Log.i(TAG, "✅ Reminder added")
                true
            } else {
                Log.e(TAG, "❌ Failed to add reminder")
                false
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error adding reminder: ${e.message}")
            return false
        }
    }
    
    /**
     * 🔍 ดึง Primary Calendar ID
     */
    private fun getPrimaryCalendarId(context: Context): Long {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.IS_PRIMARY
        )
        
        try {
            context.contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                projection,
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idColumn = cursor.getColumnIndex(CalendarContract.Calendars._ID)
                    return cursor.getLong(idColumn)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting calendar ID: ${e.message}")
        }
        
        // Default calendar ID ถ้าหาไม่เจอ
        return 1L
    }
    
    /**
     * ✅ ตรวจสอบว่ามี Calendar Permission หรือไม่
     */
    fun hasCalendarPermission(context: Context): Boolean {
        val permission = android.Manifest.permission.WRITE_CALENDAR
        return context.checkSelfPermission(permission) == 
               android.content.pm.PackageManager.PERMISSION_GRANTED
    }
    
    /**
     * 📋 ขอ Calendar Permission
     */
    fun requestCalendarPermission(activity: MainActivity, requestCode: Int = 1001) {
        activity.requestPermissions(
            arrayOf(
                android.Manifest.permission.READ_CALENDAR,
                android.Manifest.permission.WRITE_CALENDAR
            ),
            requestCode
        )
    }
    
    /**
     * 🗑️ ลบ Event
     * 
     * @param context Application context
     * @param eventId ID ของ event ที่จะลบ
     * @return true ถ้าสำเร็จ
     */
    fun deleteEvent(context: Context, eventId: Long): Boolean {
        try {
            Log.i(TAG, "🗑️ Deleting event: $eventId")
            
            val rows = context.contentResolver.delete(
                CalendarContract.Events.CONTENT_URI,
                "${CalendarContract.Events._ID} = ?",
                arrayOf(eventId.toString())
            )
            
            return if (rows > 0) {
                Log.i(TAG, "✅ Event deleted")
                true
            } else {
                Log.e(TAG, "❌ Event not found")
                false
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error deleting event: ${e.message}")
            return false
        }
    }
    
    /**
     * 📊 ดึงรายการ Events ในช่วงเวลา
     * 
     * @param context Application context
     * @param startTime เริ่มต้น (milliseconds)
     * @param endTime สิ้นสุด (milliseconds)
     * @return List ของ events (Map)
     */
    fun getEvents(
        context: Context,
        startTime: Long,
        endTime: Long
    ): List<Map<String, Any?>> {
        val events = mutableListOf<Map<String, Any?>>()
        
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.EVENT_LOCATION
        )
        
        val selection = "${CalendarContract.Events.DTSTART} >= ? AND ${CalendarContract.Events.DTSTART} <= ?"
        val selectionArgs = arrayOf(startTime.toString(), endTime.toString())
        
        try {
            context.contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                "${CalendarContract.Events.DTSTART} ASC"
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val event = mapOf(
                        "id" to cursor.getLong(0),
                        "title" to cursor.getString(1),
                        "description" to cursor.getString(2),
                        "startTime" to cursor.getLong(3),
                        "endTime" to cursor.getLong(4),
                        "location" to cursor.getString(5)
                    )
                    events.add(event)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting events: ${e.message}")
        }
        
        return events
    }
    
    /**
     * ⏰ ตั้งนาฬิกาปลุกอัตโนมัติ (Smart Sleep-Prep)
     * 
     * ใช้ AlarmClock Intent — ตั้งปลุกเงียบๆ (SKIP_UI=true) ไม่เปิดแอปนาฬิกา
     * 
     * @param context Application context
     * @param hour ชั่วโมง (0-23)
     * @param minute นาที (0-59)
     * @param label ข้อความปลุก (optional)
     * @return true ถ้าส่ง intent สำเร็จ
     */
    fun setAlarm(
        context: Context,
        hour: Int,
        minute: Int,
        label: String = "Haku: เวลาตื่นแล้ว!"
    ): Boolean {
        try {
            Log.i(TAG, "⏰ Setting alarm: $hour:${minute.toString().padStart(2, '0')} — $label")
            
            val intent = Intent(android.provider.AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(android.provider.AlarmClock.EXTRA_HOUR, hour)
                putExtra(android.provider.AlarmClock.EXTRA_MINUTES, minute)
                putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, label)
                putExtra(android.provider.AlarmClock.EXTRA_SKIP_UI, true)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            
            context.startActivity(intent)
            Log.i(TAG, "✅ Alarm set for $hour:${minute.toString().padStart(2, '0')}")
            return true
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting alarm: ${e.message}")
            return false
        }
    }
}
