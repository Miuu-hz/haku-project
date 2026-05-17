# Haku Device Command Architecture

> ออกแบบระบบให้ Haku AI สั่งงาน Smartphone ได้ — เปิด flash, เปิด app, โทร, ส่งข้อความ, ตั้งค่าระบบ, ฯลฯ

## Overview

Haku เป็น Flutter app ที่รัน LLM on-device ผ่าน LiteRT-LM (Gemma 3 1B) เราต้องการให้ LLM สามารถ **สั่งงานระบบ** ได้ผ่าน **Function Calling / Tool Use** คล้ายกับที่ Google AI Edge Gallery ทำไว้

แรงบันดาลใจจาก [`AgentTools.kt`](../gallery-main/gallery-main/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/agentchat/AgentTools.kt) ของ Gallery ที่มี `@Tool` annotation และ `runIntent()` สำหรับให้ LLM เรียก Android intent ได้

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: LLM Tool Definition (Dart)                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  DeviceCommandTool                                  │    │
│  │  - runIntent(action, parameters)                    │    │
│  │  - queryDeviceState(sensor)                         │    │
│  │  - openApp(packageName)                             │    │
│  └────────────────────┬────────────────────────────────┘    │
│                       │ invoke                               │
│  Layer 2: Flutter Service (Dart)                            │
│  ┌────────────────────▼────────────────────────────────┐    │
│  │  DeviceCommandService                               │    │
│  │  - MethodChannel("com.example.haku/device")         │    │
│  │  - Unified API สำหรับทุกคำสั่ง                       │    │
│  └────────────────────┬────────────────────────────────┘    │
│                       │ MethodChannel                        │
│  Layer 3: Android Native (Kotlin)                           │
│  ┌────────────────────▼────────────────────────────────┐    │
│  │  DeviceCommandHandler                               │    │
│  │  - IntentHandler (สั่งงานผ่าน Android Intent)        │    │
│  │  - SystemQueryHandler (อ่านสถานะเซ็นเซอร์)          │    │
│  │  - PermissionGuard (ตรวจสอบสิทธิ์ก่อนรัน)           │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## Layer 1: LLM Tool Definition

LiteRT-LM รองรับ `@Tool` annotation (ดูจาก Gallery) แต่บน Flutter เราต้องกำหนด tool schema ผ่าน **JSON Schema** แล้วส่งให้ LLM ใน system prompt

### Tool Schema (JSON)

```json
{
  "name": "run_device_command",
  "description": "Run a smartphone command such as open flash, open app, call phone, send SMS, open settings, etc.",
  "parameters": {
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "enum": [
          "flashlight_on", "flashlight_off", "flashlight_toggle",
          "open_app", "dial_phone", "send_sms", "send_email",
          "open_url", "open_camera", "open_gallery",
          "open_wifi_settings", "open_bluetooth_settings",
          "open_location_settings", "open_battery_settings",
          "open_calendar", "open_clock", "open_calculator",
          "share_text", "create_contact", "open_maps",
          "toggle_airplane_mode", "toggle_dnd",
          "get_battery_level", "get_network_status"
        ],
        "description": "The command to execute"
      },
      "params": {
        "type": "object",
        "description": "Command-specific parameters"
      }
    },
    "required": ["command"]
  }
}
```

### System Prompt Snippet

```
You are Haku, a private on-device AI assistant. You can control the user's smartphone.

Available commands:
- flashlight_on / flashlight_off / flashlight_toggle
- open_app(packageName) — open an app by package name
- dial_phone(phoneNumber) — open dialer with number
- send_sms(phoneNumber, message) — open SMS composer
- send_email(to, subject, body) — open email client
- open_url(url) — open browser
- open_camera — open camera app
- open_gallery — open photo gallery
- open_wifi_settings / open_bluetooth_settings / open_location_settings
- open_calendar / open_clock / open_calculator
- share_text(text) — open share sheet
- create_contact(name, phone, email)
- open_maps(query) — open map with search query
- get_battery_level — returns battery percentage
- get_network_status — returns wifi/mobile status

When the user asks to do something, respond with the appropriate command in JSON format.
```

---

## Layer 2: Flutter Service

`lib/services/device_command_service.dart`

```dart
class DeviceCommandService {
  static const MethodChannel _channel = 
    MethodChannel('com.example.haku/device');

  /// สั่งงานทั้งหมดผ่าน channel เดียว
  static Future<Map<String, dynamic>> execute(String command, Map<String, dynamic> params) async {
    try {
      final result = await _channel.invokeMethod('execute', {
        'command': command,
        'params': params,
      });
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      return {'success': false, 'error': e.message};
    }
  }

  /// Convenience methods
  static Future<bool> flashlight(bool on) async {
    final r = await execute(on ? 'flashlight_on' : 'flashlight_off', {});
    return r['success'] ?? false;
  }

  static Future<bool> openApp(String packageName) async {
    final r = await execute('open_app', {'packageName': packageName});
    return r['success'] ?? false;
  }

  static Future<bool> dialPhone(String number) async {
    final r = await execute('dial_phone', {'phoneNumber': number});
    return r['success'] ?? false;
  }

  static Future<bool> sendSms(String number, String message) async {
    final r = await execute('send_sms', {'phoneNumber': number, 'message': message});
    return r['success'] ?? false;
  }

  static Future<bool> openUrl(String url) async {
    final r = await execute('open_url', {'url': url});
    return r['success'] ?? false;
  }

  static Future<bool> openSettings(String type) async {
    final r = await execute('open_settings', {'type': type});
    return r['success'] ?? false;
  }

  static Future<Map<String, dynamic>> getBatteryLevel() async {
    return await execute('get_battery_level', {});
  }

  static Future<Map<String, dynamic>> getNetworkStatus() async {
    return await execute('get_network_status', {});
  }
}
```

