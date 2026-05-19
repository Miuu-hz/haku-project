package com.example.haku

import android.util.Log
import com.google.ai.edge.litertlm.Tool
import com.google.ai.edge.litertlm.ToolParam
import com.google.ai.edge.litertlm.ToolSet

private const val TAG = "HakuTools"

/**
 * 🛠️ HakuToolSet — Function Calling tools สำหรับ LiteRT-LM (Gemma 4)
 *
 * โมเดลเรียก @Tool functions เหล่านี้แทนการ regex match
 * Delegate ไปยัง DeviceCommandHandler เพื่อรัน command จริง
 *
 * ใช้คู่กับ enableConversationConstrainedDecoding เพื่อความน่าเชื่อถือ
 */
class HakuToolSet(private val handler: DeviceCommandHandler) : ToolSet {

    // ── Flashlight ────────────────────────────────────────────────────────────

    @Tool(description = "Turns on the device flashlight or torch light")
    fun turnOnFlashlight(): Map<String, String> {
        Log.d(TAG, "tool: flashlight_on")
        val r = handler.execute("flashlight_on", emptyMap())
        return mapOf("result" to if (r["success"] == true) "success" else "error")
    }

    @Tool(description = "Turns off the device flashlight or torch light")
    fun turnOffFlashlight(): Map<String, String> {
        Log.d(TAG, "tool: flashlight_off")
        val r = handler.execute("flashlight_off", emptyMap())
        return mapOf("result" to if (r["success"] == true) "success" else "error")
    }

    // ── Alarm / Timer ─────────────────────────────────────────────────────────

    @Tool(description = "Sets an alarm at a specific time on the device clock app")
    fun setAlarm(
        @ToolParam(description = "Hour in 24-hour format, 0 to 23") hour: Int,
        @ToolParam(description = "Minute, 0 to 59") minute: Int,
        @ToolParam(description = "Alarm label or message, use empty string if none") label: String,
    ): Map<String, String> {
        Log.d(TAG, "tool: set_alarm $hour:$minute label=$label")
        val r = handler.execute("set_alarm", mapOf("hour" to hour, "minute" to minute, "message" to label))
        return mapOf("result" to if (r["success"] == true) "success" else "error",
                     "hour" to hour.toString(), "minute" to minute.toString())
    }

    @Tool(description = "Starts a countdown timer")
    fun setTimer(
        @ToolParam(description = "Duration in seconds, e.g. 300 for 5 minutes") seconds: Int,
        @ToolParam(description = "Timer label or message, use empty string if none") label: String,
    ): Map<String, String> {
        Log.d(TAG, "tool: set_timer ${seconds}s")
        val r = handler.execute("set_timer", mapOf("seconds" to seconds, "message" to label))
        return mapOf("result" to if (r["success"] == true) "success" else "error",
                     "seconds" to seconds.toString())
    }

    // ── Ringer / Volume ───────────────────────────────────────────────────────

    @Tool(description = "Sets the phone ringer to silent mode (no sound, no vibration)")
    fun setPhoneSilent(): Map<String, String> {
        Log.d(TAG, "tool: set_silent")
        handler.execute("set_silent", emptyMap())
        return mapOf("result" to "success")
    }

    @Tool(description = "Sets the phone to vibrate mode (vibrate but no ring sound)")
    fun setPhoneVibrate(): Map<String, String> {
        Log.d(TAG, "tool: set_vibrate")
        handler.execute("set_vibrate", emptyMap())
        return mapOf("result" to "success")
    }

    @Tool(description = "Turns on the phone ringer sound (normal sound mode)")
    fun setPhoneSoundOn(): Map<String, String> {
        Log.d(TAG, "tool: set_sound_on")
        handler.execute("set_sound_on", emptyMap())
        return mapOf("result" to "success")
    }

    @Tool(description = "Increases the phone ringer volume by one step")
    fun volumeUp(): Map<String, String> {
        Log.d(TAG, "tool: volume_up")
        handler.execute("volume_up", emptyMap())
        return mapOf("result" to "success")
    }

    @Tool(description = "Decreases the phone ringer volume by one step")
    fun volumeDown(): Map<String, String> {
        Log.d(TAG, "tool: volume_down")
        handler.execute("volume_down", emptyMap())
        return mapOf("result" to "success")
    }

    // ── App / Communication ───────────────────────────────────────────────────

    @Tool(description = "Opens an installed Android app by its package name")
    fun openApp(
        @ToolParam(description = "Android package name, e.g. com.google.android.youtube for YouTube, com.spotify.music for Spotify") packageName: String,
    ): Map<String, String> {
        Log.d(TAG, "tool: open_app $packageName")
        val r = handler.execute("open_app", mapOf("packageName" to packageName))
        return mapOf("result" to if (r["success"] == true) "success" else "error: app not found")
    }

    @Tool(description = "Opens the phone dialer with a number ready to call")
    fun dialPhone(
        @ToolParam(description = "Phone number to dial, digits only or with +country code") phoneNumber: String,
    ): Map<String, String> {
        Log.d(TAG, "tool: dial_phone $phoneNumber")
        handler.execute("dial_phone", mapOf("phoneNumber" to phoneNumber))
        return mapOf("result" to "success", "number" to phoneNumber)
    }

    @Tool(description = "Opens the SMS app to compose a message to a phone number")
    fun sendSms(
        @ToolParam(description = "Recipient phone number") phoneNumber: String,
        @ToolParam(description = "Message body text, use empty string if no message body") message: String,
    ): Map<String, String> {
        Log.d(TAG, "tool: send_sms to $phoneNumber")
        handler.execute("send_sms", mapOf("phoneNumber" to phoneNumber, "message" to message))
        return mapOf("result" to "success")
    }

    @Tool(description = "Opens a website URL in the browser")
    fun openUrl(
        @ToolParam(description = "Full URL including https://, e.g. https://www.google.com") url: String,
    ): Map<String, String> {
        Log.d(TAG, "tool: open_url $url")
        val r = handler.execute("open_url", mapOf("url" to url))
        return mapOf("result" to if (r["success"] == true) "success" else "error: invalid url")
    }

    @Tool(description = "Shows a location or place on the map app")
    fun showOnMap(
        @ToolParam(description = "Place name, address, or landmark to show on the map") location: String,
    ): Map<String, String> {
        Log.d(TAG, "tool: open_maps $location")
        handler.execute("open_maps", mapOf("query" to location))
        return mapOf("result" to "success", "location" to location)
    }

    // ── Queries ───────────────────────────────────────────────────────────────

    @Tool(description = "Gets the current device battery level as a percentage")
    fun getBatteryLevel(): Map<String, String> {
        Log.d(TAG, "tool: get_battery_level")
        val r = handler.execute("get_battery_level", emptyMap())
        return mapOf("result" to "success", "battery_percent" to (r["level"]?.toString() ?: "unknown"))
    }

    // ── Settings ─────────────────────────────────────────────────────────────

    @Tool(description = "Opens the WiFi settings screen")
    fun openWifiSettings(): Map<String, String> {
        Log.d(TAG, "tool: open_wifi_settings")
        handler.execute("open_wifi_settings", emptyMap())
        return mapOf("result" to "success")
    }

    @Tool(description = "Opens the Bluetooth settings screen")
    fun openBluetoothSettings(): Map<String, String> {
        Log.d(TAG, "tool: open_bluetooth_settings")
        handler.execute("open_bluetooth_settings", emptyMap())
        return mapOf("result" to "success")
    }
}
