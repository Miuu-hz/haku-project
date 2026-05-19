import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battery_aware_service.dart';

/// 🧠 Smart Interval Service - ปรับ interval อัตโนมัติตามพฤติกรรม
///
/// Features:
/// - เรียนรู้ช่วงเวลาที่ผู้ใช้ active
/// - ลด interval ช่วง active, เพิ่มช่วง inactive
/// - ผสมกับ battery level

class SmartIntervalService {
  static final SmartIntervalService _instance = SmartIntervalService._internal();
  factory SmartIntervalService() => _instance;
  SmartIntervalService._internal();

  final BatteryAwareService _batteryService = BatteryAwareService();

  static const String _activityKey = 'user_activity_pattern';

  // Activity tracking
  final Map<int, int> _hourlyActivity = {}; // hour -> activity count
  int _consecutiveIdleMinutes = 0;

  // Current interval
  Duration _currentInterval = const Duration(minutes: 5);
  Timer? _intervalTimer;

  // Callbacks
  void Function()? onIntervalTick;
  void Function(Duration)? onIntervalChanged;

  bool _isInitialized = false;

  // Settings
  static const Duration minInterval = Duration(minutes: 1);
  static const Duration maxInterval = Duration(minutes: 30);
  static const Duration defaultInterval = Duration(minutes: 5);

  // Getters
  Duration get currentInterval => _currentInterval;
  bool get isUserActive => _consecutiveIdleMinutes < 5;

  /// 🚀 Initialize service
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadActivityPattern();
    _startIntervalTimer();

    _isInitialized = true;
    debugPrint('✅ Smart Interval Service initialized');
    debugPrint('   - Current interval: ${_currentInterval.inMinutes} min');
  }

  /// 📥 Load activity pattern
  Future<void> _loadActivityPattern() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_activityKey);

      if (json != null) {
        final parts = json.split(',');
        for (int i = 0; i < parts.length && i < 24; i++) {
          _hourlyActivity[i] = int.tryParse(parts[i]) ?? 0;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error loading activity pattern: $e');
    }
  }

  /// 💾 Save activity pattern
  Future<void> _saveActivityPattern() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = List.generate(24, (i) => _hourlyActivity[i] ?? 0);
      await prefs.setString(_activityKey, values.join(','));
    } catch (e) {
      debugPrint('⚠️ Error saving activity pattern: $e');
    }
  }

  /// 📱 Record user activity
  void recordActivity() {
    final now = DateTime.now();
    // Activity recorded
    _consecutiveIdleMinutes = 0;

    // บันทึก activity ตาม hour
    final hour = now.hour;
    _hourlyActivity[hour] = (_hourlyActivity[hour] ?? 0) + 1;

    // Save periodically
    if (now.minute == 0) {
      _saveActivityPattern();
    }

    // Recalculate interval
    _recalculateInterval();
  }

  /// ⏱️ Start interval timer
  void _startIntervalTimer() {
    _intervalTimer?.cancel();

    _intervalTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _consecutiveIdleMinutes++;
      _recalculateInterval();

      // Check if it's time to tick
      if (_consecutiveIdleMinutes % _currentInterval.inMinutes == 0) {
        onIntervalTick?.call();
      }
    });
  }

  /// 🧮 Recalculate optimal interval
  void _recalculateInterval() {
    final oldInterval = _currentInterval;
    final now = DateTime.now();
    final hour = now.hour;

    // 1. Base interval จาก battery
    final profile = _batteryService.getRecommendedProfile();
    final baseInterval = Duration(minutes: profile.triggerIntervalMinutes);

    // 2. ปรับตาม historical activity
    final hourlyScore = _getHourlyActivityScore(hour);
    double activityMultiplier;

    if (hourlyScore > 10) {
      // ช่วง high activity
      activityMultiplier = 0.5; // ลด interval
    } else if (hourlyScore > 5) {
      // ช่วง medium activity
      activityMultiplier = 0.75;
    } else if (hourlyScore > 0) {
      // ช่วง low activity
      activityMultiplier = 1.0;
    } else {
      // ไม่มี activity (อาจเป็นเวลานอน)
      activityMultiplier = 2.0; // เพิ่ม interval
    }

    // 3. ปรับตาม recent activity
    if (_consecutiveIdleMinutes > 30) {
      // Idle มากกว่า 30 นาที
      activityMultiplier *= 2.0;
    } else if (_consecutiveIdleMinutes > 15) {
      // Idle 15-30 นาที
      activityMultiplier *= 1.5;
    } else if (_consecutiveIdleMinutes < 2) {
      // เพิ่ง active
      activityMultiplier *= 0.5;
    }

    // Calculate new interval
    final newMinutes = (baseInterval.inMinutes * activityMultiplier).round();
    _currentInterval = Duration(
      minutes: newMinutes.clamp(minInterval.inMinutes, maxInterval.inMinutes),
    );

    // Notify if changed
    if (_currentInterval != oldInterval) {
      debugPrint(
          '⏱️ Interval changed: ${oldInterval.inMinutes} -> ${_currentInterval.inMinutes} min');
      onIntervalChanged?.call(_currentInterval);
    }
  }

  /// 📊 Get activity score for hour
  int _getHourlyActivityScore(int hour) {
    // Average of current hour and adjacent hours
    final prev = (hour - 1) % 24;
    final next = (hour + 1) % 24;

    return ((_hourlyActivity[prev] ?? 0) +
            (_hourlyActivity[hour] ?? 0) * 2 +
            (_hourlyActivity[next] ?? 0)) ~/
        4;
  }

  /// 🔮 Predict if user will be active
  bool predictUserActive(int hour) {
    final score = _getHourlyActivityScore(hour);
    return score > 3;
  }

  /// 📈 Get activity pattern (for visualization)
  Map<int, int> getActivityPattern() => Map.unmodifiable(_hourlyActivity);

  /// 🌙 Get detected sleep hours
  List<int> getDetectedSleepHours() {
    final sleepHours = <int>[];

    for (int hour = 0; hour < 24; hour++) {
      if ((_hourlyActivity[hour] ?? 0) == 0) {
        sleepHours.add(hour);
      }
    }

    return sleepHours;
  }

  /// ⚡ Get recommended interval for specific context
  Duration getIntervalFor({
    bool? isCharging,
    int? batteryLevel,
    bool? isUserActive,
  }) {
    Duration interval = defaultInterval;

    // Battery factor
    if (isCharging == true) {
      interval = minInterval;
    } else if (batteryLevel != null) {
      if (batteryLevel < 10) {
        interval = maxInterval;
      } else if (batteryLevel < 20) {
        interval = const Duration(minutes: 15);
      }
    }

    // User activity factor
    if (isUserActive == true) {
      interval = Duration(
        minutes: (interval.inMinutes * 0.5).round().clamp(1, 30),
      );
    } else if (isUserActive == false) {
      interval = Duration(
        minutes: (interval.inMinutes * 2).round().clamp(1, 30),
      );
    }

    return interval;
  }

  /// 🔄 Reset activity data
  Future<void> resetActivityData() async {
    _hourlyActivity.clear();
    _consecutiveIdleMinutes = 0;
    // Activity reset
    await _saveActivityPattern();
  }

  /// 🧹 Dispose
  void dispose() {
    _intervalTimer?.cancel();
    _isInitialized = false;
  }
}
