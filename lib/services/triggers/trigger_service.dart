import 'dart:async';

import 'package:flutter/foundation.dart';

import '../battery_aware_service.dart';
import '../context_retriever.dart';
import '../user_profile_service.dart';
import '../unified_vector_service.dart';
import 'timer_trigger.dart';
import 'charging_trigger.dart';
import '../big_manager_service.dart';

/// 🎯 Trigger Service - ศูนย์รวม Triggers ทั้งหมด
///
/// จัดการ:
/// - TimerTrigger: เช็คตามเวลา/location (30 นาทีหลังถึงร้าน)
/// - ChargingTrigger: ทำงานตอนชาร์จ (จบวัน)
/// - MorningTrigger: แจ้งเตือนตอนเช้า
///
/// Integration:
/// - BatteryAwareService: ตรวจสอบสถานะแบต
/// - ContextRetriever: ดึงข้อมูลบริบท
/// - UnifiedVectorService: เก็บข้อมูล RAG

class TriggerService {
  static final TriggerService _instance = TriggerService._internal();
  factory TriggerService() => _instance;
  TriggerService._internal();

  final BatteryAwareService _battery = BatteryAwareService();
  final ContextRetriever _contextRetriever = ContextRetriever();
  final UserProfileService _userProfile = UserProfileService();
  final UnifiedVectorService _vectorService = UnifiedVectorService();

  // Sub-services
  late final TimerTrigger _timerTrigger;
  late final ChargingTrigger _chargingTrigger;
  late final BigManagerService _bigManager;

  bool _isInitialized = false;

  // Callbacks
  void Function(TriggerEvent event)? onTrigger;

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize dependencies
    await _battery.initialize();
    // ContextRetriever uses lazy init, no initialize needed
    await _vectorService.initialize();

    // Create sub-services
    _timerTrigger = TimerTrigger(
      batteryService: _battery,
      onTrigger: _handleTimerTrigger,
    );

    _chargingTrigger = ChargingTrigger(
      batteryService: _battery,
      contextRetriever: _contextRetriever,
      vectorService: _vectorService,
      userProfile: _userProfile,
      onTrigger: _handleChargingTrigger,
    );

    _bigManager = BigManagerService();
    await _bigManager.initialize();

    // Register battery callbacks
    _battery.onChargingStarted = _onChargingStarted;
    _battery.onChargingStopped = _onChargingStopped;

    // Start timer trigger
    await _timerTrigger.start();

    _isInitialized = true;
    debugPrint('✅ Trigger Service initialized');
  }

  // ============================================================
  // 📡 EVENT HANDLERS
  // ============================================================

  void _onChargingStarted() {
    debugPrint('🔌 TriggerService: Charging started');
    _chargingTrigger.onChargingStarted();
  }

  void _onChargingStopped() {
    debugPrint('🔋 TriggerService: Charging stopped');
    _chargingTrigger.onChargingStopped();
  }

  void _handleTimerTrigger(TimerTriggerEvent event) {
    debugPrint('⏰ Timer trigger: ${event.type.name}');

    final triggerEvent = TriggerEvent(
      type: TriggerType.timer,
      subType: event.type.name,
      message: event.message,
      data: event.data,
    );

    onTrigger?.call(triggerEvent);
  }

  void _handleChargingTrigger(ChargingTriggerEvent event) {
    debugPrint('🔌 Charging trigger: ${event.type.name}');

    final triggerEvent = TriggerEvent(
      type: TriggerType.charging,
      subType: event.type.name,
      message: event.message,
      data: event.data,
    );

    onTrigger?.call(triggerEvent);
  }

  // ============================================================
  // 🎯 MANUAL TRIGGERS
  // ============================================================

  /// 📍 Trigger location arrival
  Future<void> triggerLocationArrival(String locationName) async {
    await _timerTrigger.onLocationArrival(locationName);
  }

  /// ⏰ Trigger time-based check
  Future<void> triggerTimeCheck() async {
    await _timerTrigger.checkScheduledTriggers();
  }

  /// 🔋 Trigger end of day (manual)
  Future<void> triggerEndOfDay() async {
    await _chargingTrigger.processEndOfDay();
  }

  /// 🌅 Trigger morning notification
  Future<ChargingTriggerEvent?> triggerMorning() => _chargingTrigger.generateMorningNotification();

  // ============================================================
  // 📊 MANAGER SUMMARY
  // ============================================================

  /// 📊 Run BigManager analysis
  Future<String> runBigManagerAnalysis(String message) => _bigManager.analyzeAndDispatch(message);

  // ============================================================
  // 📋 GETTERS
  // ============================================================

  /// Get pending triggers count
  int get pendingTriggersCount => _timerTrigger.pendingCount;

  /// Get last summary time
  DateTime? get lastSummaryTime => _chargingTrigger.lastProcessedTime;

  /// Is charging
  bool get isCharging => _battery.isChargingOrFull;

  /// Battery level
  int get batteryLevel => _battery.batteryLevel;

  // ============================================================
  // 🧹 CLEANUP
  // ============================================================

  void dispose() {
    _timerTrigger.dispose();
    _chargingTrigger.dispose();
    _battery.dispose();
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// Trigger type
enum TriggerType {
  timer,      // Time-based or location-based
  charging,   // Charging events
  morning,    // Morning notification
  health,     // Health-related
}

/// Trigger Event
class TriggerEvent {
  final TriggerType type;
  final String subType;
  final String? message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  TriggerEvent({
    required this.type,
    required this.subType,
    this.message,
    this.data,
  }) : timestamp = DateTime.now();

  /// Convert to notification content
  Map<String, String> toNotification() => {
    'title': _getTitle(),
    'body': message ?? '',
  };

  String _getTitle() {
    switch (type) {
      case TriggerType.timer:
        return '⏰ Haku';
      case TriggerType.charging:
        return '🔌 สรุปวันนี้';
      case TriggerType.morning:
        return '🌅 สวัสดีตอนเช้า';
      case TriggerType.health:
        return '💊 เตือนสุขภาพ';
    }
  }
}