---

## Layer 3: Android Native Handler

`android/app/src/main/kotlin/com/example/haku/DeviceCommandHandler.kt`

รองรับ 2 กลุ่มหลัก:

### กลุ่ม A: Intent-based Commands (เปิด app, โทร, ส่งข้อความ, เปิด settings)
ใช้ `Intent()` + `startActivity()` เหมือน Gallery

### กลุ่ม B: System API Commands (Flashlight, Battery, Network, Sensors)
ใช้ `CameraManager`, `BatteryManager`, `WifiManager`, `ConnectivityManager`

### กลุ่ม C: Settings Intents (ไม่ต้อง permission พิเศษ)
ใช้ `Settings.ACTION_*` intents

---

## Command Mapping

| Command | Android Implementation | Permission |
|---------|----------------------|------------|
| `flashlight_on` | `CameraManager.setTorchMode(cameraId, true)` | `CAMERA` |
| `flashlight_off` | `CameraManager.setTorchMode(cameraId, false)` | `CAMERA` |
| `open_app` | `packageManager.getLaunchIntentForPackage()` | - |
| `dial_phone` | `Intent(ACTION_DIAL, uri)` | - |
| `send_sms` | `Intent(ACTION_SENDTO, smsto:uri)` | - |
| `send_email` | `Intent(ACTION_SEND)` | - |
| `open_url` | `Intent(ACTION_VIEW, http:uri)` | - |
| `open_camera` | `Intent(MediaStore.ACTION_IMAGE_CAPTURE)` | - |
| `open_gallery` | `Intent(ACTION_VIEW, content://media/external/images/)` | - |
| `open_wifi_settings` | `Intent(Settings.ACTION_WIFI_SETTINGS)` | - |
| `open_bluetooth_settings` | `Intent(Settings.ACTION_BLUETOOTH_SETTINGS)` | - |
| `open_location_settings` | `Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)` | - |
| `open_battery_settings` | `Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)` | - |
| `open_calendar` | `Intent(ACTION_VIEW, content://com.android.calendar/time)` | - |
| `open_clock` | `Intent(AlarmClock.ACTION_SHOW_ALARMS)` | - |
| `open_calculator` | `Intent(ACTION_MAIN, CALCULATOR package)` | - |
| `share_text` | `Intent(ACTION_SEND, text/plain)` | - |
| `create_contact` | `Intent(ContactsContract.Intents.Insert.ACTION)` | - |
| `open_maps` | `Intent(ACTION_VIEW, geo: or google.navigation:)` | - |
| `get_battery_level` | `BatteryManager.getIntProperty(BATTERY_PROPERTY_CAPACITY)` | - |
| `get_network_status` | `ConnectivityManager.activeNetworkInfo` | - |

---

## Integration into MainActivity

เพิ่มใน `MainActivity.kt`:

```kotlin
private const val DEVICE_CHANNEL = "com.example.haku/device"

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
            result.error("DEVICE_ERROR", e.message, e.stackTraceToString())
        }
    }
}
```

แล้วเรียกใน `configureFlutterEngine()`:
```kotlin
setupDeviceCommandChannel(flutterEngine)
```

---

## Security & Privacy Considerations

1. **No Silent Actions**: ทุกคำสั่งที่มีผลต่อภายนอก (โทร, SMS, อีเมล) ต้องเปิด system UI ให้ user confirm ก่อน — ไม่ทำ background action
2. **Permission Guard**: ตรวจสอบ permission ก่อนรัน flashlight, camera, location
3. **Intent-based only**: ไม่ใช้ reflection หรือ hidden APIs ที่อาจพังบน Android รุ่นใหม่
4. **User Consent Log**: บันทึกลง SQLite (encrypted) ว่า AI สั่งอะไรไปบ้าง — user ตรวจสอบได้

---

## Future Extensions

- **iOS**: ใช้ `UIApplication.shared.open(URL)` สำหรับเปิด settings / apps และ `AVCaptureDevice` สำหรับ flashlight
- **Wear OS / Watch**: รองรับ command เฉพาะนาฬิกา (vibrate, show notification)
- **Quick Settings Tile**: เพิ่ม tile ให้ user เปิด/ปิด Haku Agent ได้จาก quick settings
- **Voice Trigger**: "Hey Haku, เปิดไฟฉาย" → ผ่าน on-device speech recognition แล้วส่งคำสั่งโดยตรง
