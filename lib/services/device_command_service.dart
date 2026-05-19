import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_command_audit.dart';
import 'device_command_gate.dart';

/// 🔧 DeviceCommandService
///
/// Flutter-side bridge สำหรับสั่งงาน smartphone ผ่าน MethodChannel
/// ไปยัง Android Native (DeviceCommandHandler.kt)
///
/// Channel: com.example.haku/device
///
/// แรงบันดาลใจจาก Google AI Edge Gallery — AgentTools.runIntent()
///
/// 🆕 รองรับ Audit Log + Permission Gate (4-tier security)
class DeviceCommandService {
  static const MethodChannel _channel =
      MethodChannel('com.example.haku/device');

  // singleton เพื่อให้ _flashlightOn state ไม่ reset ระหว่าง instance
  DeviceCommandService._();
  static final DeviceCommandService instance = DeviceCommandService._();
  factory DeviceCommandService() => instance;

  // ─── State Tracking ───
  bool _flashlightOn = false;

  bool get isFlashlightOn => _flashlightOn;

  /// 🎛️ Universal execute — รันคำสั่งทั้งหมดผ่านทางนี้
  ///
  /// [command] คือ command string เช่น 'flashlight_on', 'open_app', 'dial_phone'
  /// [params] คือ Map ของ parameters ที่จำเป็นต่อ command นั้น
  /// [context] — ถ้ามี จะแสดง confirm dialog สำหรับ command ระดับ confirm/biometric
  /// [source] — แหล่งที่มาของคำสั่ง: 'user_chat', 'proactive_trigger', 'llm_tool', 'automation'
  ///
  /// Returns: Map ที่มี 'success' (bool) และอาจมี 'error', 'level', 'state' ฯลฯ
  static Future<Map<String, dynamic>> execute(
    String command, {
    Map<String, dynamic> params = const {},
    BuildContext? context,
    String source = 'user_chat',
    bool skipApproval = false,
  }) async {
    final tier = DeviceCommandGate.getTier(command);
    final tierName = tier.name;

    // ─── Permission Gate ───
    if (DeviceCommandGate.requiresApproval(command) && !skipApproval) {
      // คำสั่ง sensitive ต้องมี UI context เสมอ — ไม่มี context = block ทันที
      if (context == null) {
        await DeviceCommandAudit.instance.logEntry(
          command: command,
          params: params,
          success: false,
          error: 'Blocked: no UI context for approval',
          source: source,
          tier: tierName,
        );
        return {
          'success': false,
          'error': 'Command "$command" requires user confirmation but no UI context was provided',
          'tier': tierName,
        };
      }
      final approved = await DeviceCommandGate.requestConfirm(
        context,
        command: command,
        title: 'ยืนยันคำสั่ง',
        details: DeviceCommandGate.summarizeCommand(command, params),
      );
      if (!approved) {
        // ผู้ใช้ปฏิเสธ — log ว่าถูกปฏิเสธแล้วคืนค่า
        await DeviceCommandAudit.instance.logEntry(
          command: command,
          params: params,
          success: false,
          error: 'ผู้ใช้ปฏิเสธคำสั่ง',
          source: source,
          tier: tierName,
        );
        return {'success': false, 'error': 'User declined', 'tier': tierName};
      }
    }

    // ─── Execute via MethodChannel ───
    Map<String, dynamic> result;
    try {
      final rawResult = await _channel.invokeMethod('execute', {
        'command': command,
        'params': Map<dynamic, dynamic>.from(params),
      });
      result = Map<String, dynamic>.from(
        (rawResult as Map<dynamic, dynamic>?) ?? {'success': false},
      );
    } on PlatformException catch (e) {
      result = {
        'success': false,
        'error': e.message ?? 'Platform error',
        'code': e.code,
      };
    } catch (e) {
      result = {'success': false, 'error': e.toString()};
    }

    // ─── Auto Audit Log ───
    await DeviceCommandAudit.instance.logEntry(
      command: command,
      params: params,
      success: result['success'] == true,
      error: result['error'] as String?,
      source: source,
      tier: tierName,
    );

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Flashlight
  // ═══════════════════════════════════════════════════════════════════

  Future<bool> flashlightOn({BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('flashlight_on', context: context, source: source);
    if (r['success'] == true) _flashlightOn = true;
    return (r['success'] as bool?) ?? false;
  }

  Future<bool> flashlightOff({BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('flashlight_off', context: context, source: source);
    if (r['success'] == true) _flashlightOn = false;
    return (r['success'] as bool?) ?? false;
  }

  Future<bool> flashlightToggle({BuildContext? context, String source = 'user_chat'}) async {
    return _flashlightOn
        ? await flashlightOff(context: context, source: source)
        : await flashlightOn(context: context, source: source);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  App / Communication
  // ═══════════════════════════════════════════════════════════════════

  static Future<bool> openApp(String packageName, {BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('open_app', params: {'packageName': packageName}, context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> dialPhone(String number, {BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('dial_phone', params: {'phoneNumber': number}, context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> sendSms(String number, String message, {BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('send_sms', params: {
      'phoneNumber': number,
      'message': message,
    }, context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> sendEmail({
    required String to,
    String subject = '',
    String body = '',
    BuildContext? context,
    String source = 'user_chat',
  }) async {
    final r = await execute('send_email', params: {
      'to': to,
      'subject': subject,
      'body': body,
    }, context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openUrl(String url, {BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('open_url', params: {'url': url}, context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openCamera({BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('open_camera', context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openGallery({BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('open_gallery', context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Settings
  // ═══════════════════════════════════════════════════════════════════

  static Future<bool> openSettings(String type, {BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('open_settings', params: {'type': type}, context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openWifiSettings({BuildContext? context, String source = 'user_chat'}) => openSettings('wifi', context: context, source: source);
  static Future<bool> openBluetoothSettings({BuildContext? context, String source = 'user_chat'}) => openSettings('bluetooth', context: context, source: source);
  static Future<bool> openLocationSettings({BuildContext? context, String source = 'user_chat'}) => openSettings('location', context: context, source: source);
  static Future<bool> openBatterySettings({BuildContext? context, String source = 'user_chat'}) => openSettings('battery', context: context, source: source);
  static Future<bool> openSoundSettings({BuildContext? context, String source = 'user_chat'}) => openSettings('sound', context: context, source: source);
  static Future<bool> openDisplaySettings({BuildContext? context, String source = 'user_chat'}) => openSettings('display', context: context, source: source);
  static Future<bool> openSecuritySettings({BuildContext? context, String source = 'user_chat'}) => openSettings('security', context: context, source: source);

  // ═══════════════════════════════════════════════════════════════════
  //  System Apps
  // ═══════════════════════════════════════════════════════════════════

  static Future<bool> openCalendar({BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('open_calendar', context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openClock({BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('open_clock', context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openCalculator({BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('open_calculator', context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openMaps({String? query, double? lat, double? lng, BuildContext? context, String source = 'user_chat'}) async {
    final params = <String, dynamic>{};
    if (query != null) params['query'] = query;
    if (lat != null) params['lat'] = lat;
    if (lng != null) params['lng'] = lng;
    final r = await execute('open_maps', params: params, context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Share / Contact
  // ═══════════════════════════════════════════════════════════════════

  static Future<bool> shareText(String text, {BuildContext? context, String source = 'user_chat'}) async {
    final r = await execute('share_text', params: {'text': text}, context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> createContact({
    String? name,
    String? phone,
    String? email,
    BuildContext? context,
    String source = 'user_chat',
  }) async {
    final r = await execute('create_contact', params: {
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
    }, context: context, source: source);
    return (r['success'] as bool?) ?? false;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Queries
  // ═══════════════════════════════════════════════════════════════════

  static Future<int> getBatteryLevel({String source = 'user_chat'}) async {
    final r = await execute('get_battery_level', source: source);
    return (r['level'] as num?)?.toInt() ?? -1;
  }

  static Future<Map<String, dynamic>> getNetworkStatus({String source = 'user_chat'}) async {
    final r = await execute('get_network_status', source: source);
    return Map<String, dynamic>.from(r);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  LLM Tool Integration
  // ═══════════════════════════════════════════════════════════════════

  /// 🧠 สำหรับให้ LLM เรียกใช้ — รับ JSON string จาก LLM แล้ว parse + execute
  ///
  /// LLM จะตอบกลับในรูปแบบ:
  /// ```json
  /// {
  ///   "command": "flashlight_on",
  ///   "params": {}
  /// }
  /// ```
  ///
  /// [context] ต้องส่งมาเสมอ — คำสั่ง confirm/biometric tier จะถูก block
  /// ถ้าไม่มี context เพื่อแสดง approval dialog
  static Future<Map<String, dynamic>> executeFromLlmJson(
    String jsonString, {
    BuildContext? context,
  }) async {
    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final command = decoded['command'] as String?;
      final params = Map<String, dynamic>.from(decoded['params'] as Map? ?? {});

      if (command == null || command.isEmpty) {
        return {'success': false, 'error': 'Missing command in LLM JSON'};
      }

      // ป้องกัน LLM bypass approval gate:
      // คำสั่ง confirm/biometric tier ต้องมี context สำหรับแสดง dialog
      // ถ้าไม่มี context → block ทันที ไม่ execute
      if (DeviceCommandGate.requiresApproval(command) && context == null) {
        return {
          'success': false,
          'error': 'Command "$command" requires user confirmation but no UI context was provided',
          'tier': DeviceCommandGate.getTier(command).name,
        };
      }

      final result = await execute(command, params: params, context: context, source: 'llm_tool');
      return result;
    } catch (e) {
      return {'success': false, 'error': 'Failed to parse LLM JSON: $e'};
    }
  }

  /// 📋 JSON Schema สำหรับใส่ใน System Prompt ให้ LLM รู้จัก tool นี้
  static Map<String, dynamic> get toolSchema => {
        'name': 'run_device_command',
        'description':
            'Run a smartphone command such as toggle flashlight, open app, dial phone, send SMS, open settings, check battery, etc.',
        'parameters': {
          'type': 'object',
          'properties': {
            'command': {
              'type': 'string',
              'enum': [
                'flashlight_on',
                'flashlight_off',
                'open_app',
                'dial_phone',
                'send_sms',
                'send_email',
                'open_url',
                'open_camera',
                'open_gallery',
                'open_wifi_settings',
                'open_bluetooth_settings',
                'open_location_settings',
                'open_battery_settings',
                'open_calendar',
                'open_clock',
                'open_calculator',
                'open_maps',
                'share_text',
                'create_contact',
                'get_battery_level',
                'get_network_status',
              ],
              'description': 'The command to execute',
            },
            'params': {
              'type': 'object',
              'description': 'Command-specific parameters as key-value pairs',
            },
          },
          'required': ['command'],
        },
      };
}
