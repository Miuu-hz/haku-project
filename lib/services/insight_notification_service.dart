import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/correlation_models.dart';
import 'notification_service.dart';

/// Extension ให้ InsightNotificationService เข้าถึง _notificationService ใน NotificationService
extension NotificationServiceExt on NotificationService {
  NotificationService get instance => this;
}

/// 🔮 Insight Notification Service - แจ้งเตือนเมื่อพบ insight ใหม่
///
/// ฟีเจอร์:
/// - ตรวจสอบ insights ใหม่ทุกครั้งที่มีการวิเคราะห์
/// - แจ้งเตือนเฉพาะ insights ที่น่าสนใจ (high confidence + high correlation)
/// - ไม่ซ้ำ (เก็บ history ของ insights ที่แจ้งเตือนแล้ว)
/// - สามารถ snooze หรือปิดการแจ้งเตือนได้

class InsightNotificationService {
  static final InsightNotificationService _instance = InsightNotificationService._internal();
  factory InsightNotificationService() => _instance;
  InsightNotificationService._internal();

  final NotificationService _notificationService = NotificationService();

  static const String _notifiedInsightsKey = 'notified_insights';
  static const String _snoozeUntilKey = 'insight_snooze_until';
  static const String _enabledKey = 'insight_notifications_enabled';

  bool _isInitialized = false;

  /// 🚀 เริ่มต้น service
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _notificationService.initialize();
    _isInitialized = true;

