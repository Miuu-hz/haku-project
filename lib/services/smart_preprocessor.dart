import 'package:flutter/foundation.dart';

import 'lean_context_service.dart';
import 'user_profile_service.dart';
import 'web_search_service.dart';
import 'workers/fact_worker.dart';
import 'workers/calendar_worker.dart';
import 'workers/reminder_worker.dart';
import 'workers/goal_worker.dart';
import 'workers/health_doctor.dart';

// Re-export for convenience
export 'workers/fact_worker.dart' show ExtractedFact, FactType;
export 'workers/calendar_worker.dart' show CalendarEvent, EventType;
export 'workers/reminder_worker.dart' show Reminder, ReminderFrequency;
export 'workers/goal_worker.dart' show Goal, GoalCategory;
export 'workers/health_doctor.dart' show HealthFact, HealthFactType;

/// 🧠 Smart Preprocessor - ตรวจจับ Intent และเสริม Context
///
/// เนื่องจาก Gemma 3 1B เล็กเกินไปที่จะเข้าใจ structured actions
/// เราจึงใช้ keyword detection ในแอพแทน
///
/// Features:
/// - ตรวจจับคำค้นหา → เรียก Web Search อัตโนมัติ
/// - ตรวจจับชื่อผู้ใช้ → บันทึกลง UserProfile
/// - สร้าง Chat History สำหรับส่งให้ LLM
/// - Lean Context → ประหยัด Token (25 chats แทน 5)
/// - Fact Extraction → บันทึกข้อมูลลง RAG
/// - Calendar Detection → ตรวจจับนัดหมาย
/// - Reminder Detection → ตรวจจับการเตือน
/// - Goal Detection → ตรวจจับเป้าหมาย
/// - Health Detection → ตรวจจับข้อมูลสุขภาพ

class SmartPreprocessor {
  static final SmartPreprocessor _instance = SmartPreprocessor._internal();
  factory SmartPreprocessor() => _instance;
  SmartPreprocessor._internal();

  final WebSearchService _webSearch = WebSearchService();
  final UserProfileService _userProfile = UserProfileService();
  final LeanContextService _leanContext = LeanContextService();

  // Workers
  final FactWorker _factWorker = FactWorker();
  final CalendarWorker _calendarWorker = CalendarWorker();
  final ReminderWorker _reminderWorker = ReminderWorker();
  final GoalWorker _goalWorker = GoalWorker();
  final HealthDoctor _healthDoctor = HealthDoctor();

  // ============================================================
  // 🔍 KEYWORD PATTERNS
  // ============================================================

  /// คำที่บ่งบอกว่าต้องการค้นหาข้อมูล
  static final List<RegExp> _searchPatterns = [
    RegExp(r'ค้นหา(.+)', caseSensitive: false),
    RegExp(r'หา(.+)ให้หน่อย', caseSensitive: false),
    RegExp(r'หา(.+)ให้ที', caseSensitive: false),
    RegExp(r'(.+)คืออะไร', caseSensitive: false),
    RegExp(r'(.+)หมายความว่าอะไร', caseSensitive: false),
    RegExp(r'อากาศ(.*)วันนี้', caseSensitive: false),
    RegExp(r'อากาศ(.*)พรุ่งนี้', caseSensitive: false),
    RegExp(r'พยากรณ์อากาศ', caseSensitive: false),
    RegExp(r'ข่าว(.+)', caseSensitive: false),
    RegExp(r'ราคา(.+)', caseSensitive: false),
    RegExp(r'วิธี(.+)', caseSensitive: false),
    RegExp(r'สูตร(.+)', caseSensitive: false),
  ];

  // ============================================================
  // 🚀 MAIN PREPROCESSING
  // ============================================================

