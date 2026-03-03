import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../unified_vector_service.dart';

/// 📅 Calendar Worker - ตรวจจับและจัดการนัดหมาย
///
/// ตรวจจับ:
/// - นัดหมาย: "นัดหมอพรุ่งนี้ 10 โมง"
/// - ประชุม: "ประชุมวันศุกร์"
/// - กิจกรรม: "ไปกินข้าววันเสาร์"
///
/// Output format: [Cal:หมอ,พรุ่งนี้,10:00]

class CalendarWorker {
  static final CalendarWorker _instance = CalendarWorker._internal();
  factory CalendarWorker() => _instance;
  CalendarWorker._internal();

  static const String _eventsKey = 'calendar_events';

  final UnifiedVectorService _vectorService = UnifiedVectorService();
  final List<CalendarEvent> _events = [];
  bool _isInitialized = false;

  // ============================================================
  // 🔍 DETECTION PATTERNS
  // ============================================================

  /// นัดหมาย (title-first: นัด/ไป + title + day + time)
  static final List<RegExp> _appointmentPatterns = [
    RegExp(r'นัด(.+?)(วันนี้|พรุ่งนี้|พรุ้งนี้|มะรืน|วัน.+?)(?:\s*(\d+)\s*(?:โมง(?:เช้า|เย็น|กลางคืน)?|:))?', caseSensitive: false),
    RegExp(r'ไป(.+?)(วันนี้|พรุ่งนี้|พรุ้งนี้|มะรืน|วัน.+?)(?:\s*(\d+)\s*(?:โมง(?:เช้า|เย็น|กลางคืน)?|:))?', caseSensitive: false),
  ];

  /// นัดหมาย (day-first: day + มีนัด + title + time) เช่น "พรุ้งนี้มีนัดที่ศาลากลาง9โมงเช้า"
  static final List<RegExp> _dayFirstPatterns = [
    RegExp(
      r'(วันนี้|พรุ่งนี้|พรุ้งนี้|มะรืน|วัน[ก-ฮ]+)\s*(?:มี)?นัด(?:ที่|ใน|กับ)?\s*(.+?)(?:\s*(\d+)\s*(?:โมง(?:เช้า|เย็น|กลางคืน)?|นาฬิกา))?(?:นะ|ครับ|ค่ะ|นะครับ|นะคะ)?$',
      caseSensitive: false,
    ),
  ];

  /// นัดหมาย (มีนัด-first: มีนัด + title + day + time) เช่น "มีนัดที่โรงพยาบาล พรุ่งนี้ 10 โมง"
  static final List<RegExp> _naedFirstPatterns = [
    RegExp(
      r'(?:มี)?นัด(?:ที่|ใน|กับ)?\s*(.+?)\s+(วันนี้|พรุ่งนี้|พรุ้งนี้|มะรืน|วัน[ก-ฮ]+)(?:\s*(\d+)\s*(?:โมง(?:เช้า|เย็น|กลางคืน)?|นาฬิกา))?(?:นะ|ครับ|ค่ะ|นะครับ|นะคะ)?$',
      caseSensitive: false,
    ),
  ];

  /// ประชุม (Thai)
  static final List<RegExp> _meetingPatterns = [
    RegExp(r'ประชุม(.+?)(วันนี้|พรุ่งนี้|พรุ้งนี้|วัน.+?)(?:\s*(\d+)\s*(?:โมง(?:เช้า|เย็น|กลางคืน)?|:))?', caseSensitive: false),
  ];

  /// English appointment/meeting patterns
  static final List<RegExp> _enAppointmentPatterns = [
    // "meeting with Sales team tomorrow at 1pm"
    RegExp(
      r'(?:meeting|call|appointment|event)\s+(?:with\s+)?([\w\s]+?)\s+(tomorrow|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?:\s+at\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)))?',
      caseSensitive: false,
    ),
    // "tomorrow have a meeting with John at 3pm"
    RegExp(
      r'(tomorrow|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+(?:have\s+(?:a\s+)?)?(?:meeting|call|appointment)\s+(?:with\s+)?([\w\s]+?)(?:\s+at\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)))?',
      caseSensitive: false,
    ),
  ];

