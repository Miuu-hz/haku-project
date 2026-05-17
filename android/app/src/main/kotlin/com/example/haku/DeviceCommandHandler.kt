package com.example.haku

import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.provider.AlarmClock
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import androidx.core.net.toUri
import org.json.JSONObject

/**
 * 🔧 DeviceCommandHandler — รันคำสั่ง smartphone ทั้งหมด
 *
 * แบ่งเป็น 3 กลุ่ม:
 *   A. Intent-based: เปิด app, โทร, SMS, เปิด settings (ไม่ต้อง permission)
 *   B. System API: Flashlight, Battery, Network (ต้อง permission)
 *   C. Query: อ่านสถานะเซ็นเซอร์ต่างๆ
 *
 * อ้างอิงจาก Google AI Edge Gallery: AgentTools.runIntent()
 */
class DeviceCommandHandler(private val context: Context) {

    companion object {
        private const val TAG = "HakuDeviceCmd"
    }

    private val cameraManager by lazy {
        context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    }

    private val batteryManager by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        } else null
    }

    /**
     * 🎛️ Entry point — รับ command string + params map แล้ว dispatch
     */
    fun execute(command: String, params: Map<String, Any?>): Map<String, Any?> {
        Log.i(TAG, "▶️ execute: $command | params=$params")

        return try {
            when (command) {
                // ─── Flashlight ───
                "flashlight_on" -> flashlight(true)
                "flashlight_off" -> flashlight(false)
                "flashlight_toggle" -> flashlightToggle()

                // ─── App / Communication ───
                "open_app" -> openApp(params)
                "dial_phone" -> dialPhone(params)
                "send_sms" -> sendSms(params)
                "send_email" -> sendEmail(params)
                "open_url" -> openUrl(params)
                "open_camera" -> openCamera()
                "open_gallery" -> openGallery()

                // ─── Settings ───
                "open_settings" -> openSettings(params)
                "open_wifi_settings" -> openSettings(mapOf("type" to "wifi"))
                "open_bluetooth_settings" -> openSettings(mapOf("type" to "bluetooth"))
                "open_location_settings" -> openSettings(mapOf("type" to "location"))
                "open_battery_settings" -> openSettings(mapOf("type" to "battery"))
                "open_sound_settings" -> openSettings(mapOf("type" to "sound"))
                "open_display_settings" -> openSettings(mapOf("type" to "display"))
                "open_security_settings" -> openSettings(mapOf("type" to "security"))
                "open_developer_settings" -> openSettings(mapOf("type" to "developer"))

                // ─── System Apps ───
                "open_calendar" -> openCalendar()
                "open_clock" -> openClock()
                "open_calculator" -> openCalculator()
                "open_maps" -> openMaps(params)

                // ─── Share / Contact ───
                "share_text" -> shareText(params)
                "create_contact" -> createContact(params)

                // ─── Queries ───
                "get_battery_level" -> getBatteryLevel()
                "get_network_status" -> getNetworkStatus()

                else -> mapOf(
                    "success" to false,
                    "error" to "Unknown command: $command"
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Command failed: $command", e)
            mapOf("success" to false, "error" to (e.message ?: "Unknown error"))
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  A. Flashlight (System API)
    // ═══════════════════════════════════════════════════════════════════

    private fun flashlight(on: Boolean): Map<String, Any?> {
        return try {
            val cameraId = cameraManager.cameraIdList.firstOrNull()
                ?: return mapOf("success" to false, "error" to "No camera found")
            cameraManager.setTorchMode(cameraId, on)
            mapOf("success" to true, "state" to if (on) "on" else "off")
        } catch (e: Exception) {
            mapOf("success" to false, "error" to e.message)
        }
    }

    private fun flashlightToggle(): Map<String, Any?> {
        // ไม่มี API อ่านสถานะ torch โดยตรง ให้ Flutter track state เอง
        // แต่ถ้าจะ toggle ต้องรู้ state ปัจจุบัน → ส่งให้ Flutter จัดการ
        return mapOf(
            "success" to false,
            "error" to "Use flashlight_on/off explicitly, or track state in Flutter"
        )
    }

    // ═══════════════════════════════════════════════════════════════════
    //  B. Intent-based Commands
    // ═══════════════════════════════════════════════════════════════════

    private fun openApp(params: Map<String, Any?>): Map<String, Any?> {
        val packageName = params["packageName"] as? String
            ?: return mapOf("success" to false, "error" to "Missing packageName")

        val intent = context.packageManager.getLaunchIntentForPackage(packageName)
            ?: return mapOf("success" to false, "error" to "App not found: $packageName")

        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return mapOf("success" to true, "opened" to packageName)
    }

    private fun dialPhone(params: Map<String, Any?>): Map<String, Any?> {
        val number = params["phoneNumber"] as? String
            ?: return mapOf("success" to false, "error" to "Missing phoneNumber")

        val intent = Intent(Intent.ACTION_DIAL, "tel:$number".toUri())
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return mapOf("success" to true, "dialed" to number)
    }

    private fun sendSms(params: Map<String, Any?>): Map<String, Any?> {
        val number = params["phoneNumber"] as? String
            ?: return mapOf("success" to false, "error" to "Missing phoneNumber")
        val message = params["message"] as? String ?: ""

        val uri = "smsto:$number".toUri()
        val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
            putExtra("sms_body", message)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return mapOf("success" to true, "to" to number)
    }

    private fun sendEmail(params: Map<String, Any?>): Map<String, Any?> {
        val to = params["to"] as? String
            ?: return mapOf("success" to false, "error" to "Missing to")
        val subject = params["subject"] as? String ?: ""
        val body = params["body"] as? String ?: ""

        val intent = Intent(Intent.ACTION_SEND).apply {
            data = "mailto:".toUri()
            type = "text/plain"
            putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, body)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return mapOf("success" to true)
    }

    private fun openUrl(params: Map<String, Any?>): Map<String, Any?> {
        val url = params["url"] as? String
            ?: return mapOf("success" to false, "error" to "Missing url")

        val fixedUrl = if (url.startsWith("http://") || url.startsWith("https://")) url else "https://$url"
        val intent = Intent(Intent.ACTION_VIEW, fixedUrl.toUri())
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return mapOf("success" to true, "url" to fixedUrl)
    }

    private fun openCamera(): Map<String, Any?> {
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return mapOf("success" to true)
    }

    private fun openGallery(): Map<String, Any?> {
        val intent = Intent(Intent.ACTION_VIEW, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return mapOf("success" to true)
    }

    // ═══════════════════════════════════════════════════════════════════
    //  C. Settings Intents
    // ═══════════════════════════════════════════════════════════════════

    private fun openSettings(params: Map<String, Any?>): Map<String, Any?> {
        val type = params["type"] as? String ?: "default"

        val intent = when (type) {
            "wifi" -> Intent(Settings.ACTION_WIFI_SETTINGS)
            "bluetooth" -> Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            "location" -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            "battery" -> Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
            "sound" -> Intent(Settings.ACTION_SOUND_SETTINGS)
            "display" -> Intent(Settings.ACTION_DISPLAY_SETTINGS)
            "security" -> Intent(Settings.ACTION_SECURITY_SETTINGS)
            "developer" -> Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
            "app" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
            }
            "wireless" -> Intent(Settings.ACTION_WIRELESS_SETTINGS)
            "date" -> Intent(Settings.ACTION_DATE_SETTINGS)
            "locale" -> Intent(Settings.ACTION_LOCALE_SETTINGS)
            "storage" -> Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS)
            else -> Intent(Settings.ACTION_SETTINGS)
        }

        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return mapOf("success" to true, "opened" to type)
    }

    // ═══════════════════════════════════════════════════════════════════
    //  D. System Apps
    // ═══════════════════════════════════════════════════════════════════

    private fun openCalendar(): Map<String, Any?> {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("content://com.android.calendar/time/${System.currentTimeMillis()}")
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return mapOf("success" to true)
    }

    private fun openClock(): Map<String, Any?> {
        val intent = Intent(AlarmClock.ACTION_SHOW_ALARMS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return mapOf("success" to true)
    }

    private fun openCalculator(): Map<String, Any?> {
        // ไม่มี standard intent สำหรับ calculator ต้องลองหา package ทั่วไป
        val calculatorPackages = listOf(
            "com.google.android.calculator",
            "com.android.calculator2",
            "com.samsung.android.calculator"
        )
        for (pkg in calculatorPackages) {
            val intent = context.packageManager.getLaunchIntentForPackage(pkg)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return mapOf("success" to true, "package" to pkg)
            }
        }
        return mapOf("success" to false, "error" to "Calculator app not found")
    }

    private fun openMaps(params: Map<String, Any?>): Map<String, Any?> {
        val query = params["query"] as? String
        val lat = params["lat"] as? Double
        val lng = params["lng"] as? Double

        val uri = when {
            lat != null && lng != null -> "geo:$lat,$lng?q=$lat,$lng"
            query != null -> "geo:0,0?q=${Uri.encode(query)}"
            else -> "geo:0,0?q="
        }

        val intent = Intent(Intent.ACTION_VIEW, uri.toUri())
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        // ลอง Google Maps ก่อน ถ้าไม่มีให้ระบบเลือก app เอง
        intent.setPackage("com.google.android.apps.maps")
        val pm = context.packageManager
        if (intent.resolveActivity(pm) != null) {
            context.startActivity(intent)
        } else {
            intent.setPackage(null)
            context.startActivity(intent)
        }
        return mapOf("success" to true)
    }

    // ═══════════════════════════════════════════════════════════════════
    //  E. Share / Contact
    // ═══════════════════════════════════════════════════════════════════

    private fun shareText(params: Map<String, Any?>): Map<String, Any?> {
        val text = params["text"] as? String
            ?: return mapOf("success" to false, "error" to "Missing text")

        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        val chooser = Intent.createChooser(intent, "แชร์ผ่าน").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(chooser)
        return mapOf("success" to true)
    }

    private fun createContact(params: Map<String, Any?>): Map<String, Any?> {
        val intent = Intent(ContactsContract.Intents.Insert.ACTION).apply {
            type = ContactsContract.RawContacts.CONTENT_TYPE
            params["name"]?.let { putExtra(ContactsContract.Intents.Insert.NAME, it.toString()) }
            params["phone"]?.let { putExtra(ContactsContract.Intents.Insert.PHONE, it.toString()) }
            params["email"]?.let { putExtra(ContactsContract.Intents.Insert.EMAIL, it.toString()) }
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return mapOf("success" to true)
    }

    // ═══════════════════════════════════════════════════════════════════
    //  F. Queries (Read-only System State)
    // ═══════════════════════════════════════════════════════════════════

    private fun getBatteryLevel(): Map<String, Any?> {
        val bm = batteryManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && bm != null) {
            val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            mapOf("success" to true, "level" to level)
        } else {
            // Fallback: อ่านจาก Intent sticky
            val intent = context.registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            val pct = if (scale > 0) (level * 100 / scale) else -1
            mapOf("success" to true, "level" to pct)
        }
    }

    private fun getNetworkStatus(): Map<String, Any?> {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? android.net.ConnectivityManager

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && connectivityManager != null) {
            val network = connectivityManager.activeNetwork
            val capabilities = connectivityManager.getNetworkCapabilities(network)
            mapOf(
                "success" to true,
                "connected" to (capabilities != null),
                "wifi" to (capabilities?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true),
                "cellular" to (capabilities?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) == true),
                "vpn" to (capabilities?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN) == true),
            )
        } else {
            @Suppress("DEPRECATION")
            val info = connectivityManager?.activeNetworkInfo
            mapOf(
                "success" to true,
                "connected" to (info?.isConnected == true),
                "type" to (info?.typeName ?: "unknown")
            )
        }
    }
}
