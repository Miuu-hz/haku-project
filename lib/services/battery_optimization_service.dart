import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 🔋 Battery Optimization Service
///
/// จัดการสิทธิ์ "ไม่ให้ Android optimize battery" สำหรับ Haku
/// ระบบ Proactive ต้องทำงานในพื้นหลังได้ → ต้องขอสิทธิ์นี้
///
/// รองรับ:
/// - Xiaomi (MIUI) → Auto-start permission
/// - Samsung → ไม่ให้ put to sleep
/// - OPPO / vivo / Realme → Battery optimization whitelist
/// - Stock Android → REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
///
/// Usage:
/// ```dart
/// final status = await BatteryOptimizationService().checkStatus();
/// if (!status.isOptimized) {
///   await BatteryOptimizationService().requestPermission();
/// }
/// ```

class BatteryOptimizationService {
  static final BatteryOptimizationService _instance =
      BatteryOptimizationService._internal();
  factory BatteryOptimizationService() => _instance;
  BatteryOptimizationService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.example.haku/battery');

  /// 📊 ตรวจสอบสถานะปัจจุบัน
  Future<BatteryOptStatus> checkStatus() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('checkStatus');
      final isIgnoring = result?['isIgnoringBatteryOptimizations'] as bool? ?? false;
      final canRequest = result?['canRequest'] as bool? ?? false;
      final manufacturer = result?['manufacturer'] as String? ?? 'unknown';

