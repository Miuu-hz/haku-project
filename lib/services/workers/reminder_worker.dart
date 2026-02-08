import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../unified_vector_service.dart';

/// 🔔 Reminder Worker - ตรวจจับและจัดการการเตือน
///
/// ตรวจจับ:
/// - "เตือนกินยา 8 โมงเช้า"
/// - "อย่าลืมซื้อของ"
/// - "เตือนทุกวัน 7 โมง"
///
/// Output format: [Rem:ยา,08:00,daily]

class ReminderWorker {
  static final ReminderWorker _instance = ReminderWorker._internal();
  factory ReminderWorker() => _instance;
  ReminderWorker._internal();

  static const String _remindersKey = 'reminders';

  final UnifiedVectorService _vectorService = UnifiedVectorService();
  final List<Reminder> _reminders = [];
  bool _isInitialized = false;

  // ============================================================
  // 🔍 DETECTION PATTERNS
  // ============================================================

  /// เตือน
  static final List<RegExp> _reminderPatterns = [
    RegExp(r'เตือน(.+?)(?:ตอน|เวลา)?\s*(\d+)\s*(?:โมง|:)(\d+)?(?:\s*(เช้า|บ่าย|เย็น|ค่ำ))?', caseSensitive: false),
    RegExp(r'เตือน(.+?)ทุก(วัน|เช้า|เย็น)', caseSensitive: false),
    RegExp(r'อย่าลืม(.+?)(?:นะ|ด้วย)?', caseSensitive: false),
  ];

  /// ความถี่
  static final Map<String, ReminderFrequency> _frequencyMap = {
    'ทุกวัน': ReminderFrequency.daily,
    'ทุกเช้า': ReminderFrequency.daily,
    'ทุกเย็น': ReminderFrequency.daily,
    'ทุกสัปดาห์': ReminderFrequency.weekly,
    'ครั้งเดียว': ReminderFrequency.once,
  };

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadReminders();
    _isInitialized = true;
    debugPrint('✅ ReminderWorker initialized: ${_reminders.length} reminders');
  }

  Future<void> _loadReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_remindersKey);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _reminders.clear();
        _reminders.addAll(
          list.map((e) => Reminder.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error loading reminders: $e');
    }
  }

  Future<void> _saveReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _remindersKey,
        jsonEncode(_reminders.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving reminders: $e');
    }
  }

  // ============================================================
  // 🔍 DETECTION
  // ============================================================

  /// ตรวจจับ reminders จากข้อความ
  Future<List<Reminder>> detectReminders(String message) async {
    final reminders = <Reminder>[];

    for (final pattern in _reminderPatterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        final reminder = _parseReminder(match, message);
        if (reminder != null) {
          reminders.add(reminder);
          await addReminder(reminder);
        }
      }
    }

    return reminders;
  }

  Reminder? _parseReminder(RegExpMatch match, String originalMessage) {
    String content = match.group(1)?.trim() ?? '';
    content = content.replaceAll(RegExp(r'[ครับค่ะนะ]+$'), '').trim();

    if (content.isEmpty) return null;

    // Parse time
    int? hour;
    int minute = 0;

    if (match.groupCount >= 2) {
      hour = int.tryParse(match.group(2) ?? '');
    }

    if (match.groupCount >= 3 && match.group(3) != null) {
      minute = int.tryParse(match.group(3)!) ?? 0;
    }

    // Adjust for AM/PM
    if (match.groupCount >= 4 && hour != null) {
      final period = match.group(4);
      if (period == 'บ่าย' || period == 'เย็น' || period == 'ค่ำ') {
        if (hour < 12) hour += 12;
      }
    }

    // Parse frequency
    ReminderFrequency frequency = ReminderFrequency.once;
    for (final entry in _frequencyMap.entries) {
      if (originalMessage.contains(entry.key)) {
        frequency = entry.value;
        break;
      }
    }

    // Default to daily if no time specified but has "ทุก"
    if (hour == null && originalMessage.contains('ทุก')) {
      hour = 8; // Default morning
      frequency = ReminderFrequency.daily;
    }

    return Reminder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      time: hour != null ? ReminderTime(hour: hour, minute: minute) : null,
      frequency: frequency,
      isActive: true,
      createdAt: DateTime.now(),
    );
  }

  // ============================================================
  // 📝 REMINDER MANAGEMENT
  // ============================================================

  /// เพิ่ม reminder
  Future<void> addReminder(Reminder reminder) async {
    _reminders.add(reminder);
    await _saveReminders();

    // Save to RAG for long-term analysis
    await _vectorService.addFact(
      category: 'reminder',
      content: '${reminder.content} at ${reminder.time?.toString() ?? "unspecified"} (${reminder.frequency.name})',
      metadata: reminder.toJson(),
    );

    debugPrint('🔔 ReminderWorker: Added - ${reminder.content}');
  }

  /// ลบ reminder
  Future<void> removeReminder(String id) async {
    _reminders.removeWhere((r) => r.id == id);
    await _saveReminders();
  }

  /// Toggle reminder
  Future<void> toggleReminder(String id) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index >= 0) {
      _reminders[index] = _reminders[index].copyWith(
        isActive: !_reminders[index].isActive,
      );
      await _saveReminders();
    }
  }

  /// Get reminders for specific time
  List<Reminder> getRemindersForTime(int hour, int minute) {
    return _reminders.where((r) {
      if (!r.isActive || r.time == null) return false;
      return r.time!.hour == hour && r.time!.minute == minute;
    }).toList();
  }

  /// Get active reminders
  List<Reminder> get activeReminders {
    return _reminders.where((r) => r.isActive).toList();
  }

  /// Get all reminders
  List<Reminder> get allReminders => List.unmodifiable(_reminders);

  // ============================================================
  // 📦 LEAN FORMAT
  // ============================================================

  /// Get lean format for context
  String getLeanFormat() {
    final active = activeReminders;
    if (active.isEmpty) return '';

    final parts = active.take(3).map((r) {
      final timeStr = r.time != null ? '${r.time!.hour}:${r.time!.minute.toString().padLeft(2, '0')}' : 'any';
      final freqStr = r.frequency.shortName;
      return '${r.content},$timeStr,$freqStr';
    }).toList();

    return '[Rem:${parts.join(";")}]';
  }

  /// Check due reminders
  List<Reminder> checkDueReminders() {
    final now = DateTime.now();
    final dueReminders = <Reminder>[];

    for (final reminder in _reminders) {
      if (!reminder.isActive) continue;
      if (reminder.time == null) continue;

      if (reminder.time!.hour == now.hour && reminder.time!.minute == now.minute) {
        // Check frequency
        if (reminder.frequency == ReminderFrequency.once) {
          // Check if already triggered today
          if (reminder.lastTriggered != null) {
            final lastDate = DateTime(
              reminder.lastTriggered!.year,
              reminder.lastTriggered!.month,
              reminder.lastTriggered!.day,
            );
            final today = DateTime(now.year, now.month, now.day);
            if (lastDate == today) continue;
          }
        }

        dueReminders.add(reminder);
      }
    }

    return dueReminders;
  }

  /// Mark reminder as triggered
  Future<void> markTriggered(String id) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index >= 0) {
      _reminders[index] = _reminders[index].copyWith(
        lastTriggered: DateTime.now(),
      );

      // Deactivate if once
      if (_reminders[index].frequency == ReminderFrequency.once) {
        _reminders[index] = _reminders[index].copyWith(isActive: false);
      }

      await _saveReminders();
    }
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