  /// 🧠 Preprocess ข้อความก่อนส่งให้ LLM
  ///
  /// Returns: PreprocessResult ที่มี:
  /// - enrichedContext: ข้อมูลเสริมจาก web search, user profile
  /// - detectedIntent: intent ที่ตรวจจับได้
  Future<PreprocessResult> preprocess(
    String userMessage, {
    List<ChatHistoryItem>? recentHistory,
    bool useLeanContext = true,
  }) async {
    debugPrint('🧠 SmartPreprocessor: Processing "$userMessage"');

    String enrichedContext = '';
    DetectedIntent intent = DetectedIntent.general;
    final workerResults = WorkerResults();

    // 0. Initialize services
    await Future.wait([
      _leanContext.initialize(),
      _calendarWorker.initialize(),
      _reminderWorker.initialize(),
      _goalWorker.initialize(),
      _healthDoctor.initialize(),
    ]);

    // 1. 🔄 Run all workers in parallel (Rule-based, 0 LLM tokens)
    await Future.wait([
      // Fact extraction
      _factWorker.processMessage(userMessage).then((facts) {
        workerResults.facts = facts;
        if (facts.isNotEmpty) {
          debugPrint('📝 Extracted ${facts.length} facts');
        }
      }),

      // Calendar detection
      _calendarWorker.detectEvents(userMessage).then((events) {
        workerResults.calendarEvents = events;
        if (events.isNotEmpty) {
          debugPrint('📅 Detected ${events.length} calendar events');
          intent = DetectedIntent.schedule;
        }
      }),

      // Reminder detection
      _reminderWorker.detectReminders(userMessage).then((reminders) {
        workerResults.reminders = reminders;
        if (reminders.isNotEmpty) {
          debugPrint('🔔 Detected ${reminders.length} reminders');
          intent = DetectedIntent.reminder;
        }
      }),

      // Goal detection
      _goalWorker.detectGoals(userMessage).then((goals) {
        workerResults.goals = goals;
        if (goals.isNotEmpty) {
          debugPrint('🎯 Detected ${goals.length} goals');
        }
      }),

      // Health detection
      _healthDoctor.detectHealth(userMessage).then((health) {
        workerResults.healthFacts = health;
        if (health.isNotEmpty) {
          debugPrint('💊 Detected ${health.length} health facts');
        }
      }),
    ]);

    // 2. ตรวจจับว่าต้องการค้นหาข้อมูลไหม (detect only, ไม่ execute)
    // Search execution ย้ายไปทำใน sendToAI() flow เพื่อไม่ให้ซ้ำซ้อน
    final searchQuery = _detectSearchIntent(userMessage);
    if (searchQuery != null) {
      debugPrint('🔍 Detected search intent: $searchQuery');
      intent = DetectedIntent.search;
    }

    // 3. 📦 Build Context
    if (useLeanContext) {
      // Build lean context with worker data
      final contextParts = <String>[];

      // Identity
      final identity = _userProfile.getIdentityCard();
      if (identity.isNotEmpty) contextParts.add(identity);

      // Health (if any)
      final healthLean = _healthDoctor.leanFormat;
      if (healthLean.isNotEmpty) contextParts.add(healthLean);

      // Calendar (upcoming)
      final calendarLean = _calendarWorker.getLeanFormat();
      if (calendarLean.isNotEmpty) contextParts.add(calendarLean);

      // Reminders
      final reminderLean = _reminderWorker.getLeanFormat();
      if (reminderLean.isNotEmpty) contextParts.add(reminderLean);

      // Goals
      final goalLean = _goalWorker.getLeanFormat();
      if (goalLean.isNotEmpty) contextParts.add(goalLean);

      // Lean chat history
      enrichedContext = '${contextParts.join("\n")}\n${_leanContext.buildContextForAI()}\n$enrichedContext';
      debugPrint('📦 Using Lean Context: ~${_leanContext.getEstimatedTokenCount()} tokens');
    } else {
      // ใช้แบบเดิม
      final identity = _userProfile.getIdentityCard();
      if (identity.isNotEmpty) {
        enrichedContext = '👤 ผู้ใช้: $identity\n$enrichedContext';
      }

      if (recentHistory != null && recentHistory.isNotEmpty) {
        final historyStr = _buildChatHistory(recentHistory);
        enrichedContext = '$historyStr\n$enrichedContext';
      }
    }

    debugPrint('✅ Preprocessing complete, context length: ${enrichedContext.length}');

    return PreprocessResult(
      enrichedContext: enrichedContext.trim(),
      detectedIntent: intent,
      searchQuery: searchQuery,
      workerResults: workerResults,
    );
  }

  /// ➕ Add message to Lean Context
  Future<void> addToLeanContext(String content, {required bool isUser}) async {
    await _leanContext.initialize();
    if (isUser) {
      await _leanContext.addUserMessage(content);
    } else {
      await _leanContext.addAIMessage(content);
    }
  }

  /// 📊 Get Lean Context stats
  Map<String, dynamic> getLeanContextStats() => _leanContext.getSessionInfo();

  // ============================================================
  // 🔍 DETECTION METHODS
  // ============================================================

  /// ตรวจจับว่าต้องการค้นหาข้อมูลไหม
  String? _detectSearchIntent(String message) {
    final lower = message.toLowerCase();

    // ตรวจสอบ patterns
    for (final pattern in _searchPatterns) {
      final match = pattern.firstMatch(lower);
      if (match != null) {
        // สร้าง search query
        if (match.groupCount > 0 && match.group(1)?.isNotEmpty == true) {
          return match.group(1)!.trim();
        }
        // ถ้าไม่มี capture group ให้ใช้ข้อความเต็ม
        return message;
      }
    }

    // ตรวจสอบคำสำคัญ
    final searchKeywords = ['อากาศ', 'ข่าว', 'ราคา', 'หุ้น', 'สกุลเงิน'];
    for (final keyword in searchKeywords) {
      if (lower.contains(keyword)) {
        return message;
      }
    }

    return null;
  }

