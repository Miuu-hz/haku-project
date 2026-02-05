import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'context_retriever.dart';
import 'mvp_trigger_service.dart';

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
    final actions = event.quickReplyOptions.map((option) {
      return AndroidNotificationAction(
        'reply_$option',
        option,
        showsUserInterface: false,
      );
    }).toList();

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
      event.displayTitle,
      event.suggestedMessage ?? 'Haku มีอะไรจะบอกคุณ',
      details,
      payload: triggerId,
    );

    debugPrint('🔔 Showed notification: ${event.displayTitle}');
  }

  /// 👆 จัดการเมื่อผู้ใช้ตอบกลับจาก notification
  void _onNotificationResponse(NotificationResponse response) async {
    final actionId = response.actionId;
    final payload = response.payload;
    
    debugPrint('📱 Notification response: action=$actionId, payload=$payload');

    if (actionId == null || actionId == 'open_app') {
      // เปิดแอพ
      final context = await ContextRetriever().retrieveFullContext();
      onNotificationTap?.call(
        TriggerEvent(
          type: TriggerType.morningStart,
          timestamp: DateTime.now(),
          context: context,
          quickReplyOptions: const ['พร้อมมาก!', 'ยังง่วง', 'วันนี้มีอะไร?'],
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
}