enum ReminderFrequency {
  once,
  daily,
  weekly,
  monthly,
}

extension ReminderFrequencyExtension on ReminderFrequency {
  String get shortName {
    switch (this) {
      case ReminderFrequency.once: return '1x';
      case ReminderFrequency.daily: return 'daily';
      case ReminderFrequency.weekly: return 'weekly';
      case ReminderFrequency.monthly: return 'monthly';
    }
  }

  String get displayName {
    switch (this) {
      case ReminderFrequency.once: return 'ครั้งเดียว';
      case ReminderFrequency.daily: return 'ทุกวัน';
      case ReminderFrequency.weekly: return 'ทุกสัปดาห์';
      case ReminderFrequency.monthly: return 'ทุกเดือน';
    }
  }
}

class ReminderTime {
  final int hour;
  final int minute;

  ReminderTime({required this.hour, required this.minute});

  factory ReminderTime.fromJson(Map<String, dynamic> json) => ReminderTime(
    hour: json['hour'] as int,
    minute: json['minute'] as int,
  );

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  @override
  String toString() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class Reminder {
  final String id;
  final String content;
  final ReminderTime? time;
  final ReminderFrequency frequency;
  final bool isActive;
  final DateTime? lastTriggered;
  final DateTime createdAt;

  Reminder({
    required this.id,
    required this.content,
    this.time,
    required this.frequency,
    required this.isActive,
    this.lastTriggered,
    required this.createdAt,
  });

  Reminder copyWith({
    String? content,
    ReminderTime? time,
    ReminderFrequency? frequency,
    bool? isActive,
    DateTime? lastTriggered,
  }) => Reminder(
    id: id,
    content: content ?? this.content,
    time: time ?? this.time,
    frequency: frequency ?? this.frequency,
    isActive: isActive ?? this.isActive,
    lastTriggered: lastTriggered ?? this.lastTriggered,
    createdAt: createdAt,
  );

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
    id: json['id'] as String,
    content: json['content'] as String,
    time: json['time'] != null
        ? ReminderTime.fromJson(json['time'] as Map<String, dynamic>)
        : null,
    frequency: ReminderFrequency.values.firstWhere(
      (f) => f.name == json['frequency'],
      orElse: () => ReminderFrequency.once,
    ),
    isActive: json['isActive'] as bool? ?? true,
    lastTriggered: json['lastTriggered'] != null
        ? DateTime.parse(json['lastTriggered'] as String)
        : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'time': time?.toJson(),
    'frequency': frequency.name,
    'isActive': isActive,
    'lastTriggered': lastTriggered?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  String toDisplayString() {
    final timeStr = time?.toString() ?? 'ไม่ระบุเวลา';
    return '$content ($timeStr, ${frequency.displayName})';
  }
}
