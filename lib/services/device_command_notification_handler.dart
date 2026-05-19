import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import 'device_command_service.dart';
import 'notification_service.dart';

/// 🔔 Device Command Notification Handler
///
/// จัดการคำสั่งที่รอการยืนยันจาก notification action buttons.
/// เมื่อผู้ใช้กด "ยืนยัน" จาก notification → execute ทันที (skip approval)
/// เพราะผู้ใช้ยืนยันแล้วจาก notification shade.
class DeviceCommandNotificationHandler {
  static final DeviceCommandNotificationHandler _instance =
      DeviceCommandNotificationHandler._internal();
  factory DeviceCommandNotificationHandler() => _instance;
  DeviceCommandNotificationHandler._internal();

  /// Queue สำหรับคำสั่งที่รอ context (กรณี app ไม่อยู่ foreground)
  final List<_PendingCommand> _pendingQueue = [];

  /// เริ่มต้น listener สำหรับ notification actions
  void initialize() {
    final ns = NotificationService();
    ns.onCommandConfirm = _handleConfirm;
    ns.onCommandDeny = _handleDeny;
    debugPrint('✅ DeviceCommandNotificationHandler initialized');
  }

  /// ✅ ผู้ใช้กด "ยืนยัน" จาก notification
  Future<void> _handleConfirm(
    String command,
    Map<String, dynamic> params,
  ) async {
    debugPrint('🔔 Notification confirm: $command | params: $params');

    final context = hakuNavigatorKey.currentContext;

    if (context != null && context.mounted) {
      // App อยู่ foreground → execute ทันที (skip approval เพราะ user ยืนยันแล้ว)
      await _execute(command, params, context);
    } else {
      // App ไม่อยู่ foreground → queue ไว้รอตอน app มา foreground
      _pendingQueue.add(_PendingCommand(command, params));
      debugPrint('⏳ Queued command for foreground: $command');
    }
  }

  /// ❌ ผู้ใช้กด "ยกเลิก" จาก notification
  void _handleDeny(String command, Map<String, dynamic> params) {
    debugPrint('🔔 Notification deny: $command');
    // ไม่ต้องทำอะไร — แค่ log
  }

  /// ▶️ Execute command พร้อม snackbar feedback
  Future<void> _execute(
    String command,
    Map<String, dynamic> params,
    BuildContext context,
  ) async {
    final result = await DeviceCommandService.execute(
      command,
      params: params,
      context: context,
      source: 'notification',
      skipApproval: true, // user ยืนยันแล้วจาก notification
    );

    if (!context.mounted) return;

    final success = result['success'] == true;
    final message = success
        ? '✅ ทำ $command แล้วค่ะ'
        : '❌ ${result['error'] ?? 'ทำไม่สำเร็จ'}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// 🔄 เรียกเมื่อ app มา foreground (เช่น in resume lifecycle)
  /// ประมวลผลคำสั่งที่ค้างอยู่ใน queue
  void processPendingQueue() {
    if (_pendingQueue.isEmpty) return;

    final context = hakuNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    final queue = List<_PendingCommand>.from(_pendingQueue);
    _pendingQueue.clear();

    for (final pending in queue) {
      debugPrint('▶️ Processing pending command: ${pending.command}');
      _execute(pending.command, pending.params, context);
    }
  }
}

class _PendingCommand {
  final String command;
  final Map<String, dynamic> params;

  _PendingCommand(this.command, this.params);
}
