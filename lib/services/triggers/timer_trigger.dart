import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../battery_aware_service.dart';

/// ⏰ Timer Trigger - Trigger ตามเวลาและ Location
///
/// รองรับ:
/// - 30 นาทีหลังถึงร้าน → "ร้านนี้เป็นไงบ้าง?"
/// - เช้า 6 โมง → แจ้งเตือนวัน
/// - กำหนดเอง → custom triggers

class TimerTrigger {
  final BatteryAwareService batteryService;
  final void Function(TimerTriggerEvent) onTrigger;

  TimerTrigger({
    required this.batteryService,
    required this.onTrigger,
  });

  static const String _pendingTriggersKey = 'pending_triggers';
  static const String _locationHistoryKey = 'location_history';

  Timer? _checkTimer;
  final List<PendingTrigger> _pendingTriggers = [];
  LocationArrival? _lastArrival;

  int get pendingCount => _pendingTriggers.length;

  /// 🚀 Start timer
  Future<void> start() async {
    await _loadPendingTriggers();

    // ตรวจสอบทุก 1 นาที (ปรับตาม energy profile)
    final interval = batteryService.getRecommendedProfile().triggerIntervalMinutes;
    _checkTimer = Timer.periodic(Duration(minutes: interval), (_) {
      checkScheduledTriggers();
    });

    debugPrint('⏰ Timer Trigger started (interval: ${interval}m)');
  }

