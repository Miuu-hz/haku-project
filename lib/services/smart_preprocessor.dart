import 'package:flutter/foundation.dart';

import '../models/entry.dart';
import 'database_helper.dart';
import 'lean_context_service.dart';
import 'rag_service.dart';
import 'scheduler_service.dart';
import 'user_profile_service.dart';
import 'weather_service.dart';
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

  /// คำที่บ่งบอกว่าต้องการค้นหาข้อมูลจากเว็บ (ไม่รวม weather → ใช้ Open-Meteo แทน)
  static final List<RegExp> _searchPatterns = [
    // ภาษาไทย
    RegExp(r'ค้นหา(.+)', caseSensitive: false),
    RegExp(r'หา(.+)ให้หน่อย', caseSensitive: false),
    RegExp(r'หา(.+)ให้ที', caseSensitive: false),
    RegExp(r'(.+)คืออะไร', caseSensitive: false),
    RegExp(r'(.+)หมายความว่าอะไร', caseSensitive: false),
    RegExp(r'ข่าว(.+)', caseSensitive: false),
    RegExp(r'ราคา(.+)', caseSensitive: false),
    RegExp(r'วิธี(.+)', caseSensitive: false),
    RegExp(r'สูตร(.+)', caseSensitive: false),
    // English patterns
    RegExp(r'(?:search|find|look up|look for|search for)\s+(.+)', caseSensitive: false),
    RegExp(r'what\s+is\s+(.+)', caseSensitive: false),
    RegExp(r'how\s+(?:to|do)\s+(.+)', caseSensitive: false),
    RegExp(r'where\s+(?:is|are|can\s+i\s+find)\s+(.+)', caseSensitive: false),
    RegExp(r'(.+)\s+near(?:by|\s+me)\b', caseSensitive: false),
  ];

  /// คำที่บ่งบอกว่าถามเรื่องอากาศ → ใช้ WeatherService (Open-Meteo) แทน web search
  static final RegExp _weatherPattern = RegExp(
    r'อากาศ|ฝนตก|ฝนจะ|ฟ้า|ร้อน.*วันนี้|หนาว.*วันนี้|พยากรณ์|สภาพอากาศ|'
    r'weather|forecast|จะฝน|จะร้อน|จะหนาว|มีฝน|ลมแรง|พายุ',
    caseSensitive: false,
  );

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

    // 2.1 🌤️ Weather Worker — ใช้ Open-Meteo แทน web search (เร็วกว่า + ไม่ถูก block)
    if (_weatherPattern.hasMatch(userMessage)) {
      debugPrint('🌤️ Weather intent detected, fetching forecast...');
      try {
        final ctx = await WeatherService()
            .getContextString()
            .timeout(const Duration(seconds: 8));
        if (ctx != null) {
          enrichedContext = '$ctx\n$enrichedContext';
          intent = DetectedIntent.weather;
          debugPrint('🌤️ Weather context injected');
        }
      } catch (e) {
        debugPrint('⚠️ Weather fetch skipped: $e');
      }
    }

    // 2.5 ⚡ Fast Path: SQL LIKE search (0 LLM, ทันที)
    // ถ้า user ถามเรื่องเก่า เช่น "เคยไปทะเลเมื่อไหร่" → หา entry ดิบด้วย keyword
    // ถ้า SQL ไม่เจอ → escalate to RAGService (semantic, language-agnostic)
    final pastDataKeyword = _extractPastDataKeyword(userMessage);
    if (pastDataKeyword != null) {
      final filters = _extractPastFilters(userMessage);
      try {
        final found = await DatabaseHelper.instance
            .searchEntries(pastDataKeyword)
            .timeout(const Duration(seconds: 2));
        final matched = _filterEntries(found, filters);
        if (matched.isNotEmpty) {
          enrichedContext = 'Related entries:\n${_buildEntrySnippets(matched.take(2).toList(), filters)}\n$enrichedContext';
          debugPrint('⚡ Fast Path: found ${matched.length} entries for "$pastDataKeyword"');
        } else if (RAGService().isInitialized) {
          // SQL miss → semantic RAG fallback (รองรับ English query → Thai content)
          debugPrint('🔍 Fast Path miss → RAG: "$pastDataKeyword"');
          try {
            final ragResults = await RAGService()
                .search(pastDataKeyword, limit: 3)
                .timeout(const Duration(seconds: 5));
            final ragMatched = ragResults
                .where((r) => _matchFilters(r.entry, filters))
                .map((r) => r.entry)
                .toList();
            if (ragMatched.isNotEmpty) {
              enrichedContext = 'Related entries:\n${_buildEntrySnippets(ragMatched.take(2).toList(), filters)}\n$enrichedContext';
              debugPrint('✅ RAG fallback: ${ragMatched.length} entries');
            }
          } catch (e) {
            debugPrint('⚠️ RAG fallback failed: $e');
          }
        }
      } catch (_) {}
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

      // 🔍 Conflict check — ถ้า detect schedule intent ให้ตรวจ overlap + เสนอ slot ว่าง (2.11)
      if (intent == DetectedIntent.schedule &&
          workerResults.calendarEvents.isNotEmpty) {
        final first = workerResults.calendarEvents.first;
        final timeStr = first.time != null
            ? '${first.time!.hour.toString().padLeft(2, '0')}:${first.time!.minute.toString().padLeft(2, '0')}'
            : null;
        final eventInfo = EventInfo(
          title: first.title,
          date: first.date,
          time: timeStr,
          originalText: '',
        );
        try {
          final scheduler = SchedulerService();
          final conflict = await scheduler
              .checkConflicts(eventInfo)
              .timeout(const Duration(seconds: 3));
          if (conflict.hasConflict) {
            final names = conflict.conflicts
                .map((e) => e['title'] as String? ?? 'กิจกรรม')
                .join(', ');
            final freeSlot = await scheduler
                .findNextFreeSlot(
                    conflict.proposedStart, eventInfo.durationMinutes)
                .timeout(const Duration(seconds: 3));
            final slotStr = freeSlot != null
                ? '[FreeSlot:${freeSlot.hour.toString().padLeft(2, '0')}:${freeSlot.minute.toString().padLeft(2, '0')}]'
                : '';
            contextParts.add('[Conflict:$names]$slotStr');
            debugPrint('⚠️ Conflict: $names | FreeSlot: $freeSlot');
          }
        } catch (e) {
          debugPrint('⚠️ Conflict check skipped: $e');
        }
      }

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

  /// 🔄 Update last AI lean entry with English (Secret Chat output, async)
  void updateLeanContextWithEnglish(String englishSummary) {
    _leanContext.updateLastPairWithEnglish(englishSummary);
  }

  /// 🔄 Update last USER lean entry with English (from preClassify, instant)
  /// เรียกทันทีหลัง preClassify returns — ไม่ต้องรอ SecretChat async
  void updateUserMessageWithEnglish(String englishSummary) {
    _leanContext.updateLastUserMessageWithEnglish(englishSummary);
  }

  /// 📊 Get Lean Context stats
  Map<String, dynamic> getLeanContextStats() => _leanContext.getSessionInfo();

  /// 🗑️ Clear lean context (messages + session summaries)
  Future<void> clearLeanContext() => _leanContext.clearAll();

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
    final searchKeywords = ['อากาศ', 'ข่าว', 'ราคา', 'หุ้น', 'สกุลเงิน', 'news', 'price', 'stock', 'nearby', 'near me', 'ใกล้ฉัน', 'ใกล้ที่นี่', 'ใกล้บ้าน', 'แถวนี้', 'ในละแวก'];
    for (final keyword in searchKeywords) {
      if (lower.contains(keyword)) {
        return message;
      }
    }

    return null;
  }

  /// ⚡ ดึง keyword สำหรับ Fast Path SQL search
  ///
  /// ตรวจจับว่า user ถามเรื่องข้อมูลเก่า เช่น "เคยไปทะเล", "ตอนนั้นกินอะไร"
  /// Returns: keyword ที่จะใช้ LIKE search, หรือ null ถ้าไม่ใช่คำถามเรื่องเก่า
  String? _extractPastDataKeyword(String message) {
    // pattern บ่งบอกว่าถามเรื่องอดีต/ข้อมูลเก่า
    final pastPatterns = [
      // ภาษาไทย
      RegExp(r'เคย(.+)', caseSensitive: false),
      RegExp(r'ตอน(?:นั้น|ก่อน|ที่แล้ว)(.+)', caseSensitive: false),
      RegExp(r'ครั้งที่แล้ว(.*)'),
      RegExp(r'(.+)เมื่อไ(?:หร่|ร)'),
      RegExp(r'(.+)วันไหน'),
      RegExp(r'จำได้ไหม(.+)', caseSensitive: false),
      // English — captures the subject/object as search keyword
      RegExp(r'(?:did|have)\s+i\s+ever\s+(.+?)[\?\.]*$', caseSensitive: false),
      RegExp(r'when\s+did\s+i\s+(.+?)[\?\.]*$', caseSensitive: false),
      RegExp(r'where\s+did\s+i\s+(.+?)[\?\.]*$', caseSensitive: false),
      RegExp(r'what\s+did\s+i\s+(.+?)[\?\.]*$', caseSensitive: false),
      RegExp(r'last\s+time\s+(?:i\s+)?(.+?)[\?\.]*$', caseSensitive: false),
      RegExp(r'do\s+you\s+remember\s+(?:when\s+i\s+|what\s+i\s+)?(.+?)[\?\.]*$', caseSensitive: false),
      RegExp(r'have\s+i\s+(?:been\s+to|visited|gone\s+to)\s+(.+?)[\?\.]*$', caseSensitive: false),
    ];

    for (final pattern in pastPatterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        // ดึง capture group แรก ถ้ามี
        final captured = match.groupCount > 0
            ? (match.group(1) ?? '').trim()
            : message;
        if (captured.length >= 2) return captured;
        return message.trim();
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

  // ============================================================
  // 🔍 PAST DATA FILTER HELPERS
  // ============================================================

  /// ดึง date/mood filters จาก user message (Thai + English)
  _PastDataFilters _extractPastFilters(String message) {
    final lower = message.toLowerCase();
    final now = DateTime.now();
    DateTime? dateFrom;
    DateTime? dateTo;
    int? minMood;
    int? maxMood;

    // Date filters
    if (lower.contains('เมื่อปีที่แล้ว') || lower.contains('ปีที่แล้ว') || lower.contains('last year')) {
      dateFrom = DateTime(now.year - 1, 1, 1);
      dateTo = DateTime(now.year, 1, 1);
    } else if (lower.contains('เดือนที่แล้ว') || lower.contains('last month')) {
      dateFrom = DateTime(now.year, now.month - 1, 1);
      dateTo = DateTime(now.year, now.month, 1);
    } else if (lower.contains('ปีนี้') || lower.contains('this year')) {
      dateFrom = DateTime(now.year, 1, 1);
    } else if (lower.contains('เดือนนี้') || lower.contains('this month')) {
      dateFrom = DateTime(now.year, now.month, 1);
    } else if (lower.contains('ช่วงนี้') || lower.contains('recently') || lower.contains('lately')) {
      dateFrom = now.subtract(const Duration(days: 30));
    }

    // Mood filters
    if (RegExp(r'มีความสุข|อารมณ์ดี|สนุก|ดีใจ|happy|good mood|joyful', caseSensitive: false).hasMatch(lower)) {
      minMood = 4;
    } else if (RegExp(r'เครียด|เศร้า|ซึมเซา|อารมณ์ไม่ดี|stressed|sad|bad mood|depressed', caseSensitive: false).hasMatch(lower)) {
      maxMood = 2;
    }

    return _PastDataFilters(dateFrom: dateFrom, dateTo: dateTo, minMood: minMood, maxMood: maxMood);
  }

  /// ตรวจว่า entry ผ่าน filter ไหม
  bool _matchFilters(Entry entry, _PastDataFilters filters) {
    if (!filters.hasFilters) return true;
    if (filters.dateFrom != null && entry.createdAt.isBefore(filters.dateFrom!)) return false;
    if (filters.dateTo != null && entry.createdAt.isAfter(filters.dateTo!)) return false;
    if (filters.minMood != null && (entry.mood == null || entry.mood! < filters.minMood!)) return false;
    if (filters.maxMood != null && (entry.mood == null || entry.mood! > filters.maxMood!)) return false;
    return true;
  }

  /// กรอง entries ตาม filters
  List<Entry> _filterEntries(List<Entry> entries, _PastDataFilters filters) {
    if (!filters.hasFilters) return entries;
    return entries.where((e) => _matchFilters(e, filters)).toList();
  }

  /// สร้าง snippet string สำหรับ context (พร้อม mood label ถ้า mood filter เปิดอยู่)
  String _buildEntrySnippets(List<Entry> entries, _PastDataFilters filters) {
    return entries.map((e) {
      final date = e.createdAt.toString().substring(0, 10);
      final preview = e.content.length > 80 ? '${e.content.substring(0, 80)}...' : e.content;
      final moodLabel = (filters.minMood != null || filters.maxMood != null) && e.mood != null
          ? ' [mood:${e.mood}]'
          : '';
      return '[$date$moodLabel] $preview';
    }).join('\n');
  }

  bool _isGreeting(String lower) {
    final greetings = ['สวัสดี', 'หวัดดี', 'ดีจ้า', 'hello', 'hi ', 'hey'];
    return greetings.any((g) => lower.startsWith(g) || lower == g);
  }
}

// ============================================================
// 🔍 PAST DATA FILTERS
// ============================================================

/// Date/mood filters สำหรับ Fast Path + RAG past-data search
class _PastDataFilters {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int? minMood; // mood >= minMood (e.g. 4 = happy)
  final int? maxMood; // mood <= maxMood (e.g. 2 = stressed)

  const _PastDataFilters({this.dateFrom, this.dateTo, this.minMood, this.maxMood});

  bool get hasFilters => dateFrom != null || dateTo != null || minMood != null || maxMood != null;
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

  /// สร้าง Brain-Dump summary string สำหรับแสดงใน UI card
  /// Format: "จดได้ N รายการ\n📅 X · พรุ่งนี้ 13:00\n⏰ Y · ทุกวัน"
  String buildBrainDumpSummary() {
    final lines = <String>[];

    for (final e in calendarEvents) {
      final dateStr = _formatEventDate(e.date);
      final timeStr = e.time != null
          ? ' ${e.time!.hour.toString().padLeft(2, '0')}:${e.time!.minute.toString().padLeft(2, '0')}'
          : '';
      lines.add('📅 ${e.title} · $dateStr$timeStr');
    }

    for (final r in reminders) {
      final timeStr = r.time != null
          ? ' · ${r.time!.hour.toString().padLeft(2, '0')}:${r.time!.minute.toString().padLeft(2, '0')}'
          : '';
      final freqStr = r.frequency == ReminderFrequency.daily ? ' · ทุกวัน' : '';
      lines.add('⏰ ${r.content}$timeStr$freqStr');
    }

    for (final g in goals) {
      lines.add('🎯 ${g.title}');
    }

    if (lines.isEmpty) return '';
    return 'จดได้ ${lines.length} รายการ\n${lines.join('\n')}';
  }

  static String _formatEventDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = date.difference(today).inDays;
    if (diff == 0) return 'วันนี้';
    if (diff == 1) return 'พรุ่งนี้';
    return '${date.day}/${date.month}';
  }
}

/// Intent ที่ตรวจจับได้
enum DetectedIntent {
  general,
  search,
  weather,
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
