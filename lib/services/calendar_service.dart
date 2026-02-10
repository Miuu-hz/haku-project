import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mediapipe_llm_service.dart';
import 'workers/calendar_worker.dart';

// Export unified CalendarEvent
export 'workers/calendar_worker.dart' show CalendarEvent, EventType, TimeOfDay;

/// 📅 Calendar Service - จัดการปฏิทินและการแจ้งเตือน
/// 
/// แยกจาก scheduler_service.dart เดิม (กลุ่ม 5)
/// หน้าที่:
/// - ดึงข้อมูลกิจกรรมจากข้อความ (LLM extraction)
/// - สร้าง event ใน Calendar ของเครื่อง
/// - ตั้งการแจ้งเตือนล่วงหน้า

class CalendarService {
  static const MethodChannel _channel = MethodChannel('com.example.haku/calendar');
  
  static final CalendarService _instance = CalendarService._internal();
  factory CalendarService() => _instance;
  CalendarService._internal();

  /// 🧠 วิเคราะห์ข้อความแล้วดึงข้อมูลกิจกรรม
  Future<CalendarEvent?> extractEvent(String text) async {
    try {
      final prompt = '''<|im_start|>system
ดึงข้อมูลกิจกรรมจากข้อความ ตอบเป็น JSON:
{
  "title": "ชื่อกิจกรรม",
  "date": "YYYY-MM-DD",
  "time": "HH:MM",
  "duration_minutes": 60,
  "location": "สถานที่"
}
ถ้าไม่พบวันที่ ใช้วันนี้<|im_end|>
<|im_start|>user
$text<|im_end|>
<|im_start|>assistant
''';  

      final response = await MediaPipeLLMService().generate(prompt);
      if (response.isEmpty) return _fallbackExtract(text);

      final jsonStr = _extractJson(response);
      if (jsonStr == null) return _fallbackExtract(text);

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return CalendarEvent.fromExtraction(
        title: data['title'] as String? ?? 'กิจกรรม',
        date: data['date'] != null ? DateTime.parse(data['date'] as String) : null,
        time: data['time'] as String?,
        durationMinutes: data['duration_minutes'] as int? ?? 60,
        location: data['location'] as String?,
        originalText: text,
      );
    } catch (e) {
      if (kDebugMode) print('❌ Extract event failed: $e');
      return _fallbackExtract(text);
    }
  }

  /// 📅 สร้าง event ใน Calendar
  Future<bool> createCalendarEvent(CalendarEvent event) async {
    try {
      final result = await _channel.invokeMethod('createEvent', {
        'title': event.title,
        'date': event.date.toIso8601String(),
        'time': event.time,
        'durationMinutes': event.durationMinutes,
        'location': event.location,
      });
      return result == true;
    } on PlatformException catch (_) {
      if (kDebugMode) print('❌ Create calendar event failed');
      return false;
    }
  }

  /// 🔔 ตั้งเตือนล่วงหน้า
  Future<bool> scheduleReminder(CalendarEvent event, {int minutesBefore = 15}) async {
    try {
      final result = await _channel.invokeMethod('scheduleReminder', {
        'title': 'ใกล้ถึงเวลา: \${event.title}',
        'body': event.location != null ? 'ที่: \${event.location}' : 'อย่าลืมนะคะ',
        'triggerMinutes': minutesBefore,
      });
      return result == true;
    } on PlatformException catch (_) {
      if (kDebugMode) print('❌ Schedule reminder failed');
      return false;
    }
  }

  /// 🔍 Simple fallback ถ้าไม่มี LLM
  CalendarEvent? _fallbackExtract(String text) {
    final timeRegex = RegExp(r'(\d{1,2}):(\d{2})');
    final timeMatch = timeRegex.firstMatch(text);
    String? time;
    if (timeMatch != null) {
      time = '\${timeMatch.group(1)}:\${timeMatch.group(2)}';
    }

    String title = 'กิจกรรม';
    if (text.contains('หมอ')) {
      title = 'นัดหมอ';
    } else if (text.contains('ประชุม')) {
      title = 'ประชุม';
    } else if (text.contains('กินข้าว')) {
      title = 'นัดกินข้าว';
    } else if (text.contains(' gym ') || text.contains('ยิม')) {
      title = 'ออกกำลังกาย';
    }

    return CalendarEvent.fromExtraction(
      title: title,
      time: time,
      originalText: text,
    );
  }

  String? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || start >= end) return null;
    return text.substring(start, end + 1);
  }
}