  /// วันที่ (Thai + English)
  static final Map<String, int> _dayOffsets = {
    'วันนี้': 0,
    'today': 0,
    'พรุ่งนี้': 1,
    'พรุ้งนี้': 1,  // typo variant
    'tomorrow': 1,
    'มะรืน': 2,
    'วันจันทร์': -1, // special handling
    'วันอังคาร': -1,
    'วันพุธ': -1,
    'วันพฤหัส': -1,
    'วันศุกร์': -1,
    'วันเสาร์': -1,
    'วันอาทิตย์': -1,
    'monday': -1,
    'tuesday': -1,
    'wednesday': -1,
    'thursday': -1,
    'friday': -1,
    'saturday': -1,
    'sunday': -1,
  };

  static final Map<String, int> _weekdays = {
    'วันจันทร์': DateTime.monday,
    'วันอังคาร': DateTime.tuesday,
    'วันพุธ': DateTime.wednesday,
    'วันพฤหัส': DateTime.thursday,
    'วันศุกร์': DateTime.friday,
    'วันเสาร์': DateTime.saturday,
    'วันอาทิตย์': DateTime.sunday,
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
  };

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadEvents();
    _isInitialized = true;
    debugPrint('✅ CalendarWorker initialized: ${_events.length} events');
  }

  Future<void> _loadEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_eventsKey);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _events.clear();
        _events.addAll(
          list.map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>)),
        );

        // Clean up past events
        _cleanupPastEvents();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading calendar events: $e');
    }
  }

  Future<void> _saveEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _eventsKey,
        jsonEncode(_events.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving calendar events: $e');
    }
  }

  void _cleanupPastEvents() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _events.removeWhere((e) => e.date.isBefore(today));
  }

  // ============================================================
  // 🔍 DETECTION
  // ============================================================

  /// ตรวจจับนัดหมายจากข้อความ (Thai + English, รองรับหลาย events/message)
  Future<List<CalendarEvent>> detectEvents(String message) async {
    final events = <CalendarEvent>[];

    // ── Thai patterns ──────────────────────────────────────────────

    // ตรวจจับ appointments (allMatches เพื่อจับหลาย events)
    for (final pattern in _appointmentPatterns) {
      for (final match in pattern.allMatches(message)) {
        final event = _parseEvent(
          type: EventType.appointment,
          title: match.group(1)?.trim() ?? '',
          dayStr: match.group(2)?.trim() ?? '',
          timeStr: match.group(3),
        );
        if (event != null && !events.any((e) => e.title == event.title)) {
          events.add(event);
          await addEvent(event);
        }
      }
    }

    // ตรวจจับ day-first: "พรุ้งนี้มีนัดที่ศาลากลาง 9โมงเช้า" → group(1)=day, group(2)=title, group(3)=time
    for (final pattern in _dayFirstPatterns) {
      final match = pattern.firstMatch(message); // anchored ($) → firstMatch ok
      if (match != null) {
        final event = _parseEvent(
          type: EventType.appointment,
          title: match.group(2)?.trim() ?? '',
          dayStr: match.group(1)?.trim() ?? '',
          timeStr: match.group(3),
        );
        if (event != null && !events.any((e) => e.title == event.title)) {
          events.add(event);
          await addEvent(event);
        }
      }
    }

    // ตรวจจับ มีนัด-first: "มีนัดที่โรงพยาบาล พรุ่งนี้ 10 โมง" → group(1)=title, group(2)=day, group(3)=time
    for (final pattern in _naedFirstPatterns) {
      final match = pattern.firstMatch(message); // anchored ($) → firstMatch ok
      if (match != null) {
        final event = _parseEvent(
          type: EventType.appointment,
          title: match.group(1)?.trim() ?? '',
          dayStr: match.group(2)?.trim() ?? '',
          timeStr: match.group(3),
        );
        if (event != null && !events.any((e) => e.title == event.title)) {
          events.add(event);
          await addEvent(event);
        }
      }
    }

    // ตรวจจับ meetings Thai (allMatches)
    for (final pattern in _meetingPatterns) {
      for (final match in pattern.allMatches(message)) {
        final event = _parseEvent(
          type: EventType.meeting,
          title: match.group(1)?.trim() ?? 'ประชุม',
          dayStr: match.group(2)?.trim() ?? '',
          timeStr: match.group(3),
        );
        if (event != null && !events.any((e) => e.title == event.title)) {
          events.add(event);
          await addEvent(event);
        }
      }
    }

    // ── English patterns ───────────────────────────────────────────

    // Pattern 1: "meeting with X tomorrow at 3pm"
    for (final match in _enAppointmentPatterns[0].allMatches(message)) {
      final title = match.group(1)?.trim() ?? '';
      final dayStr = match.group(2)?.trim().toLowerCase() ?? '';
      final timeRaw = match.group(3);
      final event = _parseEvent(
        type: EventType.meeting,
        title: title.isEmpty ? 'meeting' : title,
        dayStr: dayStr,
        timeStr: timeRaw != null ? _parseEnTimeStr(timeRaw) : null,
      );
      if (event != null && !events.any((e) => e.title == event.title)) {
        events.add(event);
        await addEvent(event);
      }
    }

    // Pattern 2: "tomorrow meeting with X at 3pm" (day-first English)
    for (final match in _enAppointmentPatterns[1].allMatches(message)) {
      final dayStr = match.group(1)?.trim().toLowerCase() ?? '';
      final title = match.group(2)?.trim() ?? '';
      final timeRaw = match.group(3);
      final event = _parseEvent(
        type: EventType.meeting,
        title: title.isEmpty ? 'meeting' : title,
        dayStr: dayStr,
        timeStr: timeRaw != null ? _parseEnTimeStr(timeRaw) : null,
      );
      if (event != null && !events.any((e) => e.title == event.title)) {
        events.add(event);
        await addEvent(event);
      }
    }

    return events;
  }

  /// แปลง English time string → hour string ที่ _parseEvent รับได้
  /// "3pm" → "15", "10am" → "10", "3:30pm" → "15" (minute ยังไม่ support ใน model)
  String? _parseEnTimeStr(String raw) {
    final cleaned = raw.trim().toLowerCase();
    final match = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)').firstMatch(cleaned);
    if (match == null) return null;
    int hour = int.parse(match.group(1)!);
    final period = match.group(3)!;
    if (period == 'pm' && hour < 12) hour += 12;
    if (period == 'am' && hour == 12) hour = 0;
    return hour.toString();
  }

  /// Parse event from matched strings
  CalendarEvent? _parseEvent({
    required EventType type,
    required String title,
    required String dayStr,
    String? timeStr,
  }) {
    // Clean title
    title = title.replaceAll(RegExp(r'[ครับค่ะนะ]+$'), '').trim();
    if (title.isEmpty) return null;

    // Parse date
    final date = _parseDate(dayStr);
    if (date == null) return null;

    // Parse time
    int? hour;
    if (timeStr != null) {
      hour = int.tryParse(timeStr);
    }

    return CalendarEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      title: title,
      date: date,
      time: hour != null ? TimeOfDay(hour: hour, minute: 0) : null,
      createdAt: DateTime.now(),
    );
  }

  /// Parse date from string
  DateTime? _parseDate(String dayStr) {
    final now = DateTime.now();

    // Check for simple offsets
    if (_dayOffsets.containsKey(dayStr)) {
      final offset = _dayOffsets[dayStr]!;
      if (offset >= 0) {
        return DateTime(now.year, now.month, now.day).add(Duration(days: offset));
      }
    }

    // Check for weekdays
    if (_weekdays.containsKey(dayStr)) {
      final targetWeekday = _weekdays[dayStr]!;
      var daysUntil = targetWeekday - now.weekday;
      if (daysUntil <= 0) daysUntil += 7; // Next week
      return DateTime(now.year, now.month, now.day).add(Duration(days: daysUntil));
    }

    // Try to find weekday in string
    for (final entry in _weekdays.entries) {
      if (dayStr.contains(entry.key)) {
        final targetWeekday = entry.value;
        var daysUntil = targetWeekday - now.weekday;
        if (daysUntil <= 0) daysUntil += 7;
        return DateTime(now.year, now.month, now.day).add(Duration(days: daysUntil));
      }
    }

    return null;
  }

  // ============================================================
  // 📝 EVENT MANAGEMENT
  // ============================================================

  /// เพิ่ม event
  Future<void> addEvent(CalendarEvent event) async {
    _events.add(event);
    await _saveEvents();

    // Save to RAG for context
    await _vectorService.addFact(
      category: 'calendar',
      content: '${event.type.name}: ${event.title} on ${event.date.toIso8601String()}',
      metadata: event.toJson(),
    );

    debugPrint('📅 CalendarWorker: Event added - ${event.title}');
  }

  /// ลบ event
  Future<void> removeEvent(String id) async {
    _events.removeWhere((e) => e.id == id);
    await _saveEvents();
  }

  /// Get events for date
  List<CalendarEvent> getEventsForDate(DateTime date) {
    final targetDate = DateTime(date.year, date.month, date.day);
    return _events.where((e) {
      final eventDate = DateTime(e.date.year, e.date.month, e.date.day);
      return eventDate == targetDate;
    }).toList();
  }

  /// Get today's events
  List<CalendarEvent> get todayEvents => getEventsForDate(DateTime.now());

  /// Get tomorrow's events
  List<CalendarEvent> get tomorrowEvents {
    return getEventsForDate(DateTime.now().add(const Duration(days: 1)));
  }

  /// Get upcoming events
  List<CalendarEvent> getUpcomingEvents({int days = 7}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = today.add(Duration(days: days));

    return _events.where((e) {
      return e.date.isAfter(today.subtract(const Duration(days: 1))) &&
          e.date.isBefore(cutoff);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  // ============================================================
  // 📦 LEAN FORMAT
  // ============================================================

  /// Get lean format for context
  String getLeanFormat() {
    final upcoming = getUpcomingEvents(days: 3);
    if (upcoming.isEmpty) return '';

    final parts = upcoming.take(3).map((e) {
      final timeStr = e.time != null ? ',${e.time!.hour}:00' : '';
      final dayStr = _getDayString(e.date);
      return '${e.title},$dayStr$timeStr';
    }).toList();

    return '[Cal:${parts.join(";")}]';
  }

  String _getDayString(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDate = DateTime(date.year, date.month, date.day);
    final diff = eventDate.difference(today).inDays;

    if (diff == 0) return 'วันนี้';
    if (diff == 1) return 'พรุ่งนี้';
    if (diff == 2) return 'มะรืน';

    final weekdays = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
    return weekdays[date.weekday - 1];
  }

  /// All events
  List<CalendarEvent> get allEvents => List.unmodifiable(_events);
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

enum EventType {
  appointment,
  meeting,
  event,
  reminder,
}

class TimeOfDay {
  final int hour;
  final int minute;

  TimeOfDay({required this.hour, required this.minute});

  factory TimeOfDay.fromJson(Map<String, dynamic> json) => TimeOfDay(
    hour: json['hour'] as int,
    minute: json['minute'] as int,
  );

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  @override
  String toString() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class CalendarEvent {
  final String id;
  final EventType type;
  final String title;
  final DateTime date;
  final TimeOfDay? time;
  final String? location;
  final String? notes;
  final DateTime createdAt;

  CalendarEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.date,
    this.time,
    this.location,
    this.notes,
    required this.createdAt,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
    id: json['id'] as String,
    type: EventType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => EventType.event,
    ),
    title: json['title'] as String,
    date: DateTime.parse(json['date'] as String),
    time: json['time'] != null
        ? TimeOfDay.fromJson(json['time'] as Map<String, dynamic>)
        : null,
    location: json['location'] as String?,
    notes: json['notes'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'date': date.toIso8601String(),
    'time': time?.toJson(),
    'location': location,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Get display string
  String toDisplayString() {
    final buffer = StringBuffer(title);
    if (time != null) {
      buffer.write(' $time');
    }
    if (location != null) {
      buffer.write(' @$location');
    }
    return buffer.toString();
  }
}
