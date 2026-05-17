import 'device_command_service.dart';

/// 🎯 DeviceCommandIntentDetector
///
/// ตรวจจับ intent เกี่ยวกับการสั่งงาน smartphone จากข้อความผู้ใช้
/// ใช้ rule-based matching (ไม่ต้องรอ LLM) เพื่อความเร็วและความแม่นยำบนโมเดลเล็ก
///
/// แนวคิด: ถ้าผู้ใช้พิมพ์คำสั่งชัดเจน → execute ทันที ไม่ต้องถาม LLM
/// ถ้าไม่ชัดเจน → ส่งให้ LLM ตอบตามปกติ
class DeviceCommandIntentDetector {
  // ─── Flashlight ───
  static final _flashlightOnPattern = RegExp(
    r'เปิดไฟฉาย|เปิดแฟลช|เปิดไฟ|flashlight on|turn on flash',
    caseSensitive: false,
  );
  static final _flashlightOffPattern = RegExp(
    r'ปิดไฟฉาย|ปิดแฟลช|ปิดไฟ|flashlight off|turn off flash',
    caseSensitive: false,
  );
  static final _flashlightTogglePattern = RegExp(
    r'สลับไฟฉาย|สลับแฟลช|toggle flash',
    caseSensitive: false,
  );

  // ─── Phone / SMS ───
  static final _dialPattern = RegExp(
    r'โทร(หา|ไปที่|ไป)?\s*(\+?[\d\-]+)|call\s*(\+?[\d\-]+)|dial\s*(\+?[\d\-]+)',
    caseSensitive: false,
  );
  // ─── Settings ───
  static final _wifiPattern = RegExp(
    r'เปิด(หน้า|การตั้งค่า)?\s*wifi|wifi settings|ตั้งค่า wifi',
    caseSensitive: false,
  );
  static final _bluetoothPattern = RegExp(
    r'เปิด(หน้า|การตั้งค่า)?\s*บลูทูธ|bluetooth settings|ตั้งค่าบลูทูธ',
    caseSensitive: false,
  );
  static final _locationPattern = RegExp(
    r'เปิด(หน้า|การตั้งค่า)?\s*location|gps settings|ตั้งค่า gps|ตั้งค่าตำแหน่ง',
    caseSensitive: false,
  );
  static final _batteryPattern = RegExp(
    r'เปิด(หน้า|การตั้งค่า)?\s*แบต|battery settings|ตั้งค่าแบตเตอรี่',
    caseSensitive: false,
  );

  // ─── System Apps ───
  static final _cameraPattern = RegExp(
    r'เปิดกล้อง|open camera|ถ่ายรูป|take a photo',
    caseSensitive: false,
  );
  static final _galleryPattern = RegExp(
    r'เปิดแกลเลอรี่|open gallery|ดูรูป|open photos',
    caseSensitive: false,
  );
  static final _calendarPattern = RegExp(
    r'เปิดปฏิทิน|open calendar|ดูปฏิทิน',
    caseSensitive: false,
  );
  static final _clockPattern = RegExp(
    r'เปิดนาฬิกา|open clock|ดูเวลา|set alarm',
    caseSensitive: false,
  );
  static final _calculatorPattern = RegExp(
    r'เปิดเครื่องคิดเลข|open calculator|คิดเลข',
    caseSensitive: false,
  );
  static final _mapsPattern = RegExp(
    r'เปิดแผนที่|open map|นำทางไป|navigate to',
    caseSensitive: false,
  );

  // ─── Queries ───
  static final _batteryLevelPattern = RegExp(
    r'แบต(เตอรี่)?\s*(เท่าไร|เหลือเท่าไร|กี่เปอร์เซ็น)|battery level|how much battery',
    caseSensitive: false,
  );
  static final _networkPattern = RegExp(
    r'เน็ต(ติด|ใช้ได้|ไหม|เร็วไหม|ช้าไหม)|wifi(ติด|ใช้ได้|ไหม)|network status|check (network|internet|wifi)',
    caseSensitive: false,
  );

