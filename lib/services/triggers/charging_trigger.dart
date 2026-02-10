import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../battery_aware_service.dart';
import '../unified_task_service.dart';
import '../context_retriever.dart';
import '../unified_vector_service.dart';
import '../user_profile_service.dart';
import '../workers/correlation_worker.dart';

import '../big_manager_service.dart';
import 'timer_trigger.dart';

/// 🔌 Charging Trigger - ประมวลผลเมื่อชาร์จ (จบวัน)
///
/// ทำงานเมื่อ:
/// - เสียบชาร์จ (ถือว่าจบวัน)
/// - เวลาหลัง 22:00
///
/// Tasks:
/// - สรุป Session → SessionSummary
/// - วิเคราะห์ข้อมูลสุขภาพ → HealthDoctor
/// - ตั้ง triggers สำหรับวันถัดไป

class ChargingTrigger {
  final BatteryAwareService batteryService;
  final ContextRetriever contextRetriever;
  final UnifiedVectorService vectorService;
  final UserProfileService userProfile;
  final void Function(ChargingTriggerEvent) onTrigger;

  ChargingTrigger({
    required this.batteryService,
    required this.contextRetriever,
    required this.vectorService,
    required this.userProfile,
    required this.onTrigger,
  });

  static const String _lastProcessedKey = 'charging_last_processed';
  static const String _dailySummaryKey = 'daily_summaries';

  DateTime? _lastProcessedTime;
  bool _isProcessing = false;
  final List<DailySummary> _dailySummaries = [];

  DateTime? get lastProcessedTime => _lastProcessedTime;

  /// 🔌 Called when charging starts
  Future<void> onChargingStarted() async {
    await _loadState();

    // ตรวจสอบว่าควรประมวลผลหรือไม่
    if (!_shouldProcess()) {
      debugPrint('🔌 ChargingTrigger: Already processed today');
      return;
    }

    await processEndOfDay();
  }

  /// 🔋 Called when charging stops
  void onChargingStopped() {
    // หยุดงานที่กำลังทำ (ถ้ามี)
    debugPrint('🔋 ChargingTrigger: Charging stopped');
  }

  /// 📥 Load state
  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final lastStr = prefs.getString(_lastProcessedKey);
      if (lastStr != null) {
        _lastProcessedTime = DateTime.parse(lastStr);
      }

      final summaryJson = prefs.getString(_dailySummaryKey);
      if (summaryJson != null) {
        final List<dynamic> list = jsonDecode(summaryJson) as List<dynamic>;
        _dailySummaries.clear();
        _dailySummaries.addAll(
          list.map((e) => DailySummary.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error loading charging state: $e');
    }
  }

  /// 💾 Save state
  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_lastProcessedTime != null) {
        await prefs.setString(_lastProcessedKey, _lastProcessedTime!.toIso8601String());
      }

      // Keep only last 30 days
      final recentSummaries = _dailySummaries.length > 30
          ? _dailySummaries.sublist(_dailySummaries.length - 30)
          : _dailySummaries;

      await prefs.setString(
        _dailySummaryKey,
        jsonEncode(recentSummaries.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving charging state: $e');
    }
  }

  /// 🔍 Should process?
  bool _shouldProcess() {
    if (_isProcessing) return false;

    final now = DateTime.now();

    // ยังไม่เคยประมวลผล
    if (_lastProcessedTime == null) return true;

    // ประมวลผลวันละครั้ง
    final isSameDay = _lastProcessedTime!.day == now.day &&
        _lastProcessedTime!.month == now.month &&
        _lastProcessedTime!.year == now.year;

    if (isSameDay) return false;

    // ต้องหลัง 20:00 (ถือว่าจบวัน)
    if (now.hour < 20) {
      debugPrint('🔌 ChargingTrigger: Too early (before 20:00)');
      return false;
    }

    return true;
  }

  // ============================================================
  // 📊 END OF DAY PROCESSING
  // ============================================================

