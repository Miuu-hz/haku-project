import 'dart:convert';

import 'package:flutter/material.dart';

import 'device_command_intent_detector.dart';
import 'device_command_service.dart';
import 'llm_provider_manager.dart';

/// 🧠 LLM Intent Detector — ให้ LLM เข้าใจ intent เองแทน rule-based regex
///
/// Flow:
/// 1. ส่ง prompt สั้นๆ ให้ LLM classify intent → JSON
/// 2. Parse JSON → execute command (ผ่าน approval gate ถ้า sensitive)
/// 3. ถ้า LLM fail / ไม่พร้อม / timeout → fallback ไป rule-based
///
/// ข้อดี: เข้าใจภาษาธรรมชาติ เช่น "ตาแห้งจัง มืดเกินไป" → flashlight_on
/// ข้อเสีย: ช้ากว่า rule-based ~500ms-2s (ใช้ token ~50-100)
class LLMIntentDetector {
  static const String _systemPrompt = r'''
You are an intent classifier for a smartphone AI assistant.
Classify the user's message into ONE intent.
Reply with JSON only. No explanation. No markdown.

Available intents:
- "flashlight_on" — user wants light/torch (e.g., "เปิดไฟ", "มืดจัง", "flashlight on", "open flash")
- "flashlight_off" — user wants to turn off light (e.g., "ปิดไฟ", "flashlight off", "close flash")
- "camera_open" — user wants camera (e.g., "เปิดกล้อง", "ถ่ายรูป", "open camera")
- "gallery_open" — user wants photos (e.g., "เปิดแกลเลอรี่", "ดูรูป", "open gallery")
- "dial_phone" — user wants to call (e.g., "โทรหาแม่", "call mom")
- "send_sms" — user wants to text (e.g., "ส่งข้อความ", "sms")
- "open_settings" — user wants settings (e.g., "เปิด wifi", "bluetooth settings")
- "open_calendar" — user wants calendar (e.g., "เปิดปฏิทิน", "open calendar")
- "open_maps" — user wants maps/navigation (e.g., "เปิดแผนที่", "นำทาง", "open map")
- "get_battery" — user asks about battery (e.g., "แบตเท่าไร", "battery level")
- "chat" — casual talk, no action needed

JSON format: {"intent":"INTENT_NAME","params":{"key":"value"}}

Examples:
User: "เปิดไฟฉาย" → {"intent":"flashlight_on","params":{}}
User: "ปิดแฟลช" → {"intent":"flashlight_off","params":{}}
User: "เปิดกล้องหน่อย" → {"intent":"camera_open","params":{}}
User: "โทรหา 0812345678" → {"intent":"dial_phone","params":{"phoneNumber":"0812345678"}}
User: "ตาแห้งจัง มืดเกินไป" → {"intent":"flashlight_on","params":{}}
User: "สวัสดี" → {"intent":"chat","params":{}}
User: "วันนี้มีอะไร" → {"intent":"chat","params":{}}
''';

  /// 🧠 Classify intent ด้วย LLM แล้ว execute คำสั่ง
  ///
  /// [context] ต้องส่งมาเสมอสำหรับคำสั่ง sensitive (dial_phone, send_sms, ฯลฯ)
  /// ถ้าไม่มี context → คำสั่ง sensitive จะถูก block ที่ approval gate
  static Future<DeviceCommandResult?> detect(
    String userMessage, {
    BuildContext? context,
  }) async {
    final llm = LLMProviderManager().provider;

    // ─── Fast path: ถ้า LLM ไม่พร้อม → fallback rule-based ทันที ───
    if (!llm.isInitialized) {
      debugPrint('🧠 LLM not ready → fallback to rule-based');
      return DeviceCommandIntentDetector.detectAndExecute(
        userMessage,
        context: context,
      );
    }

    try {
      // Build prompt
      final prompt = '$_systemPrompt\n\nUser: "$userMessage"';

      // สั้นๆ ไม่ต้องรอนาน (intent classification ใช้ token น้อย)
      final raw = await llm
          .generate(prompt)
          .timeout(const Duration(seconds: 5));

      // Extract JSON block
      final jsonMatch = RegExp(r'\{[\s\S]*?\}').firstMatch(raw);
      if (jsonMatch == null) {
        debugPrint('🧠 LLM response has no JSON → fallback');
        if (context != null && !context.mounted) return null;
        return DeviceCommandIntentDetector.detectAndExecute(
          userMessage,
          context: context,
        );
      }

      final decoded = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      final intent = decoded['intent'] as String?;
      final params = Map<String, dynamic>.from(decoded['params'] as Map? ?? {});

      if (intent == null || intent == 'chat') {
        debugPrint('🧠 Intent = chat → no action');
        return null;
      }

      debugPrint('🧠 LLM intent: $intent | params: $params');

      // Execute ผ่าน DeviceCommandService (มี approval gate อยู่แล้ว)
      if (context != null && !context.mounted) return null;
      final result = await DeviceCommandService.execute(
        intent,
        params: params,
        context: context,
        source: 'llm_intent',
      );

      return DeviceCommandResult(
        action: intent,
        success: result['success'] == true,
        reply: _buildReply(intent, params, result),
        rawResult: result,
      );
    } catch (e) {
      debugPrint('🧠 LLM intent detection failed: $e → fallback to rule-based');
      if (context != null && !context.mounted) return null;
      return DeviceCommandIntentDetector.detectAndExecute(
        userMessage,
        context: context,
      );
    }
  }

  /// 💬 สร้างข้อความตอบกลับตาม intent + result
  static String _buildReply(
    String intent,
    Map<String, dynamic> params,
    Map<String, dynamic> result,
  ) {
    if (result['success'] != true) {
      final error = result['error'] as String?;
      if (error == 'User declined') return '❌ ยกเลิกคำสั่งแล้วค่ะ';
      return '❌ ทำไม่สำเร็จค่ะ${error != null ? ': $error' : ''}';
    }

    switch (intent) {
      case 'flashlight_on':
        return '💡 เปิดไฟฉายแล้วค่ะ';
      case 'flashlight_off':
        return '💡 ปิดไฟฉายแล้วค่ะ';
      case 'camera_open':
        return '📷 เปิดกล้องแล้วค่ะ';
      case 'gallery_open':
        return '🖼️ เปิดแกลเลอรี่แล้วค่ะ';
      case 'dial_phone':
        final number = params['phoneNumber'] ?? '';
        return '☎️ เปิดหน้าโทร $number แล้วค่ะ';
      case 'send_sms':
        final number = params['phoneNumber'] ?? '';
        return '💬 เปิดหน้าส่งข้อความไป $number แล้วค่ะ';
      case 'open_settings':
        return '⚙️ เปิดการตั้งค่าแล้วค่ะ';
      case 'open_calendar':
        return '📅 เปิดปฏิทินแล้วค่ะ';
      case 'open_maps':
        final query = params['query'];
        return query != null
            ? '🗺️ เปิดแผนที่ไปที่ $query แล้วค่ะ'
            : '🗺️ เปิดแผนที่แล้วค่ะ';
      case 'get_battery':
        final level = result['level'] ?? -1;
        return '🔋 แบตเตอรี่เหลือ $level% ค่ะ';
      default:
        return '✅ ทำ $intent แล้วค่ะ';
    }
  }
}
