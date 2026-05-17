import 'dart:convert';
import 'package:flutter/services.dart';

/// 🔧 DeviceCommandService
///
/// Flutter-side bridge สำหรับสั่งงาน smartphone ผ่าน MethodChannel
/// ไปยัง Android Native (DeviceCommandHandler.kt)
///
/// Channel: com.example.haku/device
///
/// แรงบันดาลใจจาก Google AI Edge Gallery — AgentTools.runIntent()
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
  ///
  /// Returns: Map ที่มี 'success' (bool) และอาจมี 'error', 'level', 'state' ฯลฯ
  static Future<Map<String, dynamic>> execute(
    String command, {
    Map<String, dynamic> params = const {},
  }) async {
    try {
      final result = await _channel.invokeMethod('execute', {
        'command': command,
        'params': Map<dynamic, dynamic>.from(params),
      });
      return Map<String, dynamic>.from((result as Map<dynamic, dynamic>?) ?? {'success': false});
    } on PlatformException catch (e) {
      return {
        'success': false,
        'error': e.message ?? 'Platform error',
        'code': e.code,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Flashlight
  // ═══════════════════════════════════════════════════════════════════

  Future<bool> flashlightOn() async {
    final r = await execute('flashlight_on');
    if (r['success'] == true) _flashlightOn = true;
    return (r['success'] as bool?) ?? false;
  }

  Future<bool> flashlightOff() async {
    final r = await execute('flashlight_off');
    if (r['success'] == true) _flashlightOn = false;
    return (r['success'] as bool?) ?? false;
  }

  Future<bool> flashlightToggle() async {
    return _flashlightOn ? await flashlightOff() : await flashlightOn();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  App / Communication
  // ═══════════════════════════════════════════════════════════════════

  static Future<bool> openApp(String packageName) async {
    final r = await execute('open_app', params: {'packageName': packageName});
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> dialPhone(String number) async {
    final r = await execute('dial_phone', params: {'phoneNumber': number});
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> sendSms(String number, String message) async {
    final r = await execute('send_sms', params: {
      'phoneNumber': number,
      'message': message,
    });
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> sendEmail({
    required String to,
    String subject = '',
    String body = '',
  }) async {
    final r = await execute('send_email', params: {
      'to': to,
      'subject': subject,
      'body': body,
    });
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openUrl(String url) async {
    final r = await execute('open_url', params: {'url': url});
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openCamera() async {
    final r = await execute('open_camera');
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openGallery() async {
    final r = await execute('open_gallery');
    return (r['success'] as bool?) ?? false;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Settings
  // ═══════════════════════════════════════════════════════════════════

  static Future<bool> openSettings(String type) async {
    final r = await execute('open_settings', params: {'type': type});
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openWifiSettings() => openSettings('wifi');
  static Future<bool> openBluetoothSettings() => openSettings('bluetooth');
  static Future<bool> openLocationSettings() => openSettings('location');
  static Future<bool> openBatterySettings() => openSettings('battery');
  static Future<bool> openSoundSettings() => openSettings('sound');
  static Future<bool> openDisplaySettings() => openSettings('display');
  static Future<bool> openSecuritySettings() => openSettings('security');

  // ═══════════════════════════════════════════════════════════════════
  //  System Apps
  // ═══════════════════════════════════════════════════════════════════

  static Future<bool> openCalendar() async {
    final r = await execute('open_calendar');
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openClock() async {
    final r = await execute('open_clock');
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openCalculator() async {
    final r = await execute('open_calculator');
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> openMaps({String? query, double? lat, double? lng}) async {
    final params = <String, dynamic>{};
    if (query != null) params['query'] = query;
    if (lat != null) params['lat'] = lat;
    if (lng != null) params['lng'] = lng;
    final r = await execute('open_maps', params: params);
    return (r['success'] as bool?) ?? false;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Share / Contact
  // ═══════════════════════════════════════════════════════════════════

  static Future<bool> shareText(String text) async {
    final r = await execute('share_text', params: {'text': text});
    return (r['success'] as bool?) ?? false;
  }

  static Future<bool> createContact({
    String? name,
    String? phone,
    String? email,
  }) async {
    final r = await execute('create_contact', params: {
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
    });
    return (r['success'] as bool?) ?? false;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Queries
  // ═══════════════════════════════════════════════════════════════════

  static Future<int> getBatteryLevel() async {
    final r = await execute('get_battery_level');
    return (r['level'] as num?)?.toInt() ?? -1;
  }

  static Future<Map<String, dynamic>> getNetworkStatus() async {
    final r = await execute('get_network_status');
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
  static Future<Map<String, dynamic>> executeFromLlmJson(String jsonString) async {
    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final command = decoded['command'] as String?;
      final params = Map<String, dynamic>.from(decoded['params'] as Map? ?? {});

      if (command == null || command.isEmpty) {
        return {'success': false, 'error': 'Missing command in LLM JSON'};
      }

      final result = await execute(command, params: params);
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
