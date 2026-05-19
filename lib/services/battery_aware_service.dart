import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

/// 🔋 Battery Aware Service - ตรวจสอบสถานะแบตและชาร์จ
///
/// ใช้สำหรับ:
/// - Defer งานหนักไปทำตอนชาร์จ
/// - ปรับ behavior ตามระดับแบต
/// - ทำ background tasks เมื่อชาร์จ

class BatteryAwareService {
  static final BatteryAwareService _instance = BatteryAwareService._internal();
  factory BatteryAwareService() => _instance;
  BatteryAwareService._internal();

  final Battery _battery = Battery();

  // สถานะปัจจุบัน
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.unknown;
  bool _isInitialized = false;

  // Streams
  StreamSubscription<BatteryState>? _stateSubscription;

  // Callbacks
  void Function()? onChargingStarted;
  void Function()? onChargingStopped;
  void Function(int level)? onBatteryLow;

  // Getters
  int get batteryLevel => _batteryLevel;
  bool get isCharging => _batteryState == BatteryState.charging;
  bool get isFull => _batteryState == BatteryState.full;
  bool get isChargingOrFull => isCharging || isFull;
  bool get isLowBattery => _batteryLevel < 20;
  bool get isCriticalBattery => _batteryLevel < 10;

  /// 🚀 เริ่มต้น service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // ดึงระดับแบตปัจจุบัน
      _batteryLevel = await _battery.batteryLevel;

      // ดึงสถานะการชาร์จ
      _batteryState = await _battery.batteryState;

      // Listen การเปลี่ยนแปลงสถานะ
      _stateSubscription = _battery.onBatteryStateChanged.listen((state) {
        final wasCharging = isChargingOrFull;
        _batteryState = state;

        // เริ่มชาร์จ
        if (!wasCharging && isChargingOrFull) {
          debugPrint('🔌 เริ่มชาร์จ - พร้อมทำ deferred tasks');
          onChargingStarted?.call();
        }
        // หยุดชาร์จ
        else if (wasCharging && !isChargingOrFull) {
          debugPrint('🔋 หยุดชาร์จ - หยุด heavy tasks');
          onChargingStopped?.call();
        }
      });

      // อัปเดตระดับแบตเป็นระยะ (ทุก 5 นาที)
      Timer.periodic(const Duration(minutes: 5), (_) async {
        _batteryLevel = await _battery.batteryLevel;

        if (_batteryLevel < 20) {
          onBatteryLow?.call(_batteryLevel);
        }
      });

      _isInitialized = true;
      debugPrint('✅ Battery Aware Service initialized');
      debugPrint('   - Level: $_batteryLevel%');
      debugPrint('   - State: ${_batteryState.name}');
    } catch (e) {
      debugPrint('⚠️ Battery service init failed: $e');
      // ถ้าไม่ได้ ก็ assume ว่าไม่ได้ชาร์จ
      _batteryLevel = 50;
      _batteryState = BatteryState.discharging;
    }
  }

  /// 🔍 ตรวจสอบว่าควรทำ heavy task หรือไม่
  ///
  /// Returns true ถ้า:
  /// - กำลังชาร์จ หรือ
  /// - แบตเยอะพอ (> 50%)
  bool shouldRunHeavyTask() {
    if (isChargingOrFull) return true;
    if (_batteryLevel > 50) return true;
    return false;
  }

  /// 🔍 ตรวจสอบว่าควรทำ background task หรือไม่
  ///
  /// Returns true ถ้า:
  /// - กำลังชาร์จ และแบต > 20%
  bool shouldRunBackgroundTask() {
    if (!isChargingOrFull) return false;
    if (_batteryLevel < 20) return false;
    return true;
  }

  /// 📊 ดึง Energy Profile ที่แนะนำ
  EnergyProfile getRecommendedProfile() {
    if (isCriticalBattery) return EnergyProfile.ultraSaver;
    if (isLowBattery) return EnergyProfile.batterySaver;
    if (isChargingOrFull) return EnergyProfile.performance;
    return EnergyProfile.balanced;
  }

  /// 🧹 Dispose
  void dispose() {
    _stateSubscription?.cancel();
    _isInitialized = false;
  }
}

/// ⚡ Energy Profile - ระดับการประหยัดพลังงาน
enum EnergyProfile {
  /// ประหยัดสุดๆ (แบต < 10%)
  ultraSaver,

  /// ประหยัด (แบต < 20%)
  batterySaver,

  /// สมดุล (ปกติ)
  balanced,

  /// เต็มประสิทธิภาพ (กำลังชาร์จ)
  performance,
}

extension EnergyProfileExtension on EnergyProfile {
  /// Interval สำหรับ time-based triggers (นาที)
  int get triggerIntervalMinutes {
    switch (this) {
      case EnergyProfile.ultraSaver:
        return 30; // เช็คทุก 30 นาที
      case EnergyProfile.batterySaver:
        return 15; // เช็คทุก 15 นาที
      case EnergyProfile.balanced:
        return 5; // เช็คทุก 5 นาที
      case EnergyProfile.performance:
        return 1; // เช็คทุก 1 นาที
    }
  }

  /// เปิด location tracking หรือไม่
  bool get enableLocationTracking {
    switch (this) {
      case EnergyProfile.ultraSaver:
        return false;
      case EnergyProfile.batterySaver:
        return false; // ใช้ geofence เท่านั้น
      case EnergyProfile.balanced:
        return true; // geofence + significant change
      case EnergyProfile.performance:
        return true; // full tracking
    }
  }

  /// เปิด auto-summarize หรือไม่
  bool get enableAutoSummarize {
    switch (this) {
      case EnergyProfile.ultraSaver:
      case EnergyProfile.batterySaver:
        return false; // รอชาร์จ
      case EnergyProfile.balanced:
      case EnergyProfile.performance:
        return true;
    }
  }

  String get displayName {
    switch (this) {
      case EnergyProfile.ultraSaver:
        return 'ประหยัดสุด';
      case EnergyProfile.batterySaver:
        return 'ประหยัด';
      case EnergyProfile.balanced:
        return 'สมดุล';
      case EnergyProfile.performance:
        return 'เต็มประสิทธิภาพ';
    }
  }
}