      return BatteryOptStatus(
        isIgnoringBatteryOptimizations: isIgnoring,
        canRequest: canRequest,
        manufacturer: manufacturer.toLowerCase(),
      );
    } catch (e) {
      developer.log('⚠️ BatteryOptimizationService.checkStatus failed: $e');
      return BatteryOptStatus.unknown();
    }
  }

  /// 🚀 ขอสิทธิ์ ignore battery optimizations (เปิด system dialog)
  ///
  /// Returns true ถ้า user กดอนุมัติ
  /// Returns false ถ้า user กดปฏิเสธ หรือไม่สามารถขอได้
  Future<bool> requestPermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      return granted ?? false;
    } catch (e) {
      developer.log('⚠️ BatteryOptimizationService.requestPermission failed: $e');
      return false;
    }
  }

  /// ⚙️ เปิด Settings ให้ user ตั้งค่าเอง (fallback ถ้าขอสิทธิ์ไม่ได้)
  Future<void> openBatterySettings() async {
    try {
      await _channel.invokeMethod('openBatterySettings');
    } catch (e) {
      developer.log('⚠️ openBatterySettings failed: $e');
    }
  }

  /// 🎯 ขอสิทธิ์แบบครบวงจร:
  /// 1. ตรวจสอบสถานะ
  /// 2. ถ้ายังไม่ได้ → เปิด dialog อธิบาย → ขอสิทธิ์
  ///
  /// [context] ใช้แสดง dialog อธิบาย
  /// Returns true ถ้าได้รับสิทธิ์ (หรือไม่ต้องการ)
  Future<bool> ensurePermission(BuildContext context) async {
    final status = await checkStatus();

    // ได้รับสิทธิ์แล้ว
    if (status.isIgnoringBatteryOptimizations) return true;

    // ไม่สามารถขอได้ (เช่น API < 23 หรือ OS ไม่รองรับ)
    if (!status.canRequest) {
      // บางรุ่น (Xiaomi, OPPO) ต้องไปตั้งค่าเอง
      if (status.needsManufacturerSettings && context.mounted) {
        final goSettings = await _showManufacturerDialog(context, status.manufacturer);
        if (goSettings) await openBatterySettings();
      }
      return false;
    }

    // ขอสิทธิ์ผ่าน system dialog
    if (!context.mounted) return false;
    final explain = await _showExplainDialog(context);
    if (!explain) return false;

    final granted = await requestPermission();

    if (!granted && context.mounted) {
      // User ปฏิเสธ → เสนอให้ไป Settings เอง
      final goSettings = await _showDeniedDialog(context);
      if (goSettings) await openBatterySettings();
    }

    return granted;
  }

  // ============================================================
  // 🎨 DIALOGS
  // ============================================================

  Future<bool> _showExplainDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🔋 อนุญาตให้ทำงานในพื้นหลัง'),
        content: const Text(
          'Haku ต้องทำงานเบื้องหลังเพื่อ:\n'
          '• แจ้งเตือนตอนเช้า / เย็น\n'
          '• สรุปข้อมูลตอนชาร์จ\n'
          '• จดจำสถานที่ที่คุณไปบ่อย\n\n'
          'กรุณากด "อนุญาต" ในหน้าถัดไป เพื่อไม่ให้ระบบปิด Haku',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('อนุญาต'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _showDeniedDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ ระบบอาจปิด Haku'),
        content: const Text(
          'หากไม่อนุญาต ระบบอาจปิด Haku โดยอัตโนมัติ\n'
          'ทำให้ไม่ได้รับการแจ้งเตือน\n\n'
          'ต้องการไปตั้งค่าเองไหม?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ไม่เป็นไร'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ไปตั้งค่า'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _showManufacturerDialog(BuildContext context, String brand) async {
    final guide = _getManufacturerGuide(brand);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('🔧 ตั้งค่าสำหรับ $brand'),
        content: Text(guide),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ภายหลัง'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ไปตั้งค่า'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _getManufacturerGuide(String brand) {
    switch (brand) {
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        return '1. เปิด Settings → Apps → Haku\n'
            '2. แตะ "Battery saver" → เลือก "No restrictions"\n'
            '3. กลับมาที่ App info → แตะ "Auto-start" → เปิด\n'
            '4. แตะ "Other permissions" → เปิด "Start in background"';
      case 'samsung':
        return '1. เปิด Settings → Battery → Background usage limits\n'
            '2. แตะ "Never sleeping apps" → เพิ่ม Haku\n'
            '3. หรือ Settings → Apps → Haku → Battery → Unrestricted';
      case 'oppo':
      case 'realme':
      case 'oneplus':
        return '1. เปิด Settings → Battery → App battery management\n'
            '2. หา Haku → เลือก "Don\'t optimize"\n'
            '3. หรือ Settings → Apps → Haku → Battery usage → Allow background activity';
      case 'vivo':
        return '1. เปิด Settings → Battery → Background power consumption management\n'
            '2. หา Haku → เลือก "Allow background power consumption"';
      case 'huawei':
      case 'honor':
        return '1. เปิด Settings → Battery → App launch\n'
            '2. หา Haku → ปิด "Manage automatically"\n'
            '3. เปิด "Auto-launch", "Secondary launch", "Run in background"';
      default:
        return '1. เปิด Settings → Apps → Haku\n'
            '2. แตะ Battery → เลือก "Unrestricted" หรือ "Don\'t optimize"';
    }
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

class BatteryOptStatus {
  final bool isIgnoringBatteryOptimizations;
  final bool canRequest;
  final String manufacturer;

  const BatteryOptStatus({
    required this.isIgnoringBatteryOptimizations,
    required this.canRequest,
    required this.manufacturer,
  });

  factory BatteryOptStatus.unknown() => const BatteryOptStatus(
        isIgnoringBatteryOptimizations: false,
        canRequest: false,
        manufacturer: 'unknown',
      );

  /// ต้องตั้งค่าเองตามยี่ห้อมือถือ
  bool get needsManufacturerSettings => !canRequest && _isChineseOEM;

  bool get _isChineseOEM {
    final list = ['xiaomi', 'redmi', 'poco', 'oppo', 'realme', 'oneplus', 'vivo', 'huawei', 'honor'];
    return list.contains(manufacturer);
  }
}
