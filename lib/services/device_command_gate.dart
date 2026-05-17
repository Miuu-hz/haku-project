import 'package:flutter/material.dart';

/// 🛡️ DeviceCommandGate — 4 ระดับความปลอดภัยสำหรับคำสั่ง smartphone
///
/// แบ่งคำสั่งตามความ sensitive ก่อนส่งไป DeviceCommandService.execute()
///
/// | Tier | พฤติกรรม | ตัวอย่าง |
/// |------|----------|----------|
/// | 🟢 Auto | ทำทันที ไม่ต้องถาม | ไฟฉาย, settings |
/// | 🟡 Notify | ทำทันที แต่แจ้งเตือนทีหลัง | กล้อง, แกลเลอรี่ |
/// | 🔴 Confirm | ขึ้นป๊อปอัพให้กดยืนยัน | โทร, SMS, อีเมล |
/// | 🔒 Biometric | ต้องสแกนใบหน้า/ลายนิ้วมือ | ล็อกเครื่อง, ล้างข้อมูล |
enum CommandTier { auto, notify, confirm, biometric }

class DeviceCommandGate {
  static final DeviceCommandGate instance = DeviceCommandGate._internal();
  DeviceCommandGate._internal();

  // ─── Tier Mapping ───

  /// ดูระดับความปลอดภัยของคำสั่ง
  static CommandTier getTier(String command) {
    if (_autoCommands.contains(command)) return CommandTier.auto;
    if (_notifyCommands.contains(command)) return CommandTier.notify;
    if (_confirmCommands.contains(command)) return CommandTier.confirm;
    if (_biometricCommands.contains(command)) return CommandTier.biometric;
    return CommandTier.auto; // default
  }

  /// เช็คว่าคำสั่งต้องขออนุมัติหรือไม่ (confirm / biometric)
  static bool requiresApproval(String command) {
    final tier = getTier(command);
    return tier == CommandTier.confirm || tier == CommandTier.biometric;
  }

  /// 🎨 ชื่อ tier ภาษาไทย
  static String tierLabel(CommandTier tier) {
    switch (tier) {
      case CommandTier.auto:
        return 'อัตโนมัติ';
      case CommandTier.notify:
        return 'แจ้งเตือน';
      case CommandTier.confirm:
        return 'ต้องยืนยัน';
      case CommandTier.biometric:
        return 'ต้องยืนยันตัวตน';
    }
  }

  static String tierLabelFromString(String tier) {
    switch (tier) {
      case 'auto':
        return 'อัตโนมัติ';
      case 'notify':
        return 'แจ้งเตือน';
      case 'confirm':
        return 'ต้องยืนยัน';
      case 'biometric':
        return 'ต้องยืนยันตัวตน';
      default:
        return 'อัตโนมัติ';
    }
  }

  // ─── Command Lists ───

  static const Set<String> _autoCommands = {
    'flashlight_on',
    'flashlight_off',
    'flashlight_toggle',
    'open_settings',
    'open_wifi_settings',
    'open_bluetooth_settings',
    'open_location_settings',
    'open_battery_settings',
    'open_sound_settings',
    'open_display_settings',
    'open_security_settings',
    'open_developer_settings',
    'open_calendar',
    'open_clock',
    'open_calculator',
    'open_maps',
    'get_battery_level',
    'get_network_status',
    'set_silent',
    'set_vibrate',
    'set_sound_on',
    'volume_up',
    'volume_down',
    'set_alarm',
    'set_timer',
  };

  static const Set<String> _notifyCommands = {
    'open_app',
    'open_camera',
    'open_gallery',
    'open_url',
    'share_text',
  };

  static const Set<String> _confirmCommands = {
    'dial_phone',
    'send_sms',
    'send_email',
    'create_contact',
  };

  static const Set<String> _biometricCommands = {
    // ยังไม่มี command ในระดับนี้ — สำรองไว้สำหรับ future
    // 'device_lock',
    // 'wipe_data',
    // 'uninstall_app',
  };

  // ─── Approval Flow ───

  /// ขออนุมัติจากผู้ใช้ (สำหรับ Confirm tier)
  ///
  /// คืน true = ผู้ใช้กดยืนยัน, false = ยกเลิก
  static Future<bool> requestConfirm(BuildContext context, {
    required String command,
    required String title,
    String? details,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2B4D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: details != null
            ? Text(
                details,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15),
              )
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'ยกเลิก',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3CDFFF),
              foregroundColor: const Color(0xFF0A1F4D),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('ยืนยัน', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// ขออนุมัติด้วย Biometric (สำหรับ Biometric tier)
  ///
  /// คืน true = ยืนยันตัวตนสำเร็จ, false = ล้มเหลว/ยกเลิก
  static Future<bool> requestBiometric(BuildContext context, {
    required String reason,
  }) async {
    // placeholder — implement จริงเมื่อมี biometric-tier command
    return false;
  }

  /// 📋 สรุปคำสั่งเป็น string อ่านง่าย (สำหรับแสดงใน dialog)
  static String summarizeCommand(String command, Map<String, dynamic> params) {
    switch (command) {
      case 'dial_phone':
        final number = params['phoneNumber'] ?? 'ไม่ระบุ';
        return 'โทรหา $number';
      case 'send_sms':
        final number = params['phoneNumber'] ?? 'ไม่ระบุ';
        return 'ส่ง SMS ไป $number';
      case 'send_email':
        final to = params['to'] ?? 'ไม่ระบุ';
        return 'ส่งอีเมลไป $to';
      case 'create_contact':
        final name = params['name'] ?? 'ไม่ระบุชื่อ';
        return 'สร้างผู้ติดต่อ: $name';
      default:
        return command;
    }
  }
}
