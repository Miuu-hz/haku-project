import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// ⏰ Background Task Service — zonedSchedule สำหรับ time triggers
///
/// ใช้ flutter_local_notifications + AlarmManager เพื่อ:
/// - 09:00 → Morning agenda notification (repeat ทุกวัน)
/// - 20:00 → Evening summary notification (repeat ทุกวัน)
///
/// ทำงานได้แม้แอพปิด (AlarmManager-based, ไม่ขึ้นกับ Flutter engine)
/// ข้อมูล calendar อ่านจาก SharedPreferences 'calendar_events'

const _kNotifChannel = 'haku_triggers';
const _kMorningId = 901;
const _kEveningId = 902;
const _kCalendarKey = 'calendar_events';

// ─── BackgroundTaskService ──────────────────────────────────────

class BackgroundTaskService {
  BackgroundTaskService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// เรียกใน main() ก่อน runApp()
  static Future<void> initialize() async {
    if (_initialized) return;

    // โหลด timezone database (ใช้ UTC + Dart offset math แทน native plugin)
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    _initialized = true;
    debugPrint('✅ BackgroundTaskService initialized');
  }

  /// Schedule morning (09:00) + evening (20:00) daily repeating notifications
  static Future<void> scheduleDailyTriggers() async {
    final morningBody = await _buildMorningBody();
    final eveningBody = await _buildEveningBody();

    const notifDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _kNotifChannel,
        'Haku Triggers',
        channelDescription: 'แจ้งเตือนตามเวลาจาก Haku',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    // Morning 09:00
    await _plugin.zonedSchedule(
      _kMorningId,
      'สวัสดีตอนเช้า ☀️',
      morningBody,
      _nextInstanceOf(9, 0),
      notifDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // Evening 20:00
    await _plugin.zonedSchedule(
      _kEveningId,
      'เย็นแล้ว 🌙',
      eveningBody,
      _nextInstanceOf(20, 0),
      notifDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    debugPrint('⏰ Daily triggers scheduled: 09:00 + 20:00');
  }

  /// คำนวณ TZDateTime ถัดไปสำหรับเวลาที่กำหนด (local time → UTC TZDateTime)
  /// ใช้ Dart built-in timezone offset แทน native plugin
  static tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    // toUtc() แปลงเวลาท้องถิ่น → UTC โดยใช้ offset ของอุปกรณ์
    return tz.TZDateTime.from(target.toUtc(), tz.UTC);
  }

  /// ยกเลิก triggers ทั้งหมด (เรียกตอน reset / uninstall)
  static Future<void> cancelAll() async {
    await _plugin.cancel(_kMorningId);
    await _plugin.cancel(_kEveningId);
    debugPrint('⏰ Daily triggers cancelled');
  }
}

// ─── Message builders (อ่านจาก SharedPreferences) ─────────────

Future<String> _buildMorningBody() async {
  final today = DateTime.now();
  final events = await _loadTodayEvents(today);

  if (events.isEmpty) return 'วันนี้ไม่มีนัดหมาย เปิด Haku เพื่อวางแผนวันนี้ได้เลย';

  final count = events.length;
  final preview = events.take(2).map((e) {
    final title = e['title'] as String? ?? 'กิจกรรม';
    final time = e['time'] as Map<String, dynamic>?;
    if (time != null) {
      final h = time['hour'] as int? ?? 0;
      final m = (time['minute'] as int? ?? 0).toString().padLeft(2, '0');
      return '$title $h:$m';
    }
    return title;
  }).join(', ');

  return 'วันนี้มี $count นัด: $preview${count > 2 ? " ..." : ""}';
}

Future<String> _buildEveningBody() async {
  final today = DateTime.now();
  final events = await _loadTodayEvents(today);

  if (events.isEmpty) return 'ถึงเวลาสรุปวันนี้กับ Haku แล้วค่ะ 📝';
  return 'วันนี้มีนัด ${events.length} รายการ วันนี้เป็นยังไงบ้างคะ?';
}

Future<List<Map<String, dynamic>>> _loadTodayEvents(DateTime today) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kCalendarKey);
    if (json == null) return [];

    final list = jsonDecode(json) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .where((e) {
          final dateStr = e['date'] as String?;
          if (dateStr == null) return false;
          final date = DateTime.tryParse(dateStr);
          return date != null &&
              date.year == today.year &&
              date.month == today.month &&
              date.day == today.day;
        })
        .toList();
  } catch (_) {
    return [];
  }
}