  // ─── Share / URL ───
  static final _urlPattern = RegExp(
    r'เปิด(ลิงก์|ลิงค์|เว็บ|เว็บไซต์|link)\s*(https?://\S+|www\.\S+)|https?://\S+',
    caseSensitive: false,
  );

  /// 🔍 ตรวจจับ intent จากข้อความผู้ใช้
  /// Returns: DeviceCommand? ถ้าไม่ match จะ return null
  static Future<DeviceCommand?> detect(String userMessage) async {
    final msg = userMessage.toLowerCase().trim();

    // ─── Flashlight ───
    if (_flashlightOnPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'flashlight_on',
        execute: () => DeviceCommandService.execute('flashlight_on'),
        replyTemplate: '💡 เปิดไฟฉายแล้วค่ะ',
      );
    }
    if (_flashlightOffPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'flashlight_off',
        execute: () => DeviceCommandService.execute('flashlight_off'),
        replyTemplate: '💡 ปิดไฟฉายแล้วค่ะ',
      );
    }
    if (_flashlightTogglePattern.hasMatch(msg)) {
      // Kotlin ไม่รู้สถานะ torch — ให้ Dart singleton track state แล้ว call on/off
      return DeviceCommand(
        action: 'flashlight_toggle',
        execute: () => DeviceCommandService().flashlightToggle().then((s) => {'success': s}),
        replyTemplate: '💡 สลับไฟฉายแล้วค่ะ',
      );
    }

    // ─── Camera ───
    if (_cameraPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'open_camera',
        execute: () => DeviceCommandService.execute('open_camera'),
        replyTemplate: '📷 เปิดกล้องแล้วค่ะ',
      );
    }

    // ─── Gallery ───
    if (_galleryPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'open_gallery',
        execute: () => DeviceCommandService.execute('open_gallery'),
        replyTemplate: '🖼️ เปิดแกลเลอรี่แล้วค่ะ',
      );
    }

    // ─── Calendar ───
    if (_calendarPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'open_calendar',
        execute: () => DeviceCommandService.execute('open_calendar'),
        replyTemplate: '📅 เปิดปฏิทินแล้วค่ะ',
      );
    }

    // ─── Clock ───
    if (_clockPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'open_clock',
        execute: () => DeviceCommandService.execute('open_clock'),
        replyTemplate: '⏰ เปิดนาฬิกาแล้วค่ะ',
      );
    }

    // ─── Calculator ───
    if (_calculatorPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'open_calculator',
        execute: () => DeviceCommandService.execute('open_calculator'),
        replyTemplate: '🧮 เปิดเครื่องคิดเลขแล้วค่ะ',
      );
    }

    // ─── Settings ───
    if (_wifiPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'open_wifi_settings',
        execute: () => DeviceCommandService.execute('open_wifi_settings'),
        replyTemplate: '📶 เปิดตั้งค่า WiFi แล้วค่ะ',
      );
    }
    if (_bluetoothPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'open_bluetooth_settings',
        execute: () => DeviceCommandService.execute('open_bluetooth_settings'),
        replyTemplate: '🔵 เปิดตั้งค่า Bluetooth แล้วค่ะ',
      );
    }
    if (_locationPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'open_location_settings',
        execute: () => DeviceCommandService.execute('open_location_settings'),
        replyTemplate: '📍 เปิดตั้งค่าตำแหน่งแล้วค่ะ',
      );
    }
    if (_batteryPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'open_battery_settings',
        execute: () => DeviceCommandService.execute('open_battery_settings'),
        replyTemplate: '🔋 เปิดตั้งค่าแบตเตอรี่แล้วค่ะ',
      );
    }

    // ─── Maps ───
    if (_mapsPattern.hasMatch(msg)) {
      // พยายาม extract location จากข้อความ
      final locationMatch = RegExp(r'นำทางไป\s*(.+)|navigate to\s*(.+)')
          .firstMatch(msg);
      final query = locationMatch?.group(1) ?? locationMatch?.group(2);
      return DeviceCommand(
        action: 'open_maps',
        execute: () => DeviceCommandService.execute('open_maps', params: {'query': query}),
        replyTemplate: query != null
            ? '🗺️ เปิดแผนที่ไปที่ $query แล้วค่ะ'
            : '🗺️ เปิดแผนที่แล้วค่ะ',
      );
    }

    // ─── Dial Phone ───
    final dialMatch = _dialPattern.firstMatch(userMessage);
    if (dialMatch != null) {
      final number = dialMatch.group(2) ?? dialMatch.group(3) ?? dialMatch.group(4);
      if (number != null && number.isNotEmpty) {
        return DeviceCommand(
          action: 'dial_phone',
          execute: () => DeviceCommandService.execute('dial_phone', params: {'phoneNumber': number}),
          replyTemplate: '☎️ เปิดหน้าโทร $number แล้วค่ะ',
        );
      }
    }

    // ─── Battery Level ───
    if (_batteryLevelPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'get_battery_level',
        execute: () async {
          final level = await DeviceCommandService.getBatteryLevel();
          return {'success': true, 'level': level};
        },
        replyTemplate: '', // จะถูก override หลัง execute
        postExecuteReply: (result) {
          final level = result['level'] ?? -1;
          return '🔋 แบตเตอรี่เหลือ $level% ค่ะ';
        },
      );
    }

    // ─── Network Status ───
    if (_networkPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'get_network_status',
        execute: () => DeviceCommandService.execute('get_network_status'),
        replyTemplate: '',
        postExecuteReply: (result) {
          final connected = result['connected'] == true;
          final wifi = result['wifi'] == true;
          if (connected && wifi) return '📶 เชื่อมต่อ WiFi อยู่ค่ะ';
          if (connected) return '📡 เชื่อมต่อเน็ตมือถืออยู่ค่ะ';
          return '❌ ไม่มีการเชื่อมต่ออินเทอร์เน็ตค่ะ';
        },
      );
    }

    // ─── URL ───
    final urlMatch = _urlPattern.firstMatch(userMessage);
    if (urlMatch != null) {
      final url = urlMatch.group(2) ?? '';
      if (url.isNotEmpty) {
        return DeviceCommand(
          action: 'open_url',
          execute: () => DeviceCommandService.execute('open_url', params: {'url': url}),
          replyTemplate: '🌐 เปิด $url แล้วค่ะ',
        );
      }
    }

    return null; // ไม่ match คำสั่งใด — ส่งให้ LLM ตอบตามปกติ
  }

  /// 🚀 ตรวจจับแล้ว execute ทันที พร้อม return ข้อความตอบกลับ
  static Future<DeviceCommandResult?> detectAndExecute(String userMessage) async {
    final command = await detect(userMessage);
    if (command == null) return null;

    try {
      final result = await command.execute();
      final success = result['success'] == true;

      String reply;
      if (command.postExecuteReply != null) {
        reply = command.postExecuteReply!(result);
      } else {
        reply = command.replyTemplate;
      }

      return DeviceCommandResult(
        action: command.action,
        success: success,
        reply: reply,
        rawResult: result,
      );
    } catch (e) {
      return DeviceCommandResult(
        action: command.action,
        success: false,
        reply: '❌ ทำไม่สำเร็จค่ะ: $e',
        rawResult: {},
      );
    }
  }
}

/// 📦 Data class สำหรับคำสั่งที่ตรวจจับได้
class DeviceCommand {
  final String action;
  final Future<Map<String, dynamic>> Function() execute;
  final String replyTemplate;
  final String Function(Map<String, dynamic> result)? postExecuteReply;

  DeviceCommand({
    required this.action,
    required this.execute,
    required this.replyTemplate,
    this.postExecuteReply,
  });
}

/// 📦 Data class สำหรับผลลัพธ์หลัง execute
class DeviceCommandResult {
  final String action;
  final bool success;
  final String reply;
  final Map<String, dynamic> rawResult;

  DeviceCommandResult({
    required this.action,
    required this.success,
    required this.reply,
    required this.rawResult,
  });

  Map<String, dynamic> toJson() => {
        'action': action,
        'success': success,
        'reply': reply,
        'rawResult': rawResult,
      };
}
