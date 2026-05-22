import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Callbacks สำหรับยืนยัน/ปฏิเสธคำสั่งจาก notification
  void Function(String command, Map<String, dynamic> params)? onCommandConfirm;
  void Function(String command, Map<String, dynamic> params)? onCommandDeny;

  /// 🚀 เริ่มต้น service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Android 13+: ขอ POST_NOTIFICATIONS ที่ runtime
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }

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
      'haku_proactive_triggers', // id
      'Haku Proactive', // name
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
    final actions = event.quickReplyOptions.map((option) => AndroidNotificationAction(
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
      'haku_proactive_triggers',
      'Haku Proactive',
      channelDescription: 'การแจ้งเตือนจาก Haku AI',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.message,
      actions: actions,
      styleInformation: BigTextStyleInformation(
        event.suggestedMessage ?? 'Haku มีอะไรจะบอกคุณ',
        contentTitle: event.displayTitle,
        summaryText: 'แตะเพื่อตอบกลับ',
      ),
      visibility: NotificationVisibility.public,
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
      event.timestamp.millisecondsSinceEpoch % 100000,
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
      final context = await ContextRetriever().retrieveFullContext();

      // charging notification → ดึง ragContext ที่ background process เก็บไว้
      if (payload != null && payload.startsWith('charging:')) {
        final prefs = await SharedPreferences.getInstance();
        final ragContext = prefs.getString('pending_charging_rag_context');
        await prefs.remove('pending_charging_rag_context');

        onNotificationTap?.call(
          TriggerEvent(
            type: TriggerType.eveningSummary,
            timestamp: DateTime.now(),
            context: context,
            quickReplyOptions: const ['สรุปวันนี้', 'วันดีมาก', 'เหนื่อยหน่อย'],
            payloadJson: ragContext != null ? {'ragContext': ragContext} : null,
          ),
        );
        return;
      }

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
      return;
    }

    // Command Confirmation (Confirm/Deny)
    if (actionId == 'confirm_cmd' || actionId == 'deny_cmd') {
      if (payload != null && payload.isNotEmpty) {
        try {
          final decoded = jsonDecode(payload) as Map<String, dynamic>;
          if (decoded['type'] == 'cmd_confirm') {
            final command = decoded['command'] as String? ?? '';
            final params = Map<String, dynamic>.from(decoded['params'] as Map? ?? {});
            if (actionId == 'confirm_cmd') {
              onCommandConfirm?.call(command, params);
              debugPrint('✅ Command confirmed from notification: $command');
            } else {
              onCommandDeny?.call(command, params);
              debugPrint('❌ Command denied from notification: $command');
            }
          }
        } catch (e) {
          debugPrint('⚠️ Failed to parse command confirmation payload: $e');
        }
      }
      return;
    }
  }

  /// 🛡️ แสดง Notification ขออนุมัติคำสั่ง (Confirm/Deny)
  ///
  /// ใช้สำหรับ sensitive commands (dial_phone, send_sms, ฯลฯ)
  /// ที่ถูก trigger จาก background หรือ proactive AI
  Future<void> showCommandConfirmationNotification({
    required String command,
    required Map<String, dynamic> params,
    required String title,
    required String body,
  }) async {
    if (!_isInitialized) {
      debugPrint('⚠️ NotificationService not initialized');
      return;
    }

    final payload = jsonEncode({
      'type': 'cmd_confirm',
      'command': command,
      'params': params,
    });

    const confirmAction = AndroidNotificationAction(
      'confirm_cmd',
      'ยืนยัน',
      showsUserInterface: false,
    );
    const denyAction = AndroidNotificationAction(
      'deny_cmd',
      'ยกเลิก',
      showsUserInterface: false,
    );

    final androidDetails = AndroidNotificationDetails(
      'haku_proactive_triggers',
      'Haku Proactive',
      channelDescription: 'การแจ้งเตือนจาก Haku AI',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.message,
      actions: [confirmAction, denyAction],
      styleInformation: BigTextStyleInformation(body),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'cmd_confirm_category',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final id = DateTime.now().millisecondsSinceEpoch % 100000;

    await _notifications.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );

    debugPrint('🔔 Showed command confirmation: $command');
  }

  /// 🎭 แสดง Notification เมื่อ Preset เปลี่ยน
  Future<void> showPresetNotification({
    required String oldPresetName,
    required String newPresetName,
    required String newPresetIcon,
    String? greeting,
  }) async {
    if (!_isInitialized) {
      debugPrint('⚠️ NotificationService not initialized');
      return;
    }

    final body = greeting ?? 'Switched to $newPresetName';

    final androidDetails = AndroidNotificationDetails(
      'haku_proactive_triggers',
      'Haku Proactive',
      channelDescription: 'การแจ้งเตือนจาก Haku AI',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: true,
      enableVibration: false,
      playSound: false,
      category: AndroidNotificationCategory.event,
      styleInformation: BigTextStyleInformation(body),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final id = DateTime.now().millisecondsSinceEpoch % 100000;

    await _notifications.show(
      id,
      '$newPresetIcon $newPresetName',
      body,
      details,
      payload: 'preset:$newPresetName',
    );

    debugPrint('🔔 Showed preset notification: $newPresetName');
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


