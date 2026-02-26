import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'llm_provider_manager.dart';
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
  ///
  /// 🔋 Battery Optimized: ใช้ lazy loading - LLM จะโหลดเมื่อใช้งานจริง
  Future<EventInfo?> extractEvent(String text) async {
    try {
      // ใช้ LLM ดึงข้อมูล (Gemma-3 format)
      final prompt = PromptBuilder.buildSchedulerPrompt(text);

      String response;
      if (LLMProviderManager().provider.isInitialized) {
        response = await LLMProviderManager().provider.generate(prompt);
      } else {
        // Simple regex fallback
        return _fallbackExtract(text);
      }

      // Parse JSON
      final jsonStr = _extractJson(response);
      if (jsonStr == null) return _fallbackExtract(text);

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return EventInfo(
        title: data['title'] as String? ?? 'กิจกรรม',
        date: data['date'] != null
            ? DateTime.parse(data['date'] as String)
            : null,
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
      // Android ต้องการ startTime/endTime เป็น milliseconds since epoch
      final now = DateTime.now();
      DateTime startDateTime = event.date ?? now.add(const Duration(hours: 1));

      // ถ้ามี time string เช่น "15:00" หรือ "15" → parse แล้วใส่ใน startDateTime
      if (event.time != null) {
        final timeParts = event.time!.split(':');
        final hour = int.tryParse(timeParts[0]) ?? 9;
        final minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
        startDateTime = DateTime(
          startDateTime.year,
          startDateTime.month,
          startDateTime.day,
          hour,
          minute,
        );
      }

      final endDateTime = startDateTime.add(Duration(minutes: event.durationMinutes));

      final result = await _channel.invokeMethod('createEvent', {
        'title': event.title,
        'description': '',
        'startTime': startDateTime.millisecondsSinceEpoch,
        'endTime': endDateTime.millisecondsSinceEpoch,
        'location': event.location,
        'addReminder': true,
        'reminderMinutes': 15,
      });

      return result != null; // Android returns eventId (Long) on success
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

  // ============================================================
  // 📅 CALENDAR READ & CONFLICT DETECTION (Feature 2.11)
  // ============================================================

  /// 📋 ดึง events จาก Android Calendar ในช่วงเวลาที่กำหนด
  Future<List<Map<String, dynamic>>> getCalendarEvents(
    DateTime start,
    DateTime end,
  ) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getEvents', {
        'startTime': start.millisecondsSinceEpoch,
        'endTime': end.millisecondsSinceEpoch,
      });
      if (result == null) return [];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on PlatformException catch (e) {
      if (kDebugMode) print('⚠️ getCalendarEvents failed: ${e.message}');
      return [];
    }
  }

  /// 🔍 ตรวจสอบว่า EventInfo ชนกับ event ที่มีอยู่หรือไม่
  Future<ConflictResult> checkConflicts(EventInfo event) async {
    // สร้าง DateTime ของ event ใหม่ (เหมือน createCalendarEvent)
    final now = DateTime.now();
    DateTime startDT = event.date ?? now.add(const Duration(hours: 1));
    if (event.time != null) {
      final parts = event.time!.split(':');
      final hour = int.tryParse(parts[0]) ?? 9;
      final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      startDT = DateTime(startDT.year, startDT.month, startDT.day, hour, minute);
    }
    final endDT = startDT.add(Duration(minutes: event.durationMinutes));

    // ดึง events ทั้งวัน
    final dayStart = DateTime(startDT.year, startDT.month, startDT.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final existing = await getCalendarEvents(dayStart, dayEnd);

    final conflicts = <Map<String, dynamic>>[];
    for (final e in existing) {
      final eStart = e['startTime'];
      final eEnd = e['endTime'];
      if (eStart == null || eEnd == null) continue;
      final existingStart =
          DateTime.fromMillisecondsSinceEpoch(eStart as int);
      final existingEnd = DateTime.fromMillisecondsSinceEpoch(eEnd as int);
      // overlap ถ้า newStart < existingEnd && newEnd > existingStart
      if (startDT.isBefore(existingEnd) && endDT.isAfter(existingStart)) {
        conflicts.add(e);
      }
    }

    return ConflictResult(
      hasConflict: conflicts.isNotEmpty,
      conflicts: conflicts,
      proposedStart: startDT,
      proposedEnd: endDT,
    );
  }

  /// 🕐 หา time slot ว่างถัดไปในวันเดียวกัน
  ///
  /// scan ทุก 30 นาทีจาก [fromTime] ไปข้างหน้า
  /// คืน DateTime ของ slot แรกที่ว่าง หรือ null ถ้าไม่มีก่อน 21:00
  Future<DateTime?> findNextFreeSlot(
    DateTime fromTime,
    int durationMinutes,
  ) async {
    final dayStart = DateTime(fromTime.year, fromTime.month, fromTime.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final events = await getCalendarEvents(dayStart, dayEnd);

    // เริ่มจาก fromTime + duration (ข้ามช่วงที่ขอไป) แล้ว round ขึ้นไป :00 หรือ :30
    DateTime candidate = fromTime.add(Duration(minutes: durationMinutes));
    final extra = candidate.minute % 30;
    if (extra != 0) {
      candidate = candidate.add(Duration(minutes: 30 - extra));
    }
    candidate = DateTime(
        candidate.year, candidate.month, candidate.day, candidate.hour, candidate.minute);

    final cutoff = DateTime(fromTime.year, fromTime.month, fromTime.day, 21, 0);

    while (candidate.isBefore(cutoff)) {
      final candidateEnd = candidate.add(Duration(minutes: durationMinutes));
      final hasConflict = events.any((e) {
        final eStart = e['startTime'];
        final eEnd = e['endTime'];
        if (eStart == null || eEnd == null) return false;
        final s = DateTime.fromMillisecondsSinceEpoch(eStart as int);
        final en = DateTime.fromMillisecondsSinceEpoch(eEnd as int);
        return candidate.isBefore(en) && candidateEnd.isAfter(s);
      });
      if (!hasConflict) return candidate;
      candidate = candidate.add(const Duration(minutes: 30));
    }
    return null;
  }

  /// 📅 สร้าง event พร้อมตรวจ conflict ก่อน
  ///
  /// คืน [ScheduleResult] ที่มี [success] และ [conflictWarning] ถ้าชนนัด
  Future<ScheduleResult> createCalendarEventWithCheck(EventInfo event) async {
    final conflict = await checkConflicts(event);
    final success = await createCalendarEvent(event);
    return ScheduleResult(
      success: success,
      conflictWarning: conflict.hasConflict ? conflict : null,
    );
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

/// 🔍 ผลการตรวจ conflict
class ConflictResult {
  final bool hasConflict;
  final List<Map<String, dynamic>> conflicts;
  final DateTime proposedStart;
  final DateTime proposedEnd;

  const ConflictResult({
    required this.hasConflict,
    required this.conflicts,
    required this.proposedStart,
    required this.proposedEnd,
  });

  /// ชื่อ event ที่ชนกัน (สำหรับแสดงใน UI)
  String get conflictSummary {
    if (!hasConflict) return '';
    final names = conflicts.map((e) => e['title'] as String? ?? 'กิจกรรม').join(', ');
    return 'ชนกับ: $names';
  }
}

/// 📅 ผลการสร้าง calendar event
class ScheduleResult {
  final bool success;
  final ConflictResult? conflictWarning;

  const ScheduleResult({
    required this.success,
    this.conflictWarning,
  });

  bool get hadConflict => conflictWarning?.hasConflict == true;
}
