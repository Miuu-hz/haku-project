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

  // ─── Alarm / Timer ───
  static final _alarmPattern = RegExp(
    r'ตั้งปลุก|ปลุกฉัน|ปลุกหน่อย|set alarm|wake me up',
    caseSensitive: false,
  );
  static final _timerPattern = RegExp(
    r'จับเวลา|ตั้งเวลา|นับเวลา|set timer|timer\s+\d|countdown',
    caseSensitive: false,
  );

  // ─── Ringer / Volume ───
  static final _silentPattern = RegExp(
    r'เงียบ(หน่อย|เลย|ได้เลย)?|ปิดเสียง(เรียก)?|โหมดเงียบ|silent mode|mute( phone)?',
    caseSensitive: false,
  );
  static final _vibratePattern = RegExp(
    r'โหมดสั่น|เปิดสั่น|สั่นอย่างเดียว|vibrate mode',
    caseSensitive: false,
  );
  static final _soundOnPattern = RegExp(
    r'เปิดเสียง(เรียก|โทรศัพท์)?|เอาเสียงกลับ|sound on|unmute',
    caseSensitive: false,
  );
  static final _volumeUpPattern = RegExp(
    r'เพิ่มเสียง|ดังขึ้น|เสียงดังขึ้น|volume up|louder',
    caseSensitive: false,
  );
  static final _volumeDownPattern = RegExp(
    r'ลดเสียง|เบาลง|เสียงเบาลง|volume down|quieter',
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

    // ─── Alarm ───
    if (_alarmPattern.hasMatch(msg)) {
      final time = _parseThaiTime(msg);
      if (time != null) {
        final h = time.$1;
        final m = time.$2;
        final label = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        return DeviceCommand(
          action: 'set_alarm',
          execute: () => DeviceCommandService.execute('set_alarm', params: {'hour': h, 'minute': m}),
          replyTemplate: '⏰ ตั้งปลุก $label แล้วค่ะ',
        );
      }
      // ตรวจพบว่าต้องการตั้งปลุกแต่ parse เวลาไม่ได้ → ส่งให้ LLM ถาม
    }

    // ─── Timer ───
    if (_timerPattern.hasMatch(msg)) {
      final seconds = _parseTimerSeconds(msg);
      if (seconds != null && seconds > 0) {
        final label = _formatDuration(seconds);
        return DeviceCommand(
          action: 'set_timer',
          execute: () => DeviceCommandService.execute('set_timer', params: {'seconds': seconds}),
          replyTemplate: '⏱️ จับเวลา $label แล้วค่ะ',
        );
      }
    }

    // ─── Ringer / Volume ───
    if (_silentPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'set_silent',
        execute: () => DeviceCommandService.execute('set_silent'),
        replyTemplate: '🔇 เงียบแล้วค่ะ',
        postExecuteReply: (r) {
          final note = r['note'] as String?;
          if (note != null) return '📳 เปิดสั่นแทนนะคะ (DND ยังไม่ได้อนุญาต)';
          return '🔇 เงียบแล้วค่ะ';
        },
      );
    }
    if (_vibratePattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'set_vibrate',
        execute: () => DeviceCommandService.execute('set_vibrate'),
        replyTemplate: '📳 โหมดสั่นแล้วค่ะ',
      );
    }
    if (_soundOnPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'set_sound_on',
        execute: () => DeviceCommandService.execute('set_sound_on'),
        replyTemplate: '🔔 เปิดเสียงแล้วค่ะ',
      );
    }
    if (_volumeUpPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'volume_up',
        execute: () => DeviceCommandService.execute('volume_up'),
        replyTemplate: '🔊 เพิ่มเสียงแล้วค่ะ',
      );
    }
    if (_volumeDownPattern.hasMatch(msg)) {
      return DeviceCommand(
        action: 'volume_down',
        execute: () => DeviceCommandService.execute('volume_down'),
        replyTemplate: '🔉 ลดเสียงแล้วค่ะ',
      );
    }

    return null; // ไม่ match คำสั่งใด — ส่งให้ LLM ตอบตามปกติ
  }

  // ─── Time Parsing Helpers ───────────────────────────────────────────

  /// แปลงเวลาภาษาไทย → (hour, minute) หรือ null ถ้า parse ไม่ได้
  /// รองรับ: ตี N, N โมง(เช้า/เย็น), บ่าย N, N ทุ่ม, เที่ยง, เที่ยงคืน, H:MM
  static (int, int)? _parseThaiTime(String msg) {
    // H:MM หรือ HH:MM
    final clock = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(msg);
    if (clock != null) {
      final h = int.tryParse(clock.group(1)!) ?? -1;
      final m = int.tryParse(clock.group(2)!) ?? 0;
      if (h >= 0 && h < 24 && m < 60) return (h, m);
    }

    final half = msg.contains('ครึ่ง') ? 30 : 0;

    // เที่ยงคืน = 0:00
    if (msg.contains('เที่ยงคืน')) return (0, 0);
    // เที่ยง / เที่ยงวัน = 12:00
    if (RegExp(r'เที่ยง(วัน)?(?!คืน)').hasMatch(msg)) return (12, half);

    // ตี N (1–5) = 1:00–5:00 AM
    final ti = RegExp(r'ตี\s*([1-5])').firstMatch(msg);
    if (ti != null) {
      final n = int.tryParse(ti.group(1)!) ?? 0;
      return (n, half);
    }

    // N ทุ่ม (1–6) = 19:00–24:00 → mod 24
    final thum = RegExp(r'([1-6])\s*ทุ่ม').firstMatch(msg);
    if (thum != null) {
      final n = int.tryParse(thum.group(1)!) ?? 0;
      return ((18 + n) % 24, half);
    }

    // บ่ายโมง = 13:00, บ่าย N (2–5) = 14:00–17:00
    if (msg.contains('บ่ายโมง')) return (13, half);
    final baai = RegExp(r'บ่าย\s*([2-5])').firstMatch(msg);
    if (baai != null) {
      final n = int.tryParse(baai.group(1)!) ?? 0;
      return (12 + n, half);
    }

    // N โมงเย็น/ค่ำ (5–7) = 17:00–19:00
    final eve = RegExp(r'(\d{1,2})\s*โมง(เย็น|ค่ำ)').firstMatch(msg);
    if (eve != null) {
      final n = int.tryParse(eve.group(1)!) ?? 0;
      if (n >= 5 && n <= 7) return (12 + n, half);
    }

    // N โมง(เช้า) = N:00 (1–11)
    final morn = RegExp(r'(\d{1,2})\s*โมง').firstMatch(msg);
    if (morn != null) {
      final n = int.tryParse(morn.group(1)!) ?? 0;
      if (n >= 1 && n <= 11) return (n, half);
    }

    return null;
  }

  /// แปลงข้อความเวลาเป็นจำนวนวินาที: "30 นาที", "1 ชั่วโมง 30 นาที", "5 minutes"
  static int? _parseTimerSeconds(String msg) {
    int total = 0;

    final hour = RegExp(r'(\d+)\s*ชั่วโมง').firstMatch(msg);
    if (hour != null) total += (int.tryParse(hour.group(1)!) ?? 0) * 3600;

    final min = RegExp(r'(\d+)\s*(นาที|min)').firstMatch(msg);
    if (min != null) total += (int.tryParse(min.group(1)!) ?? 0) * 60;

    final sec = RegExp(r'(\d+)\s*(วินาที|sec)').firstMatch(msg);
    if (sec != null) total += (int.tryParse(sec.group(1)!) ?? 0);

    final ehour = RegExp(r'(\d+)\s*hour').firstMatch(msg);
    if (ehour != null) total += (int.tryParse(ehour.group(1)!) ?? 0) * 3600;

    return total > 0 ? total : null;
  }

  /// แปลงวินาทีเป็น label สวยงาม: "30 นาที", "1 ชั่วโมง 30 นาที"
  static String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final parts = [
      if (h > 0) '$h ชั่วโมง',
      if (m > 0) '$m นาที',
      if (s > 0 && h == 0) '$s วินาที',
    ];
    return parts.join(' ');
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