  /// 📥 Load pending triggers
  Future<void> _loadPendingTriggers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_pendingTriggersKey);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _pendingTriggers.clear();
        _pendingTriggers.addAll(
          list.map((e) => PendingTrigger.fromJson(e as Map<String, dynamic>)),
        );
      }

      // Load last location
      final locationJson = prefs.getString(_locationHistoryKey);
      if (locationJson != null) {
        _lastArrival = LocationArrival.fromJson(
          jsonDecode(locationJson) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error loading triggers: $e');
    }
  }

  /// 💾 Save pending triggers
  Future<void> _savePendingTriggers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _pendingTriggersKey,
        jsonEncode(_pendingTriggers.map((t) => t.toJson()).toList()),
      );

      if (_lastArrival != null) {
        await prefs.setString(
          _locationHistoryKey,
          jsonEncode(_lastArrival!.toJson()),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error saving triggers: $e');
    }
  }

  // ============================================================
  // 📍 LOCATION TRIGGERS
  // ============================================================

  /// 📍 Called when user arrives at a location
  Future<void> onLocationArrival(String locationName) async {
    final now = DateTime.now();

    _lastArrival = LocationArrival(
      locationName: locationName,
      arrivalTime: now,
    );

    // Add trigger for 30 minutes later
    final trigger = PendingTrigger(
      id: 'loc_${now.millisecondsSinceEpoch}',
      type: TimerTriggerType.locationFollowUp,
      triggerTime: now.add(const Duration(minutes: 30)),
      data: {
        'locationName': locationName,
        'arrivalTime': now.toIso8601String(),
      },
    );

    _pendingTriggers.add(trigger);
    await _savePendingTriggers();

    debugPrint('📍 Location arrival registered: $locationName (trigger in 30m)');
  }

  /// 📍 Check if still at location
  bool isStillAtLocation(String locationName) {
    if (_lastArrival == null) return false;
    if (_lastArrival!.locationName != locationName) return false;

    // ถ้าอยู่มากกว่า 2 ชม. ถือว่าออกแล้ว
    final elapsed = DateTime.now().difference(_lastArrival!.arrivalTime);
    return elapsed.inHours < 2;
  }

  // ============================================================
  // ⏰ SCHEDULED TRIGGERS
  // ============================================================

  /// ➕ Add custom trigger
  Future<void> addTrigger({
    required TimerTriggerType type,
    required DateTime triggerTime,
    Map<String, dynamic>? data,
  }) async {
    final trigger = PendingTrigger(
      id: '${type.name}_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      triggerTime: triggerTime,
      data: data,
    );

    _pendingTriggers.add(trigger);
    await _savePendingTriggers();
  }

  /// 🔍 Check and fire triggers
  Future<void> checkScheduledTriggers() async {
    if (_pendingTriggers.isEmpty) return;

    final now = DateTime.now();
    final toFire = <PendingTrigger>[];

    for (final trigger in _pendingTriggers) {
      if (now.isAfter(trigger.triggerTime)) {
        toFire.add(trigger);
      }
    }

    for (final trigger in toFire) {
      await _fireTrigger(trigger);
      _pendingTriggers.remove(trigger);
    }

    if (toFire.isNotEmpty) {
      await _savePendingTriggers();
    }
  }

  /// 🔥 Fire a trigger
  Future<void> _fireTrigger(PendingTrigger trigger) async {
    debugPrint('🔥 Firing trigger: ${trigger.type.name}');

    String message;

    switch (trigger.type) {
      case TimerTriggerType.locationFollowUp:
        final locationName = trigger.data?['locationName'] ?? 'ที่นี่';
        message = 'ร้าน$locationNameเป็นไงบ้างคะ? อร่อยไหม? 😊';
        break;

      case TimerTriggerType.morningReminder:
        message = trigger.data?['message'] ?? 'สวัสดีตอนเช้าค่ะ!';
        break;

      case TimerTriggerType.healthCheck:
        message = trigger.data?['message'] ?? 'วันนี้อาการเป็นไงบ้างคะ?';
        break;

      case TimerTriggerType.goalReminder:
        final goal = trigger.data?['goal'] ?? 'เป้าหมาย';
        message = 'อย่าลืม$goalนะคะ! 💪';
        break;

      case TimerTriggerType.custom:
        message = trigger.data?['message'] ?? '';
        break;
    }

    final event = TimerTriggerEvent(
      type: trigger.type,
      message: message,
      data: trigger.data,
    );

    onTrigger(event);
  }

  // ============================================================
  // 🌅 MORNING TRIGGER
  // ============================================================

  /// 🌅 Schedule morning trigger for tomorrow
  Future<void> scheduleMorningTrigger({
    required int hour,
    required int minute,
    String? customMessage,
  }) async {
    final now = DateTime.now();
    var triggerTime = DateTime(now.year, now.month, now.day, hour, minute);

    // ถ้าเวลาผ่านแล้ว ตั้งเป็นพรุ่งนี้
    if (triggerTime.isBefore(now)) {
      triggerTime = triggerTime.add(const Duration(days: 1));
    }

    await addTrigger(
      type: TimerTriggerType.morningReminder,
      triggerTime: triggerTime,
      data: {'message': customMessage},
    );

    debugPrint('🌅 Morning trigger scheduled for $triggerTime');
  }

  /// 💊 Schedule health check trigger
  Future<void> scheduleHealthCheck({
    required Duration delay,
    required String message,
    required String condition,
  }) async {
    await addTrigger(
      type: TimerTriggerType.healthCheck,
      triggerTime: DateTime.now().add(delay),
      data: {
        'message': message,
        'condition': condition,
      },
    );
  }

  // ============================================================
  // 🧹 CLEANUP
  // ============================================================

  /// Remove expired triggers
  Future<void> cleanupExpiredTriggers() async {
    final now = DateTime.now();
    final oldCount = _pendingTriggers.length;

    // Remove triggers older than 24 hours
    _pendingTriggers.removeWhere((t) {
      final age = now.difference(t.triggerTime);
      return age.inHours > 24;
    });

    if (_pendingTriggers.length != oldCount) {
      await _savePendingTriggers();
      debugPrint('🧹 Cleaned up ${oldCount - _pendingTriggers.length} expired triggers');
    }
  }

  void dispose() {
    _checkTimer?.cancel();
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// Trigger type
enum TimerTriggerType {
  locationFollowUp,  // 30m after arriving at location
  morningReminder,   // Morning notification
  healthCheck,       // Health-related reminder
  goalReminder,      // Goal reminder
  custom,            // Custom trigger
}

/// Pending trigger
class PendingTrigger {
  final String id;
  final TimerTriggerType type;
  final DateTime triggerTime;
  final Map<String, dynamic>? data;
  final DateTime createdAt;

  PendingTrigger({
    required this.id,
    required this.type,
    required this.triggerTime,
    this.data,
  }) : createdAt = DateTime.now();

  factory PendingTrigger.fromJson(Map<String, dynamic> json) => PendingTrigger(
    id: json['id'] as String,
    type: TimerTriggerType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => TimerTriggerType.custom,
    ),
    triggerTime: DateTime.parse(json['triggerTime'] as String),
    data: json['data'] as Map<String, dynamic>?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'triggerTime': triggerTime.toIso8601String(),
    'data': data,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// Location arrival record
class LocationArrival {
  final String locationName;
  final DateTime arrivalTime;

  LocationArrival({
    required this.locationName,
    required this.arrivalTime,
  });

  factory LocationArrival.fromJson(Map<String, dynamic> json) => LocationArrival(
    locationName: json['locationName'] as String,
    arrivalTime: DateTime.parse(json['arrivalTime'] as String),
  );

  Map<String, dynamic> toJson() => {
    'locationName': locationName,
    'arrivalTime': arrivalTime.toIso8601String(),
  };
}

/// Timer trigger event
class TimerTriggerEvent {
  final TimerTriggerType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  TimerTriggerEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