    debugPrint('✅ InsightNotificationService initialized');
  }

  // ============================================================
  // 🔔 MAIN NOTIFICATION METHODS
  // ============================================================

  /// 🔮 ตรวจสอบและแจ้งเตือน insights ใหม่
  ///
  /// เรียกหลังจากวิเคราะห์เสร็จ
  Future<void> checkAndNotifyNewInsights(CorrelationAnalysisResult result) async {
    if (!await _isEnabled()) {
      debugPrint('🔕 Insight notifications disabled');
      return;
    }

    if (await _isSnoozed()) {
      debugPrint('🔕 Insights snoozed until ${_getSnoozeUntil()}');
      return;
    }

    // กรอง insights ที่น่าสนใจ
    final interestingInsights = result.interestingInsights
        .where((i) => i.confidence > 0.7 && i.correlation.abs() > 0.6)
        .toList();

    if (interestingInsights.isEmpty) {
      debugPrint('🔮 No interesting new insights to notify');
      return;
    }

    // หา insights ที่ยังไม่เคยแจ้งเตือน
    final newInsights = await _filterNewInsights(interestingInsights);

    if (newInsights.isEmpty) {
      debugPrint('🔮 All interesting insights already notified');
      return;
    }

    // แจ้งเตือน insight ที่น่าสนใจที่สุด
    final topInsight = newInsights.first;
    await _showInsightNotification(topInsight, newInsights.length);

    // บันทึกว่าแจ้งเตือนแล้ว
    await _markAsNotified(newInsights);

    debugPrint('🔔 Notified ${newInsights.length} new insights');
  }

  /// 🔮 แจ้งเตือน insight เดี่ยว (ใช้กรณีพบระหว่างการทำงาน)
  Future<void> notifyInsight(CorrelationInsight insight) async {
    if (!await _isEnabled() || await _isSnoozed()) return;

    if (await _isAlreadyNotified(insight.id)) return;

    await _showInsightNotification(insight, 1);
    await _markAsNotified([insight]);
  }

  /// 🎯 แจ้งเตือน health insight ด่วน
  Future<void> notifyHealthInsight(CorrelationInsight insight) async {
    if (!await _isEnabled()) return; // Health insight ไม่สน snooze

    if (await _isAlreadyNotified(insight.id)) return;

    await _showHealthInsightNotification(insight);
    await _markAsNotified([insight]);
  }

  // ============================================================
  // 📱 NOTIFICATION DISPLAY
  // ============================================================

  /// 🔔 แสดง notification ปกติ
  Future<void> _showInsightNotification(CorrelationInsight insight, int totalNew) async {
    final title = totalNew > 1
        ? '🔮 พบ $totalNew ความเชื่อมโยงใหม่!'
        : '🔮 พบความเชื่อมโยงใหม่!';

    final body = _createNotificationBody(insight);
    final recommendation = insight.getRecommendation();

    // สร้าง actions
    final actions = <AndroidNotificationAction>[
      const AndroidNotificationAction(
        'view_insights',
        'ดูรายละเอียด',
        showsUserInterface: true,
      ),
    ];

    if (recommendation != null) {
      actions.add(
        const AndroidNotificationAction(
          'acknowledge',
          'รับทราบ',
          showsUserInterface: false,
        ),
      );
    }

    actions.add(
      const AndroidNotificationAction(
        'snooze',
        'เลื่อน',
        showsUserInterface: false,
      ),
    );

    final androidDetails = AndroidNotificationDetails(
      'haku_insight_channel',
      'Haku Insights',
      channelDescription: 'การแจ้งเตือนความเชื่อมโยงที่พบ',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.recommendation,
      actions: actions,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: recommendation ?? 'แตะเพื่อดูรายละเอียด',
      ),
      color: Colors.purple, // Purple
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationService.showNotification(
      id: _generateNotificationId(insight.id),
      title: title,
      body: body,
      details: details,
      payload: jsonEncode({
        'type': 'insight',
        'insightId': insight.id,
        'entityA': insight.entityAValue,
        'entityB': insight.entityBValue,
      }),
    );
  }

  /// 🏥 แสดง health notification (สำคัญกว่า)
  Future<void> _showHealthInsightNotification(CorrelationInsight insight) async {
    final body = _createHealthNotificationBody(insight);

    final androidDetails = AndroidNotificationDetails(
      'haku_health_insight_channel',
      'Haku Health Insights',
      channelDescription: 'การแจ้งเตือนด้านสุขภาพที่สำคัญ',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.alarm,
      color: Colors.pink, // Pink/Red
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationService.showNotification(
      id: _generateNotificationId(insight.id),
      title: '⚠️ พบความเชื่อมโยงด้านสุขภาพ',
      body: body,
      details: details,
      payload: jsonEncode({
        'type': 'health_insight',
        'insightId': insight.id,
      }),
    );
  }

  /// 📝 สร้างข้อความ notification
  String _createNotificationBody(CorrelationInsight insight) {
    final buffer = StringBuffer();

    // ความเชื่อมโยง
    buffer.writeln('${insight.entityAValue} ↔ ${insight.entityBValue}');
    buffer.writeln();

    // คำอธิบายสั้น
    final shortDesc = insight.description.length > 100
        ? '${insight.description.substring(0, 100)}...'
        : insight.description;
    buffer.write(shortDesc);

    return buffer.toString();
  }

  /// 📝 สร้างข้อความ health notification
  String _createHealthNotificationBody(CorrelationInsight insight) {
    final recommendation = insight.getRecommendation();
    if (recommendation != null) {
      return recommendation;
    }

    return '${insight.entityAValue} อาจส่งผลต่อ ${insight.entityBValue} (${(insight.correlation * 100).round()}%)';
  }

  // ============================================================
  // 🗂️ INSIGHT TRACKING
  // ============================================================

  /// กรอง insights ที่ยังไม่เคยแจ้งเตือน
  Future<List<CorrelationInsight>> _filterNewInsights(List<CorrelationInsight> insights) async {
    final notifiedIds = await _getNotifiedIds();
    return insights.where((i) => !notifiedIds.contains(i.id)).toList();
  }

  /// เช็คว่าเคยแจ้งเตือนแล้วหรือไม่
  Future<bool> _isAlreadyNotified(String insightId) async {
    final notifiedIds = await _getNotifiedIds();
    return notifiedIds.contains(insightId);
  }

  /// บันทึกว่าแจ้งเตือนแล้ว
  Future<void> _markAsNotified(List<CorrelationInsight> insights) async {
    final prefs = await SharedPreferences.getInstance();
    final notifiedIds = await _getNotifiedIds();

    // เพิ่ม ID ใหม่
    for (final insight in insights) {
      notifiedIds.add(insight.id);
    }

    // เก็บแค่ 100 ID ล่าสุด (ไม่ให้ list ใหญ่เกินไป)
    final toSave = notifiedIds.length > 100
        ? notifiedIds.skip(notifiedIds.length - 100).toList()
        : notifiedIds;

    await prefs.setStringList(_notifiedInsightsKey, toSave);
  }

  /// ดึงรายการ ID ที่เคยแจ้งเตือน
  Future<List<String>> _getNotifiedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_notifiedInsightsKey) ?? [];
  }

  /// สร้าง notification ID จาก insight ID
  int _generateNotificationId(String insightId) {
    // Hash insightId เป็น int
    return insightId.hashCode.abs() % 100000;
  }

  // ============================================================
  // ⚙️ SETTINGS
  // ============================================================

  /// เปิด/ปิดการแจ้งเตือน
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    debugPrint(enabled ? '🔔 Insight notifications enabled' : '🔕 Insight notifications disabled');
  }

  /// เช็คว่าเปิดอยู่หรือไม่
  Future<bool> _isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true; // default: เปิด
  }

  /// Snooze การแจ้งเตือน
  Future<void> snooze({Duration duration = const Duration(hours: 24)}) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(duration);
    await prefs.setString(_snoozeUntilKey, until.toIso8601String());
    debugPrint('🔕 Insights snoozed until $until');
  }

  /// เช็คว่ากำลัง snooze อยู่หรือไม่
  Future<bool> _isSnoozed() async {
    final prefs = await SharedPreferences.getInstance();
    final untilStr = prefs.getString(_snoozeUntilKey);
    if (untilStr == null) return false;

    final until = DateTime.parse(untilStr);
    return DateTime.now().isBefore(until);
  }

  /// ดึงเวลา snooze
  DateTime? _getSnoozeUntil() {
    // Note: ต้องเรียก async ภายนอก ที่นี่เป็น helper
    return null;
  }

  /// ยกเลิก snooze
  Future<void> cancelSnooze() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_snoozeUntilKey);
    debugPrint('🔔 Snooze cancelled');
  }

  /// ล้างประวัติการแจ้งเตือนทั้งหมด
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_notifiedInsightsKey);
    debugPrint('🧹 Insight notification history cleared');
  }

  /// ดึง settings ทั้งหมด
  Future<Map<String, dynamic>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final enabled = prefs.getBool(_enabledKey) ?? true;
    final snoozeStr = prefs.getString(_snoozeUntilKey);
    final notifiedCount = (prefs.getStringList(_notifiedInsightsKey) ?? []).length;

    return {
      'enabled': enabled,
      'snoozedUntil': snoozeStr != null ? DateTime.parse(snoozeStr) : null,
      'totalNotified': notifiedCount,
    };
  }

  // ============================================================
  // 🎯 BATCH NOTIFICATION
  // ============================================================

  /// แจ้งเตือนรวม (summary) ถ้ามีหลาย insights
  Future<void> notifyBatch(List<CorrelationInsight> insights) async {
    if (insights.isEmpty) return;
    if (!await _isEnabled() || await _isSnoozed()) return;

    // กรองเฉพาะใหม่
    final newInsights = await _filterNewInsights(insights);
    if (newInsights.isEmpty) return;

    if (newInsights.length == 1) {
      await _showInsightNotification(newInsights.first, 1);
    } else {
      // แสดง summary
      await _showBatchNotification(newInsights);
    }

    await _markAsNotified(newInsights);
  }

  /// แสดง batch notification
  Future<void> _showBatchNotification(List<CorrelationInsight> insights) async {
    final title = '🔮 พบ ${insights.length} ความเชื่อมโยงใหม่!';
    final body = insights.map((i) => '• ${i.entityAValue} ↔ ${i.entityBValue}').join('\n');

    const androidDetails = AndroidNotificationDetails(
      'haku_insight_channel',
      'Haku Insights',
      channelDescription: 'การแจ้งเตือนความเชื่อมโยงที่พบ',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: InboxStyleInformation(
        [],
        contentTitle: 'พบความเชื่อมโยงใหม่หลายรายการ',
        summaryText: 'แตะเพื่อดูทั้งหมด',
      ),
    );

    const details = NotificationDetails(android: androidDetails);

    await _notificationService.showNotification(
      id: 99999, // fixed ID for batch
      title: title,
      body: body,
      details: details,
      payload: jsonEncode({
        'type': 'insight_batch',
        'count': insights.length,
      }),
    );
  }
}


