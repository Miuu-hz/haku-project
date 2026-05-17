import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'database_helper.dart';

/// 📋 DeviceCommandAudit — บันทึกประวัติทุกคำสั่งที่ Haku สั่ง smartphone
///
/// เก็บใน SQLite + SQLCipher (เข้ารหัส) — auto ลบหลัง 30 วัน
///
/// ใช้ร่วมกับ DeviceCommandGate (ระดับความปลอดภัย)
class DeviceCommandAudit {
  static final DeviceCommandAudit instance = DeviceCommandAudit._internal();
  DeviceCommandAudit._internal();

  static const String _table = 'device_command_log';

  /// ➕ บันทึกคำสั่งลง Audit Log
  ///
  /// [command] — ชื่อคำสั่ง เช่น 'flashlight_on', 'dial_phone'
  /// [params] — parameters ที่ส่งไป
  /// [success] — ผลลัพธ์สำเร็จหรือไม่
  /// [error] — ข้อความ error (ถ้ามี)
  /// [source] — ใครสั่ง: 'user_chat', 'proactive_trigger', 'llm_tool', 'automation'
  /// [tier] — ระดับความปลอดภัย: 'auto', 'notify', 'confirm', 'biometric'
  Future<void> logEntry({
    required String command,
    Map<String, dynamic>? params,
    required bool success,
    String? error,
    String source = 'user_chat',
    String tier = 'auto',
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.insert(_table, {
        'timestamp': DateTime.now().toIso8601String(),
        'command': command,
        'params': params != null ? jsonEncode(params) : '{}',
        'success': success ? 1 : 0,
        'error': error,
        'source': source,
        'tier': tier,
      });
    } catch (e) {
      debugPrint('⚠️ DeviceCommandAudit.logEntry error: $e');
    }
  }

  /// 📚 ดึงประวัติล่าสุด N รายการ
  Future<List<AuditLogEntry>> getRecentLogs({int limit = 50, int offset = 0}) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query(
        _table,
        orderBy: 'timestamp DESC',
        limit: limit,
        offset: offset,
      );
      return maps.map((m) => AuditLogEntry.fromMap(m)).toList();
    } catch (e) {
      debugPrint('⚠️ DeviceCommandAudit.getRecentLogs error: $e');
      return [];
    }
  }

  /// 📅 ดึงประวัติตามวัน (YYYY-MM-DD)
  Future<List<AuditLogEntry>> getLogsByDate(String dateString) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query(
        _table,
        where: 'timestamp LIKE ?',
        whereArgs: ['$dateString%'],
        orderBy: 'timestamp DESC',
      );
      return maps.map((m) => AuditLogEntry.fromMap(m)).toList();
    } catch (e) {
      debugPrint('⚠️ DeviceCommandAudit.getLogsByDate error: $e');
      return [];
    }
  }

  /// 📊 นัดจำนวน log entries
  Future<int> getLogCount() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.rawQuery('SELECT COUNT(*) FROM $_table');
      return (result.first.values.first as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// 🗑️ ลบ log เก่ากว่า N วัน
  Future<int> pruneOldLogs({int olderThanDays = 30}) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final cutoff = DateTime.now()
          .subtract(Duration(days: olderThanDays))
          .toIso8601String();
      return db.delete(
        _table,
        where: 'timestamp < ?',
        whereArgs: [cutoff],
      );
    } catch (e) {
      debugPrint('⚠️ DeviceCommandAudit.pruneOldLogs error: $e');
      return 0;
    }
  }

  /// 🔥 ลบทั้งหมด (ใช้ระวัง!)
  Future<int> clearAll() async {
    try {
      final db = await DatabaseHelper.instance.database;
      return db.delete(_table);
    } catch (e) {
      debugPrint('⚠️ DeviceCommandAudit.clearAll error: $e');
      return 0;
    }
  }
}

/// 📦 Model สำหรับ Audit Log Entry
class AuditLogEntry {
  final int? id;
  final DateTime timestamp;
  final String command;
  final Map<String, dynamic> params;
  final bool success;
  final String? error;
  final String source;
  final String tier;

  AuditLogEntry({
    this.id,
    required this.timestamp,
    required this.command,
    required this.params,
    required this.success,
    this.error,
    required this.source,
    required this.tier,
  });

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      command: map['command'] as String,
      params: _parseParams(map['params']),
      success: (map['success'] as int) == 1,
      error: map['error'] as String?,
      source: map['source'] as String? ?? 'user_chat',
      tier: map['tier'] as String? ?? 'auto',
    );
  }

  static Map<String, dynamic> _parseParams(dynamic raw) {
    if (raw == null) return {};
    if (raw is String) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return {'value': raw};
      }
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  /// 🕐 แสดงเวลาแบบ HH:MM
  String get timeFormatted {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 📅 แสดงวันที่แบบ วัน/เดือน/ปี
  String get dateFormatted {
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }

  /// 🏷️ ชื่อคำสั่งแบบอ่านง่าย
  String get commandDisplayName {
    return _commandNames[command] ?? command;
  }

  /// 🎨 สี tier สำหรับ UI
  String get tierEmoji {
    switch (tier) {
      case 'auto':
        return '🟢';
      case 'notify':
        return '🟡';
      case 'confirm':
        return '🔴';
      case 'biometric':
        return '🔒';
      default:
        return '⚪';
    }
  }

  static final Map<String, String> _commandNames = {
    'flashlight_on': 'เปิดไฟฉาย',
    'flashlight_off': 'ปิดไฟฉาย',
    'flashlight_toggle': 'สลับไฟฉาย',
    'open_app': 'เปิดแอป',
    'dial_phone': 'โทรศัพท์',
    'send_sms': 'ส่ง SMS',
    'send_email': 'ส่งอีเมล',
    'open_url': 'เปิดลิงก์',
    'open_camera': 'เปิดกล้อง',
    'open_gallery': 'เปิดแกลเลอรี่',
    'open_settings': 'เปิดการตั้งค่า',
    'open_wifi_settings': 'เปิด WiFi',
    'open_bluetooth_settings': 'เปิด Bluetooth',
    'open_location_settings': 'เปิดตำแหน่ง',
    'open_battery_settings': 'เปิดแบตเตอรี่',
    'open_sound_settings': 'เปิดเสียง',
    'open_display_settings': 'เปิดหน้าจอ',
    'open_security_settings': 'เปิดความปลอดภัย',
    'open_calendar': 'เปิดปฏิทิน',
    'open_clock': 'เปิดนาฬิกา',
    'open_calculator': 'เปิดเครื่องคิดเลข',
    'open_maps': 'เปิดแผนที่',
    'share_text': 'แชร์ข้อความ',
    'create_contact': 'สร้างผู้ติดต่อ',
    'get_battery_level': 'เช็คแบต',
    'get_network_status': 'เช็คเน็ต',
    'set_silent': 'ปิดเสียง',
    'set_vibrate': 'สั่น',
    'set_sound_on': 'เปิดเสียง',
    'volume_up': 'เพิ่มเสียง',
    'volume_down': 'ลดเสียง',
    'set_alarm': 'ตั้งปลุก',
    'set_timer': 'ตั้งจับเวลา',
  };
}
