import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'context_retriever.dart';
import 'triggers/trigger_service.dart';

/// 🔔 Notification Service - แจ้งเตือน + Quick Reply
/// 
/// รองรับ:
/// - Local notifications แบบมีปุ่มตอบกลับ
/// - Quick Reply โดยไม่ต้องเข้าแอพ
/// - Deep link กลับมาแอพ

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  
  bool _isInitialized = false;
  
  // Callback เมื่อผู้ใช้ตอบกลับจาก notification
  void Function(String triggerId, String response)? onQuickReply;
  void Function(TriggerEvent)? onNotificationTap;

  /// 🚀 เริ่มต้น service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Android settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // สร้าง Android Notification Channel
    await _createNotificationChannel();

    _isInitialized = true;
    debugPrint('✅ Notification Service initialized');
  }

  /// 📢 สร้าง Notification Channel (Android)
  Future<void> _createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      'haku_trigger_channel', // id
      'Haku Triggers', // name
      description: 'การแจ้งเตือนจาก Haku AI',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// 🔔 แสดง Trigger Notification พร้อม Quick Reply
  Future<void> showTriggerNotification(TriggerEvent event) async {
    if (!_isInitialized) {
      debugPrint('⚠️ NotificationService not initialized');
      return;
    }

    final triggerId = event.timestamp.millisecondsSinceEpoch.toString();
    
    // Quick Reply Actions
    final quickReplies = (event.data?['quickReplies'] as List<dynamic>?)?.cast<String>() ?? [];
    final actions = quickReplies.map((option) => AndroidNotificationAction(
        'reply_$option',
        option,
        showsUserInterface: false,
      )).toList();

    // เพิ่มปุ่ม "เปิดแอพ"
    actions.add(
      const AndroidNotificationAction(
        'open_app',
        'เปิดแอพ',
        showsUserInterface: true,
      ),
    );

    final androidDetails = AndroidNotificationDetails(
      'haku_trigger_channel',
      'Haku Triggers',
      channelDescription: 'การแจ้งเตือนจาก Haku AI',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.message,
      actions: actions,
      styleInformation: const BigTextStyleInformation(
        '',
        contentTitle: '',
        summaryText: 'แตะเพื่อตอบกลับ',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'trigger_category',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      event.timestamp.millisecond, // notification id
      event.toNotification()['title'] ?? 'Haku',
      event.message ?? 'Haku มีอะไรจะบอกคุณ',
      details,
      payload: triggerId,
    );

    debugPrint('🔔 Showed notification: ${event.toNotification()['title'] ?? "Haku"}');
  }

  /// 👆 จัดการเมื่อผู้ใช้ตอบกลับจาก notification
  void _onNotificationResponse(NotificationResponse response) async {
    final actionId = response.actionId;
    final payload = response.payload;
    
    debugPrint('📱 Notification response: action=$actionId, payload=$payload');

    if (actionId == null || actionId == 'open_app') {
      // เปิดแอพ
      await ContextRetriever().retrieveFullContext();
      onNotificationTap?.call(
        TriggerEvent(
          type: TriggerType.morning,
          subType: 'morning_start',
          message: 'สวัสดีตอนเช้า! พร้อมเริ่มวันใหม่ไหมคะ?',
          data: {'quickReplies': ['พร้อมมาก!', 'ยังง่วง', 'วันนี้มีอะไร?']},
        ),
      );
      return;
    }

    // Quick Reply
    if (actionId.startsWith('reply_')) {
      final reply = actionId.replaceFirst('reply_', '');
      onQuickReply?.call(payload ?? '', reply);
      
      // แสดง toast ยืนยัน
      debugPrint('💬 Quick reply: $reply');
    }
  }

  /// 🧹 ยกเลิกการแจ้งเตือนทั้งหมด
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  /// 🧹 ยกเลิกการแจ้งเตือนเฉพาะ id
  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }

  /// 📢 แสดง notification ทั่วไป (สำหรับ external services)
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
    String? payload,
  }) async {
    if (!_isInitialized) {
      debugPrint('⚠️ NotificationService not initialized');
      return;
    }

    await _notifications.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// 📢 แสดง notification ง่าย (ใช้ default channel)
  Future<void> showSimpleNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    Importance importance = Importance.high,
  }) async {
    if (!_isInitialized) {
      debugPrint('⚠️ NotificationService not initialized');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'haku_trigger_channel',
      'Haku Triggers',
      channelDescription: 'การแจ้งเตือนจาก Haku AI',
      importance: importance,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(id, title, body, details, payload: payload);
  }
}


