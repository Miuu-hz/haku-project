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

  /// นัดหมาย
  static final List<RegExp> _appointmentPatterns = [
    RegExp(r'นัด(.+?)(วันนี้|พรุ่งนี้|มะรืน|วัน.+?)(?:\s*(\d+)\s*(?:โมง|:))?', caseSensitive: false),
    RegExp(r'ไป(.+?)(วันนี้|พรุ่งนี้|มะรืน|วัน.+?)(?:\s*(\d+)\s*(?:โมง|:))?', caseSensitive: false),
  ];

  /// ประชุม
  static final List<RegExp> _meetingPatterns = [
    RegExp(r'ประชุม(.+?)(วันนี้|พรุ่งนี้|วัน.+?)(?:\s*(\d+)\s*(?:โมง|:))?', caseSensitive: false),
    RegExp(r'meeting(.+?)(วันนี้|พรุ่งนี้|today|tomorrow)', caseSensitive: false),
  ];

  /// วันที่
  static final Map<String, int> _dayOffsets = {
    'วันนี้': 0,
    'today': 0,
    'พรุ่งนี้': 1,
    'tomorrow': 1,
    'มะรืน': 2,
    'วันจันทร์': -1, // special handling
    'วันอังคาร': -1,
    'วันพุธ': -1,
    'วันพฤหัส': -1,
    'วันศุกร์': -1,
    'วันเสาร์': -1,
    'วันอาทิตย์': -1,
  };

  static final Map<String, int> _weekdays = {
    'วันจันทร์': DateTime.monday,
    'วันอังคาร': DateTime.tuesday,
    'วันพุธ': DateTime.wednesday,
    'วันพฤหัส': DateTime.thursday,
    'วันศุกร์': DateTime.friday,
    'วันเสาร์': DateTime.saturday,
    'วันอาทิตย์': DateTime.sunday,
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

  /// ตรวจจับนัดหมายจากข้อความ
  Future<List<CalendarEvent>> detectEvents(String message) async {
    final events = <CalendarEvent>[];

    // ตรวจจับ appointments
    for (final pattern in _appointmentPatterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        final event = _parseEvent(
          type: EventType.appointment,
          title: match.group(1)?.trim() ?? '',
          dayStr: match.group(2)?.trim() ?? '',
          timeStr: match.group(3),
        );
        if (event != null) {
          events.add(event);
          await addEvent(event);
        }
      }
    }

    // ตรวจจับ meetings
    for (final pattern in _meetingPatterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        final event = _parseEvent(
          type: EventType.meeting,
          title: match.group(1)?.trim() ?? 'ประชุม',
          dayStr: match.group(2)?.trim() ?? '',
          timeStr: match.group(3),
        );
        if (event != null) {
          events.add(event);
          await addEvent(event);
        }
      }
    }

    return events;
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

  /// เพิ่ม event (สำหรับ Dispatcher)
  Future<void> add({
    required String title,
    DateTime? date,
    String? time,
    String? location,
    EventType type = EventType.event,
  }) async {
    // Parse time string (e.g., "10:00")
    TimeOfDay? eventTime;
    if (time != null) {
      final parts = time.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          eventTime = TimeOfDay(hour: hour, minute: minute);
        }
      }
    }

    final event = CalendarEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      title: title,
      date: date ?? DateTime.now(),
      time: eventTime,
      location: location,
      createdAt: DateTime.now(),
    );

    await addEvent(event);
  }

  /// เพิ่ม event (จาก object)
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

/// 📅 Calendar Event - รวมจาก EventInfo (กลุ่ม 8)
class CalendarEvent {
  final String id;
  final EventType type;
  final String title;
  final DateTime date;
  final TimeOfDay? time;
  final String? location;
  final String? notes;
  final DateTime createdAt;
  final int durationMinutes; // จาก EventInfo
  final String? originalText; // จาก EventInfo

  CalendarEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.date,
    this.time,
    this.location,
    this.notes,
    required this.createdAt,
    this.durationMinutes = 60,
    this.originalText,
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

  /// Display time for UI (จาก EventInfo)
  String get displayTime {
    final timeStr = time?.toString() ?? '';
    if (timeStr.isNotEmpty) {
      return '${date.day}/${date.month} เวลา $timeStr';
    }
    return '${date.day}/${date.month}';
  }

  /// Factory สำหรับสร้างจาก extraction result (แทน EventInfo)
  factory CalendarEvent.fromExtraction({
    required String title,
    DateTime? date,
    String? time,
    int durationMinutes = 60,
    String? location,
    String? originalText,
  }) {
    // Parse time string "HH:MM" to TimeOfDay
    TimeOfDay? timeOfDay;
    if (time != null && time.contains(':')) {
      final parts = time.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;
        timeOfDay = TimeOfDay(hour: hour, minute: minute);
      }
    }

    return CalendarEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: EventType.event,
      title: title,
      date: date ?? DateTime.now(),
      time: timeOfDay,
      durationMinutes: durationMinutes,
      location: location,
      originalText: originalText,
      createdAt: DateTime.now(),
    );
  }
}