  /// สร้าง Chat History string
  String _buildChatHistory(List<ChatHistoryItem> history) {
    if (history.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('💬 บทสนทนาล่าสุด:');

    // เอาแค่ 6 ข้อความล่าสุด (3 รอบสนทนา)
    final recent = history.length > 6 ? history.sublist(history.length - 6) : history;

    for (final item in recent) {
      final role = item.isUser ? 'User' : 'Haku';
      // ตัดข้อความยาวเกินไป
      final content = item.content.length > 100
          ? '${item.content.substring(0, 100)}...'
          : item.content;
      buffer.writeln('$role: $content');
    }

    return buffer.toString();
  }

  // ============================================================
  // 🎯 QUICK ACTIONS
  // ============================================================

  /// ตรวจสอบว่าเป็น Quick Action ไหม (ไม่ต้องผ่าน LLM)
  QuickAction? detectQuickAction(String message) {
    final lower = message.toLowerCase();

    // สวัสดี / ทักทาย
    if (_isGreeting(lower)) {
      final userName = _userProfile.name;
      final greeting = userName.isNotEmpty
          ? 'สวัสดีค่ะ คุณ$userName! วันนี้เป็นอย่างไรบ้างคะ? 😊'
          : 'สวัสดีค่ะ! ยินดีที่ได้พบ วันนี้เป็นอย่างไรบ้างคะ? 😊';
      return QuickAction(type: QuickActionType.greeting, response: greeting);
    }

    // ถามชื่อ AI
    if (lower.contains('ชื่ออะไร') && (lower.contains('เธอ') || lower.contains('คุณ'))) {
      return QuickAction(
        type: QuickActionType.askAIName,
        response: 'ฉันชื่อ Haku ค่ะ (箱 แปลว่า "กล่อง" ในภาษาญี่ปุ่น) ยินดีที่ได้รู้จักค่ะ! 📦✨',
      );
    }

    // ถามว่าผู้ใช้ชื่ออะไร
    if ((lower.contains('ฉันชื่ออะไร') || lower.contains('ฉันคือใคร')) && _userProfile.name.isNotEmpty) {
      return QuickAction(
        type: QuickActionType.askUserName,
        response: 'คุณชื่อ ${_userProfile.name} ค่ะ! จำได้แม่นเลย 😊',
      );
    }

    return null;
  }

  bool _isGreeting(String lower) {
    final greetings = ['สวัสดี', 'หวัดดี', 'ดีจ้า', 'hello', 'hi ', 'hey'];
    return greetings.any((g) => lower.startsWith(g) || lower == g);
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// ผลลัพธ์จากการ Preprocess
class PreprocessResult {
  final String enrichedContext;
  final DetectedIntent detectedIntent;
  final String? searchQuery;
  final WorkerResults workerResults;

  PreprocessResult({
    required this.enrichedContext,
    required this.detectedIntent,
    this.searchQuery,
    WorkerResults? workerResults,
  }) : workerResults = workerResults ?? WorkerResults();

  // Backward compatibility
  List<ExtractedFact> get extractedFacts => workerResults.facts;
}

/// ผลลัพธ์จาก Workers ทั้งหมด
class WorkerResults {
  List<ExtractedFact> facts;
  List<CalendarEvent> calendarEvents;
  List<Reminder> reminders;
  List<Goal> goals;
  List<HealthFact> healthFacts;

  WorkerResults({
    this.facts = const [],
    this.calendarEvents = const [],
    this.reminders = const [],
    this.goals = const [],
    this.healthFacts = const [],
  });

  bool get hasAnyResults =>
      facts.isNotEmpty ||
      calendarEvents.isNotEmpty ||
      reminders.isNotEmpty ||
      goals.isNotEmpty ||
      healthFacts.isNotEmpty;

  /// Get summary of what was detected
  String getSummary() {
    final parts = <String>[];
    if (facts.isNotEmpty) parts.add('${facts.length} facts');
    if (calendarEvents.isNotEmpty) parts.add('${calendarEvents.length} events');
    if (reminders.isNotEmpty) parts.add('${reminders.length} reminders');
    if (goals.isNotEmpty) parts.add('${goals.length} goals');
    if (healthFacts.isNotEmpty) parts.add('${healthFacts.length} health');
    return parts.isEmpty ? 'No worker results' : parts.join(', ');
  }
}

/// Intent ที่ตรวจจับได้
enum DetectedIntent {
  general,
  search,
  schedule,
  reminder,
  navigation,
}

/// Quick Action (ตอบได้เลยไม่ต้องผ่าน LLM)
class QuickAction {
  final QuickActionType type;
  final String response;

  QuickAction({required this.type, required this.response});
}

enum QuickActionType {
  greeting,
  askAIName,
  askUserName,
}

/// Chat History Item
class ChatHistoryItem {
  final String content;
  final bool isUser;
  final DateTime timestamp;

  ChatHistoryItem({
    required this.content,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
