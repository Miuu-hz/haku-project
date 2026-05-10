import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../battery_aware_service.dart';
import '../deferred_task_service.dart';
import '../scheduler_service.dart';
import '../unified_vector_service.dart';
import '../user_profile_service.dart';
import '../worker_service.dart';
import 'manager_summary_strategy.dart';
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
  final UnifiedVectorService vectorService;
  final UserProfileService userProfile;
  final void Function(ChargingTriggerEvent) onTrigger;

  ChargingTrigger({
    required this.batteryService,
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

      // 2. Run ManagerSummaryStrategy (NEW - Orchestrator Pattern)
      debugPrint('📊 Running ManagerSummaryStrategy...');
      final managerStrategy = ManagerSummaryStrategy(
        vectorService: vectorService,
        userProfile: userProfile,
      );
      final managerResult = await managerStrategy.analyze();
      
      // 3. Execute worker tasks from ManagerSummaryStrategy
      await _executeWorkerTasks(managerResult.workerTasks);

      // 4. Analyze health flags (legacy support)
      final healthAnalysis = await _analyzeHealth();

      // 5. Extract facts learned today
      final factsLearned = await _extractDailyFacts();

      // 6. Create daily summary
      final dailySummary = DailySummary(
        date: now,
        sessionSummary: 'No conversations today',
        topics: const [],
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

      // 9. Notify with ManagerSummary insights
      final insightsSummary = managerResult.insights.map((i) => i.title).join(', ');
      onTrigger(ChargingTriggerEvent(
        type: ChargingTriggerType.endOfDaySummary,
        message: 'สรุปวันนี้: ${insightsSummary.isNotEmpty ? insightsSummary : dailySummary.topics.take(3).join(", ")}',
        data: {
          ...dailySummary.toJson(),
          'managerInsights': managerResult.insights.map((i) => i.toJson()).toList(),
          'managerRecommendations': managerResult.recommendations.map((r) => r.toJson()).toList(),
        },
      ));

      debugPrint('✅ End-of-day processing complete');
    } catch (e) {
      debugPrint('⚠️ End-of-day processing failed: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// 🔧 Execute worker tasks from ManagerSummaryStrategy
  Future<void> _executeWorkerTasks(List<WorkerTask> tasks) async {
    if (tasks.isEmpty) return;
    
    debugPrint('🔧 Executing ${tasks.length} worker tasks via WorkerService...');
    
    // Use WorkerService for batch processing
    final workerService = WorkerService();
    
    for (final task in tasks) {
      try {
        switch (task.worker) {
          case WorkerType.reminder:
            debugPrint('  ⏰ Reminder: ${task.action}');
            // Parse reminder data and schedule via DeferredTaskService
            final reminderTitle = task.data?['title'] as String? ?? task.action;
            final reminderBody = task.data?['body'] as String? ?? 'อย่าลืมนะคะ';
            final delayMinutes = task.data?['delayMinutes'] as int?;
            DeferredTaskService().enqueue(
              taskType: 'reminder',
              payload: {
                'title': reminderTitle,
                'body': reminderBody,
                if (delayMinutes != null) 'delayMinutes': delayMinutes,
              },
              priority: TaskPriority.high,
            );
            break;
            
          case WorkerType.fact:
            debugPrint('  📝 Fact: ${task.action}');
            // Facts already stored in vectorService by ManagerSummaryStrategy
            // Queue for deferred processing if needed
            workerService.queueFactExtraction();
            break;
            
          case WorkerType.calendar:
            debugPrint('  📅 Calendar: ${task.action}');
            // Queue calendar processing
            DeferredTaskService().enqueue(
              taskType: 'calendar_event',
              payload: task.data,
              priority: TaskPriority.normal,
            );
            break;
            
          case WorkerType.health:
            debugPrint('  💊 Health: ${task.action}');
            // Queue health analysis
            workerService.queueHealthAnalysis();
            break;
        }
      } catch (e) {
        debugPrint('  ⚠️ Task failed: $e');
      }
    }
    
    // Also run WorkerService batch process for comprehensive background tasks
    debugPrint('🔧 Running WorkerService batch process...');
    await workerService.runBatchProcess();
  }

  /// 💊 Analyze health from vector store
  Future<Map<String, dynamic>> _analyzeHealth() async {
    final healthFlags = <String, dynamic>{};

    final healthFacts = vectorService.getByCategory('health_log');
    final periodFacts = healthFacts.where((f) =>
      f.content.contains('period') || f.metadata?['condition'] == 'period'
    ).toList();

    if (periodFacts.isNotEmpty) {
      healthFlags['period'] = true;
      healthFlags['period_day'] = 1;
      healthFlags['prediction'] = 'possible_cramps_in_2-5_days';
      healthFlags['action'] = 'schedule_daily_health_check';
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
      morningMessage += '\nวันนี้อาการเป็นไงบ้างคะ?';

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
    greeting += '!';

    // Check yesterday's summary for context
    final yesterday = _dailySummaries.lastOrNull;
    String? healthNote;
    String? scheduleNote;

    if (yesterday != null) {
      // Health follow-up
      if (yesterday.healthFlags['period'] == true) {
        final day = (yesterday.healthFlags['period_day'] as int? ?? 1) + 1;
        healthNote = 'วันที่ $day ของรอบ - อาการเป็นไงบ้างคะ?';
      }
    }

    // Check calendar for today's events
    try {
      final dayStart = DateTime(today.year, today.month, today.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final events = await SchedulerService().getCalendarEvents(dayStart, dayEnd);
      if (events.isNotEmpty) {
        final titles = events.take(3).map((e) => e['title'] as String? ?? 'นัดหมาย').join(', ');
        scheduleNote = 'วันนี้มีนัดหมาย: $titles';
        if (events.length > 3) {
          scheduleNote += ' และอีก ${events.length - 3} รายการ';
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load calendar events: $e');
    }

    // Build message
    final buffer = StringBuffer(greeting);
    if (healthNote != null) {
      buffer.writeln();
      buffer.write(healthNote);
    }
    if (scheduleNote != null) {
      buffer.writeln();
      buffer.write(scheduleNote);
    }

    return ChargingTriggerEvent(
      type: ChargingTriggerType.morningNotification,
      message: buffer.toString(),
      data: {
        'date': today.toIso8601String(),
        'hasHealthNote': healthNote != null,
        'hasScheduleNote': scheduleNote != null,
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