  /// 📊 Process end of day
  Future<void> processEndOfDay() async {
    if (_isProcessing) return;

    _isProcessing = true;
    debugPrint('🌙 Starting end-of-day processing...');

    try {
      final now = DateTime.now();

      // 1. End current session and create summary
      final sessionSummary = await contextRetriever.endSession();

      // 2. Run BigManager analysis
      debugPrint('👔 Running BigManager analysis...');
      final bigManager = BigManagerService();
      await bigManager.initialize();
      
      // 3. Execute background tasks via UnifiedTaskService
      await _executeBackgroundTasks();

      // 4. 🔮 Run Correlation Analysis (The Hidden Correlation)
      debugPrint('🔮 Running correlation analysis...');
      final correlationWorker = CorrelationWorker();
      final correlationResult = await correlationWorker.runFullAnalysis();
      
      if (correlationResult != null && correlationResult.insights.isNotEmpty) {
        debugPrint('🔮 Found ${correlationResult.insights.length} correlations');
        
        // แจ้งเตือนถ้ามี insight ที่น่าสนใจ
        final topInsight = correlationResult.interestingInsights.firstOrNull;
        if (topInsight != null) {
          onTrigger(ChargingTriggerEvent(
            type: ChargingTriggerType.correlationInsight,
            message: '🔮 พบความเชื่อมโยง: ${topInsight.description}',
            data: {
              'insight': topInsight.toJson(),
              'totalInsights': correlationResult.insights.length,
              'gemmaSummary': correlationResult.gemmaSummary,
            },
          ));
        }
      }

      // 4. Analyze health flags (legacy support)
      final healthAnalysis = await _analyzeHealth(sessionSummary);

      // 5. Extract facts learned today
      final factsLearned = await _extractDailyFacts();

      // 6. Create daily summary
      final dailySummary = DailySummary(
        date: now,
        sessionSummary: sessionSummary?.summaryEn ?? 'No conversations today',
        topics: sessionSummary?.topics ?? [],
        healthFlags: healthAnalysis,
        factsLearned: factsLearned,
        createdAt: now,
      );

      _dailySummaries.add(dailySummary);

      // 7. Schedule tomorrow's triggers
      await _scheduleTomorrowTriggers(dailySummary);

      // 8. Save state
      _lastProcessedTime = now;
      await _saveState();

      // 9. Notify with daily summary
      final topicsSummary = dailySummary.topics.take(3).join(', ');
      onTrigger(ChargingTriggerEvent(
        type: ChargingTriggerType.endOfDaySummary,
        message: 'สรุปวันนี้: ${topicsSummary.isNotEmpty ? topicsSummary : "ไม่มีข้อมูล"}',
        data: dailySummary.toJson(),
      ));

      debugPrint('✅ End-of-day processing complete');
    } catch (e) {
      debugPrint('⚠️ End-of-day processing failed: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// 🔧 Execute background tasks
  Future<void> _executeBackgroundTasks() async {
    debugPrint('🔧 Executing background tasks...');
    
    // Run batch process for comprehensive background tasks
    final taskService = UnifiedTaskService();
    await taskService.forceProcess();
    
    debugPrint('✅ Background tasks complete');
  }

  /// 💊 Analyze health from session
  Future<Map<String, dynamic>> _analyzeHealth(SessionSummary? summary) async {
    final healthFlags = <String, dynamic>{};

    if (summary == null) return healthFlags;

    final summaryLower = summary.summaryEn.toLowerCase();
    final topics = summary.topics;

    // ตรวจจับ period
    if (summaryLower.contains('period') ||
        summaryLower.contains('menstr') ||
        topics.contains('health')) {

      // ค้นหาข้อมูลเพิ่มเติมจาก RAG
      final healthFacts = vectorService.getByCategory('health_log');
      final periodFacts = healthFacts.where((f) =>
        f.content.contains('period') || f.metadata?['condition'] == 'period'
      ).toList();

      if (periodFacts.isNotEmpty) {
        healthFlags['period'] = true;
        healthFlags['period_day'] = 1; // อาจคำนวณจากวันที่บันทึกล่าสุด
        healthFlags['prediction'] = 'possible_cramps_in_2-5_days';
        healthFlags['action'] = 'schedule_daily_health_check';
      }
    }

    // ตรวจจับอาการอื่นๆ
    if (summaryLower.contains('tired') || summaryLower.contains('exhaust')) {
      healthFlags['fatigue'] = true;
    }

    if (summaryLower.contains('pain') || summaryLower.contains('hurt')) {
      healthFlags['pain'] = true;
    }

    return healthFlags;
  }

  /// 📝 Extract facts learned today
  Future<List<String>> _extractDailyFacts() async {
    final facts = <String>[];

    // Get facts added today
    final today = DateTime.now();
    final todayFacts = vectorService.facts.where((f) =>
      f.createdAt.day == today.day &&
          f.createdAt.month == today.month &&
          f.createdAt.year == today.year).toList();

    for (final fact in todayFacts) {
      final category = fact.metadata?['category'] as String? ?? '';
      facts.add('$category: ${fact.content}');
    }

    return facts;
  }

  /// 📅 Schedule tomorrow's triggers
  Future<void> _scheduleTomorrowTriggers(DailySummary summary) async {
    // Schedule morning notification
    final morningTrigger = TimerTrigger(
      batteryService: batteryService,
      onTrigger: (_) {}, // Will be handled by TriggerService
    );

    // Build morning message
    String morningMessage = 'สวัสดีตอนเช้าค่ะ';
    final userName = userProfile.name;
    if (userName.isNotEmpty) {
      morningMessage += ' คุณ$userName';
    }
    morningMessage += '!';

    // Add health follow-up if needed
    if (summary.healthFlags['period'] == true) {
      morningMessage += '\n💊 วันนี้อาการเป็นไงบ้างคะ?';

      // Schedule health check for next 5 days
      for (var i = 1; i <= 5; i++) {
        await morningTrigger.scheduleHealthCheck(
          delay: Duration(days: i),
          message: 'วันนี้อาการเป็นไงบ้างคะ? 🩺',
          condition: 'period_followup',
        );
      }
    }

    await morningTrigger.scheduleMorningTrigger(
      hour: 6,
      minute: 0,
      customMessage: morningMessage,
    );
  }

  // ============================================================
  // 🌅 MORNING NOTIFICATION
  // ============================================================

  /// 🌅 Generate morning notification content
  Future<ChargingTriggerEvent?> generateMorningNotification() async {
    await _loadState();

    final today = DateTime.now();
    final userName = userProfile.name;

    // Build greeting
    String greeting = 'สวัสดีตอนเช้าค่ะ';
    if (userName.isNotEmpty) {
      greeting += ' คุณ$userName';
    }
    greeting += '! ☀️';

    // Check yesterday's summary for context
    final yesterday = _dailySummaries.lastOrNull;
    String? healthNote;

    if (yesterday != null) {
      // Health follow-up
      if (yesterday.healthFlags['period'] == true) {
        final day = (yesterday.healthFlags['period_day'] as int? ?? 1) + 1;
        healthNote = '💊 วันที่ $day ของรอบ - อาการเป็นไงบ้างคะ?';
      }

      // TODO: Check calendar for today's events
      // scheduleNote = 'วันนี้มีนัดหมาย: ...';
    }

    // Build message
    final buffer = StringBuffer(greeting);
    if (healthNote != null) {
      buffer.writeln();
      buffer.write(healthNote);
    }
    // TODO: Add schedule note when calendar integration is ready
    // if (scheduleNote != null) {
    //   buffer.writeln();
    //   buffer.write(scheduleNote);
    // }

    return ChargingTriggerEvent(
      type: ChargingTriggerType.morningNotification,
      message: buffer.toString(),
      data: {
        'date': today.toIso8601String(),
        'hasHealthNote': healthNote != null,
        'hasScheduleNote': false, // TODO: Update when calendar is integrated
      },
    );
  }

  // ============================================================
  // 📊 GETTERS
  // ============================================================

  /// Get recent summaries
  List<DailySummary> getRecentSummaries({int days = 7}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return _dailySummaries.where((s) => s.date.isAfter(cutoff)).toList();
  }

  void dispose() {
    // Cleanup if needed
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// Charging trigger type
enum ChargingTriggerType {
  endOfDaySummary,
  morningNotification,
  healthAnalysis,
  correlationInsight,
}

/// Charging trigger event
class ChargingTriggerEvent {
  final ChargingTriggerType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  ChargingTriggerEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}

/// Daily summary
class DailySummary {
  final DateTime date;
  final String sessionSummary;      // English summary
  final List<String> topics;
  final Map<String, dynamic> healthFlags;
  final List<String> factsLearned;
  final DateTime createdAt;

  DailySummary({
    required this.date,
    required this.sessionSummary,
    required this.topics,
    required this.healthFlags,
    required this.factsLearned,
    required this.createdAt,
  });

  factory DailySummary.fromJson(Map<String, dynamic> json) => DailySummary(
    date: DateTime.parse(json['date'] as String),
    sessionSummary: json['sessionSummary'] as String,
    topics: List<String>.from(json['topics'] as Iterable<dynamic>),
    healthFlags: Map<String, dynamic>.from(json['healthFlags'] as Map),
    factsLearned: List<String>.from(json['factsLearned'] as Iterable<dynamic>),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'sessionSummary': sessionSummary,
    'topics': topics,
    'healthFlags': healthFlags,
    'factsLearned': factsLearned,
    'createdAt': createdAt.toIso8601String(),
  };
}
