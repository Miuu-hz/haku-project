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

const _kNotifChannel = 'haku_proactive_triggers';
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

  /// ยกเลิก morning + evening alarms และ reset idempotency guard
  static Future<void> cancelDailyTriggers() async {
    await _plugin.cancel(_kMorningId);
    await _plugin.cancel(_kEveningId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_scheduled_daily_triggers');
    debugPrint('⏰ Daily triggers cancelled');
  }

  /// Schedule morning (09:00) + evening (20:00) daily repeating notifications
  /// Idempotent: ถ้าเคย schedule แล้วจะ skip
  /// เคารพ proactive_morning_enabled / proactive_evening_enabled จาก SharedPreferences
  static Future<void> scheduleDailyTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final lastScheduled = prefs.getInt('last_scheduled_daily_triggers') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // ถ้าเคย schedule ภายใน 1 ชั่วโมงที่ผ่านมา → skip (idempotent)
    if (now - lastScheduled < 3600000) {
      debugPrint('⏰ Daily triggers already scheduled (within 1 hour)');
      return;
    }

    final morningEnabled = prefs.getBool('proactive_morning_enabled') ?? true;
    final eveningEnabled = prefs.getBool('proactive_evening_enabled') ?? true;

    if (!morningEnabled && !eveningEnabled) {
      await prefs.setInt('last_scheduled_daily_triggers', now);
      debugPrint('⏰ Daily triggers skipped (both disabled)');
      return;
    }

    final morningBody = await _buildMorningBody();
    final eveningBody = await _buildEveningBody();

    const notifDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _kNotifChannel,
        'Haku Proactive',
        channelDescription: 'แจ้งเตือนตามเวลาจาก Haku',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    // Morning 09:00
    if (morningEnabled) {
      await _plugin.zonedSchedule(
        _kMorningId,
        'สวัสดีตอนเช้า ☀️',
        morningBody,
        _nextInstanceOf(9, 0),
        notifDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }

    // Evening 20:00
    if (eveningEnabled) {
      await _plugin.zonedSchedule(
        _kEveningId,
        'เย็นแล้ว 🌙',
        eveningBody,
        _nextInstanceOf(20, 0),
        notifDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }

    await prefs.setInt('last_scheduled_daily_triggers', now);
    debugPrint('⏰ Daily triggers scheduled: morning=$morningEnabled evening=$eveningEnabled');
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

  // ─── Focus Timer Notifications ──────────────────────────────

  static const _kBreakStartId  = 903;
  static const _kFocusRemindId = 904;

  static const _kFocusDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _kNotifChannel,
      'Haku Proactive',
      channelDescription: 'แจ้งเตือนตามเวลาจาก Haku',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// แจ้งเตือนเมื่อ Pomodoro Focus เสร็จ — เริ่มพัก
  static Future<void> showBreakStartNotification({
    required bool isLong,
    String? goalTitle,
  }) async {
    if (!_initialized) return;
    final title = isLong ? '🎉 พักยาว 15 นาที!' : '☕ พักสั้น 5 นาที!';
    final body  = goalTitle != null
        ? '$goalTitle — Pomodoro เสร็จแล้ว พักก่อนนะ'
        : 'Focus เสร็จแล้ว! พักแล้วเริ่มรอบใหม่ได้เลย';
    await _plugin.show(_kBreakStartId, title, body, _kFocusDetails);
    debugPrint('🍅 Break start notif: $title');
  }

  /// แจ้งเตือนเมื่อ Break เสร็จ — ถึงเวลา Focus อีกครั้ง
  static Future<void> showFocusReminderNotification() async {
    if (!_initialized) return;
    await _plugin.show(
      _kFocusRemindId,
      '⏱️ ถึงเวลา Focus แล้ว!',
      'พักพอแล้ว เริ่มรอบใหม่ได้เลย 💪',
      _kFocusDetails,
    );
    debugPrint('⏱️ Focus reminder notif sent');
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
