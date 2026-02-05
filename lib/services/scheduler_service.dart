import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mediapipe_llm_service.dart';
import 'prompt_builder.dart';

// 📅 Scheduler Service - Auto-scheduling จากข้อความธรรมชาติ
// 
// รองรับ:
//- ดึง intent/เวลา/วันที่ จากข้อความ
// - สร้าง event ใน Calendar ของเครื่อง
// - แจ้งเตือนล่วงหน้า

class SchedulerService {
  static const MethodChannel _channel = MethodChannel('com.example.haku/scheduler');
  
  static final SchedulerService _instance = SchedulerService._internal();
  factory SchedulerService() => _instance;
  SchedulerService._internal();

  /// 🧠 วิเคราะห์ข้อความแล้วดึงข้อมูลกิจกรรม
  Future<EventInfo?> extractEvent(String text) async {
    try {
      // ใช้ LLM ดึงข้อมูล (Gemma-3 format)
      final prompt = PromptBuilder.buildSchedulerPrompt(text);

      String response;
      if (MediaPipeLLMService().isInitialized) {
        response = await MediaPipeLLMService().generate(prompt);
      } else {
        // Simple regex fallback
        return _fallbackExtract(text);
      }

      // Parse JSON
      final jsonStr = _extractJson(response);
      if (jsonStr == null) return null;

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return EventInfo(
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
  Future<bool> createCalendarEvent(EventInfo event) async {
    try {
      final result = await _channel.invokeMethod('createEvent', {
        'title': event.title,
        'date': event.date?.toIso8601String(),
        'time': event.time,
        'durationMinutes': event.durationMinutes,
        'location': event.location,
      });
      
      return result == true;
    } on PlatformException catch (e) {
      if (kDebugMode) print('❌ Create calendar event failed: ${e.message}');
      return false;
    }
  }

  /// 🔔 ตั้งเตือนล่วงหน้า (Proactive Alert)
 Future<bool> scheduleReminder(
  EventInfo event, {
  int minutesBefore = 15,
}) async {
    try {
      final result = await _channel.invokeMethod('scheduleReminder', {
        'title': 'ใกล้ถึงเวลา: ${event.title}',
        'body': event.location != null ? 'ที่: ${event.location}' : 'อย่าลืมนะคะ',
        'triggerMinutes': minutesBefore,
      });
      
      return result == true;
    } on PlatformException catch (e) {
      if (kDebugMode) print('❌ Schedule reminder failed: ${e.message}');
      return false;
    }
  }

  /// 🔍 Simple fallback ถ้าไม่มี LLM
  EventInfo? _fallbackExtract(String text) {
    // หาเวลาแบบง่าย ๆ
    final timeRegex = RegExp(r'(\d{1,2}):(\d{2})');
    final timeMatch = timeRegex.firstMatch(text);
    String? time;
    if (timeMatch != null) {
      time = '${timeMatch.group(1)}:${timeMatch.group(2)}';
    }

    // หาคำสำคัญ
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

    return EventInfo(
      title: title,
      time: time,
      durationMinutes: 60,
      originalText: text,
    );
  }

  /// 📝 ดึง JSON จากข้อความ
  String? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || start >= end) return null;
    return text.substring(start, end + 1);
  }
}

/// 📋 ข้อมูลกิจกรรม
class EventInfo {
  final String title;
  final DateTime? date;
  final String? time;
  final int durationMinutes;
  final String? location;
  final String originalText;

  EventInfo({
    required this.title,
    this.date,
    this.time,
    this.durationMinutes = 60,
    this.location,
    required this.originalText,
  });

  String get displayTime {
    if (date != null && time != null) {
      return '${date!.day}/${date!.month} เวลา $time';
    } else if (time != null) {
      return 'เวลา $time';
    }
    return 'ยังไม่ระบุเวลา';
  }
}
