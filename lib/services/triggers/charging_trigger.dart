import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../battery_aware_service.dart';
import '../deferred_task_service.dart';
import '../llm_service.dart';
import '../rag_service.dart';
import '../scheduler_service.dart';
import '../unified_vector_service.dart';
import '../user_profile_service.dart';
import '../wiki_service.dart';
import '../worker_service.dart';
import '../workers/fact_worker.dart';
import 'manager_summary_strategy.dart';

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
  final BatteryAwareService? batteryService;
  final UnifiedVectorService vectorService;
  final UserProfileService userProfile;
  final RAGService? ragService;
  final void Function(ChargingTriggerEvent) onTrigger;

  ChargingTrigger({
    this.batteryService,
    required this.vectorService,
    required this.userProfile,
    this.ragService,
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
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('proactive_charging_enabled') ?? true)) {
      debugPrint('🔌 ChargingTrigger: disabled in settings');
      return;
    }

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
  /// [llmService] — ถ้าระบุ จะใช้ SLM (On-device LLM) วิเคราะห์ patterns + สร้าง insight
  Future<void> processEndOfDay({LLMService? llmService}) async {
    if (_isProcessing) return;

    _isProcessing = true;
    debugPrint('🌙 Starting end-of-day processing...');

    bool slmLoaded = false;
    try {
      final now = DateTime.now();

      // 🔒 ถ้ามี SLM → เริ่ม background session (โหลดโมเดล + ยกเลิก auto-unload)
      if (llmService != null) {
        slmLoaded = await llmService.beginBackgroundSession();
        debugPrint(slmLoaded ? '🧠 SLM loaded for background processing' : '⚠️ SLM not available, using rule-based only');
      }

      // 1. Run ManagerSummaryStrategy (with optional SLM)
      debugPrint('📊 Running ManagerSummaryStrategy...');
      final managerStrategy = ManagerSummaryStrategy(
        vectorService: vectorService,
        userProfile: userProfile,
      );
      final managerResult = await managerStrategy.analyze(
        llmService: slmLoaded ? llmService : null,
      );
      
      // 2. Execute worker tasks from ManagerSummaryStrategy (background-safe)
      await _executeWorkerTasks(managerResult.workerTasks, llmService: llmService);

      // 3. Analyze health flags (legacy support)
      final healthAnalysis = await _analyzeHealth();

      // 4. Extract facts learned today
      final factsLearned = await _extractDailyFacts();

      // 4.3 Update pending Wiki summaries (LLM synthesis + link extraction)
      if (slmLoaded) {
        debugPrint('📚 Updating pending Wiki summaries...');
        await WikiService().updatePendingSummaries(batchSize: 10);
      }

      // 4.4 Analyze check-in patterns (background batch)
      debugPrint('📝 Analyzing check-in patterns...');
      await FactWorker().analyzeCheckInPatterns(
        llmService: slmLoaded ? llmService : null,
      );

      // 4.5 Query RAGService for today's relevant diary context
      String? ragContext;
      if (ragService != null) {
        try {
          final topics = managerResult.insights.map((i) => i.title).join(' ');
          final query = topics.isNotEmpty ? topics : 'today activities summary';
          ragContext = await ragService!.buildContext(query, topK: 5);
          debugPrint('📚 RAG context: ${ragContext.length} chars');
        } catch (e) {
          debugPrint('⚠️ RAG context failed (non-fatal): $e');
        }
      }

      // 5. Create daily summary
      final dailySummary = DailySummary(
        date: now,
        sessionSummary: 'No conversations today',
        topics: const [],
        healthFlags: healthAnalysis,
        factsLearned: factsLearned,
        createdAt: now,
      );

      _dailySummaries.add(dailySummary);
      // 6. Save state
      _lastProcessedTime = now;
      await _saveState();

      // 8. Generate Thai summary message (with SLM + RAG context if available)
      final thaiSummary = await _generateThaiSummary(managerResult, dailySummary, llmService, ragContext: ragContext);

      // 9. Notify
      onTrigger(ChargingTriggerEvent(
        type: ChargingTriggerType.endOfDaySummary,
        message: thaiSummary,
        ragContext: ragContext,
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
      // 🔓 ปิด SLM background session
      if (slmLoaded && llmService != null) {
        await llmService.endBackgroundSession();
      }
      _isProcessing = false;
    }
  }

  /// 📝 สร้างข้อความสรุปภาษาไทย (ใช้ SLM ถ้ามี)
  Future<String> _generateThaiSummary(
    ManagerSummaryResult managerResult,
    DailySummary dailySummary,
    LLMService? llmService, {
    String? ragContext,
  }) async {
    // ถ้ามี SLM และ insights มีข้อมูล → ใช้ SLM สร้างสรุปภาษาไทย
    if (llmService != null && llmService.isInitialized && managerResult.insights.isNotEmpty) {
      try {
        final insightsText = managerResult.insights
            .take(5)
            .map((i) => '- ${i.title}: ${i.description}')
            .join('\n');

        final ragSection = (ragContext != null && ragContext.isNotEmpty)
            ? '\nบันทึกวันนี้:\n$ragContext\n'
            : '';

        final prompt = '''
สรุปวันนี้ของผู้ใช้จากข้อมูลต่อไปนี้ ให้กระชับ เป็นกันเอง มี emoji 1-2 ตัว:

Insights:
$insightsText$ragSection
สรุป (1-2 ประโยค):''';

        final summary = await llmService.generate(prompt, maxTokens: 150);
        if (summary.trim().isNotEmpty) {
          return summary.trim();
        }
      } catch (e) {
        debugPrint('⚠️ SLM summary generation failed: $e');
      }
    }

    // Fallback: ใช้ rule-based summary
    final insightsSummary = managerResult.insights.map((i) => i.title).join(', ');
    return 'สรุปวันนี้: ${insightsSummary.isNotEmpty ? insightsSummary : dailySummary.topics.take(3).join(", ")}';
  }

  /// 🔧 Execute worker tasks from ManagerSummaryStrategy
  /// [llmService] — ส่งต่อให้ WorkerService ใช้ SLM ใน batch process
  Future<void> _executeWorkerTasks(List<WorkerTask> tasks, {LLMService? llmService}) async {
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
    await workerService.runBatchProcess(backgroundMode: true);
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
  final String? ragContext;
  final DateTime timestamp;

  ChargingTriggerEvent({
    required this.type,
    required this.message,
    this.data,
    this.ragContext,
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
