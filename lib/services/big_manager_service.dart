import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'unified_task_service.dart';

import 'workers/calendar_worker.dart';
import 'workers/correlation_worker.dart';
import 'workers/fact_worker.dart';
import 'workers/reminder_worker.dart';
import 'workers/goal_worker.dart';
import 'workers/health_doctor.dart';
import 'chat_summary_service.dart';
import 'insight_notification_service.dart';
import 'user_profile_service.dart';
import 'web_search_service.dart';

/// 👔 Big Manager Service - วิเคราะห์ข้อความและจัดการงาน (รวมจาก ManagerSummaryStrategy + AIActionService)
///
/// หน้าที่:
/// 1. วิเคราะห์ข้อความผู้ใช้เป็น structured data (JSON)
/// 2. Dispatch งานไปยัง workers ต่างๆ (ผ่าน UnifiedTaskService)
/// 3. จัดการ priority queue สำหรับงานที่ต้องใช้ LLM
///
/// Output format จาก LLM:
/// {
///   "intent": "schedule|reminder|query|fact|chat",
///   "calendar": {"title": "...", "date": "...", "time": "..."},
///   "reminder": {"content": "...", "time": "...", "frequency": "..."},
///   "fact": {"type": "like|dislike|goal|place", "value": "..."},
///   "location": {"name": "...", "action": "save|search"},
///   "web_search": {"query": "..."},
///   "response": "ข้อความตอบกลับผู้ใช้"
/// }

class BigManagerService {
  static final BigManagerService _instance = BigManagerService._internal();
  factory BigManagerService() => _instance;
  BigManagerService._internal();

  final UnifiedTaskService _taskService = UnifiedTaskService();
  final CalendarWorker _calendarWorker = CalendarWorker();
  final ReminderWorker _reminderWorker = ReminderWorker();
  final FactWorker _factWorker = FactWorker();
  final GoalWorker _goalWorker = GoalWorker();
  final HealthDoctor _healthDoctor = HealthDoctor();
  final CorrelationWorker _correlationWorker = CorrelationWorker();
  final InsightNotificationService _insightNotification = InsightNotificationService();
  final ChatSummaryService _chatSummary = ChatSummaryService();
  final UserProfileService _userProfile = UserProfileService();
  final WebSearchService _webSearch = WebSearchService();

  bool _isInitialized = false;

  // Keyword patterns for search detection
  static final List<RegExp> _searchPatterns = [
    RegExp(r'ค้นหา(.+)', caseSensitive: false),
    RegExp(r'หา(.+)ให้หน่อย', caseSensitive: false),
    RegExp(r'หา(.+)ให้ที', caseSensitive: false),
    RegExp(r'(.+)คืออะไร', caseSensitive: false),
    RegExp(r'(.+)หมายความว่าอะไร', caseSensitive: false),
    RegExp(r'อากาศ(.*)วันนี้', caseSensitive: false),
    RegExp(r'ข่าว(.+)', caseSensitive: false),
    RegExp(r'ราคา(.+)', caseSensitive: false),
  ];

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _calendarWorker.initialize();
    await _reminderWorker.initialize();
    await _taskService.initialize();

    _isInitialized = true;
    debugPrint('✅ BigManagerService initialized');
  }

  // ============================================================
  // 🧠 MAIN ANALYSIS (Priority 2)
  // ============================================================

  /// 👔 วิเคราะห์ข้อความผู้ใช้และ dispatch งาน (ใช้ LLM - Priority 2)
  ///
  /// Returns: ข้อความที่จะแสดงผู้ใช้ (จาก field "response")
  Future<String> analyzeAndDispatch(String userMessage) async {
    debugPrint('👔 BigManager: Analyzing "$userMessage"');

    try {
      // 1. วิเคราะห์ด้วย LLM (Priority 2)
      final analysis = await _analyzeWithLLM(userMessage);

      // 2. Dispatch งานตามผลลัพธ์ (Code - ไม่ใช้ LLM)
      await _dispatchFromAnalysis(analysis, userMessage);

      // 3. คืนค่าข้อความตอบกลับ
      return analysis.response ?? 'รับทราบค่ะ';
    } catch (e) {
      debugPrint('❌ BigManager analyze error: $e');
      // Fallback: ใช้ rule-based detection
      return _fallbackDispatch(userMessage);
    }
  }

  /// 🧠 วิเคราะห์ด้วย LLM (Priority 2)
  Future<_AnalysisResult> _analyzeWithLLM(String userMessage) async {
    final prompt = _buildAnalysisPrompt(userMessage);

    // ใช้ Unified Task (Priority 2)
    final response = await _taskService.llmPrompt(prompt, priority: UnifiedTaskService.priorityHigh);

    return _parseAnalysisResponse(response);
  }

  /// 📝 สร้าง prompt สำหรับวิเคราะห์
  String _buildAnalysisPrompt(String userMessage) {
    final now = DateTime.now().toString().substring(0, 16);

    return '''<start_of_turn>user
You are Haku's Big Manager. Analyze this Thai message and extract structured data.

Current DateTime: $now

User message: "$userMessage"

Analyze and return JSON ONLY:
{
  "intent": "schedule|reminder|fact|location|web_search|chat",
  "calendar": {
    "has_event": false,
    "title": "",
    "date": "YYYY-MM-DD",
    "time": "HH:MM",
    "location": ""
  },
  "reminder": {
    "has_reminder": false,
    "content": "",
    "time": "HH:MM",
    "frequency": "once|daily|weekly"
  },
  "fact": {
    "has_fact": false,
    "type": "like|dislike|goal|place|name|role",
    "value": ""
  },
  "location": {
    "has_location": false,
    "name": "",
    "action": "save|search"
  },
  "web_search": {
    "needs_search": false,
    "query": ""
  },
  "correlation": {
    "needs_analysis": false,
    "scope": "quick|full",  // quick = 14 days, full = 30 days
    "focus": ""  // optional: sleep, health, mood, etc.
  },
  "response": "Thai acknowledgment message (1 sentence, friendly)"
}

Rules:
- "วันนี้" = ${DateTime.now().toIso8601String().split('T')[0]}
- "พรุ่งนี้" = ${DateTime.now().add(const Duration(days: 1)).toIso8601String().split('T')[0]}
- "10 โมง" = "10:00", "บ่าย 2" = "14:00"
- If user mentions cafe/restaurant/place → location.action = "search"
- If user says "ชอบ/ไม่ชอบ" → fact.type = "like/dislike"
- If user asks "หา/ค้นหา" about general info → web_search.needs_search = true
- If user asks about patterns/insights/correlations (e.g., "หา correlation", "วิเคราะห์", "มีอะไรแปลก", "ทำไมฉันถึง") → correlation.needs_analysis = true<end_of_turn>
<start_of_turn>model
''';}

  /// 📋 Parse ผลลัพธ์จาก LLM
  _AnalysisResult _parseAnalysisResponse(String response) {
    try {
      // Clean response
      var clean = response.trim();
      if (clean.contains('```json')) {
        clean = clean.split('```json')[1].split('```')[0].trim();
      } else if (clean.contains('```')) {
        clean = clean.split('```')[1].split('```')[0].trim();
      }

      final json = jsonDecode(clean) as Map<String, dynamic>;

      return _AnalysisResult(
        intent: json['intent'] as String? ?? 'chat',
        calendar: json['calendar'] as Map<String, dynamic>?,
        reminder: json['reminder'] as Map<String, dynamic>?,
        fact: json['fact'] as Map<String, dynamic>?,
        location: json['location'] as Map<String, dynamic>?,
        webSearch: json['web_search'] as Map<String, dynamic>?,
        correlation: json['correlation'] as Map<String, dynamic>?,
        response: json['response'] as String?,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to parse analysis: $e');
      return const _AnalysisResult(intent: 'chat');
    }
  }

  // ============================================================
  // 🔧 DISPATCHER (Code - No LLM)
  // ============================================================

  /// 🔧 Dispatch งานตามผลวิเคราะห์ (ไม่ใช้ LLM)
  Future<void> _dispatchFromAnalysis(_AnalysisResult analysis, String originalMessage) async {
    debugPrint('🔧 Dispatcher: intent=${analysis.intent}');

    // 1. Calendar (Priority: Normal)
    if (analysis.calendar != null && analysis.calendar!['has_event'] == true) {
      await _dispatchCalendar(analysis.calendar!);
    }

    // 2. Reminder (Priority: High)
    if (analysis.reminder != null && analysis.reminder!['has_reminder'] == true) {
      await _dispatchReminder(analysis.reminder!);
    }

    // 3. Fact (Priority: Normal)
    if (analysis.fact != null && analysis.fact!['has_fact'] == true) {
      await _dispatchFact(analysis.fact!);
    }

    // 4. Location (Priority: Normal)
    if (analysis.location != null && analysis.location!['has_location'] == true) {
      await _dispatchLocation(analysis.location!);
    }

    // 5. Web Search (Priority: High - user waiting)
    if (analysis.webSearch != null && analysis.webSearch!['needs_search'] == true) {
      await _dispatchWebSearch(analysis.webSearch!, originalMessage);
    }

    // 6. Correlation Analysis (Priority: Normal - background)
    if (analysis.correlation != null && analysis.correlation!['needs_analysis'] == true) {
      await _dispatchCorrelation(analysis.correlation!);
    }

    // 7. Fallback: Rule-based detection ถ้า LLM ไม่จับอะไรเลย
    if (analysis.intent == 'chat') {
      await _fallbackRuleBasedDispatch(originalMessage);
    }
  }

  /// 📅 Dispatch Calendar
  Future<void> _dispatchCalendar(Map<String, dynamic> data) async {
    debugPrint('📅 Dispatch calendar: ${data['title']}');

    await _taskService.enqueue(
      type: TaskType.calendar,
      payload: {
        'title': data['title'],
        'date': data['date'],
        'time': data['time'],
        'location': data['location'],
      },
      priority: UnifiedTaskService.priorityNormal,
    );
  }

  /// 🔔 Dispatch Reminder
  Future<void> _dispatchReminder(Map<String, dynamic> data) async {
    debugPrint('🔔 Dispatch reminder: ${data['content']}');

    await _taskService.enqueue(
      type: TaskType.reminder,
      payload: {
        'content': data['content'],
        'time': data['time'],
        'frequency': data['frequency'],
      },
      priority: UnifiedTaskService.priorityNormal,
    );
  }

  /// 📝 Dispatch Fact
  Future<void> _dispatchFact(Map<String, dynamic> data) async {
    debugPrint('📝 Dispatch fact: ${data['type']} = ${data['value']}');

    await _taskService.enqueue(
      type: TaskType.fact,
      payload: {
        'type': data['type'],
        'value': data['value'],
      },
      priority: UnifiedTaskService.priorityLow,
    );
  }

  /// 📍 Dispatch Location
  Future<void> _dispatchLocation(Map<String, dynamic> data) async {
    debugPrint('📍 Dispatch location: ${data['name']} (${data['action']})');

    await _taskService.enqueue(
      type: TaskType.location,
      payload: {
        'name': data['name'],
        'action': data['action'],
      },
      priority: UnifiedTaskService.priorityNormal,
    );
  }

  /// 🌐 Dispatch Web Search
  Future<void> _dispatchWebSearch(Map<String, dynamic> data, String originalMessage) async {
    final query = data['query'] as String? ?? originalMessage;
    debugPrint('🌐 Dispatch web search: $query');

    await _taskService.enqueue(
      type: TaskType.webSearch,
      payload: {
        'query': query,
        'original_message': originalMessage,
      },
      priority: UnifiedTaskService.priorityHigh,
    );
  }

  /// 🔮 Dispatch Correlation Analysis
  Future<void> _dispatchCorrelation(Map<String, dynamic> data) async {
    final scope = data['scope'] as String? ?? 'quick';
    debugPrint('🔮 Dispatch correlation analysis: scope=$scope');

    // Run in background via task service
    await _taskService.enqueue(
      type: TaskType.correlation,
      payload: {
        'scope': scope,
        'focus': data['focus'] ?? '',
      },
      priority: UnifiedTaskService.priorityLow, // Background task
    );
  }

  /// 🔮 วิเคราะห์ correlation และตอบกลับทันที (สำหรับ chat)
  Future<String> analyzeAndRespondWithCorrelation(String userMessage) async {
    debugPrint('🔮 BigManager: Running correlation for chat');

    try {
      // 1. วิเคราะห์แบบเร็วก่อน
      final result = await _correlationWorker.runQuickAnalysis();
      
      if (result == null || result.insights.isEmpty) {
        return 'ยังไม่พบความเชื่อมโยงที่ชัดเจนค่ะ ลองบันทึกเพิ่มอีกสักพัก หรือให้ฉันวิเคราะห์แบบเต็มรูปแบบตอนชาร์จแบตนะคะ 🔋';
      }

      // 2. ใช้ Gemma สรุปผล
      final topInsights = result.interestingInsights.take(3).toList();
      String response;
      
      if (topInsights.isNotEmpty) {
        final insight = topInsights.first;
        final recommendation = insight.getRecommendation();
        
        response = 'พบความเชื่อมโยงที่น่าสนใจค่ะ!\n\n';
        response += '${insight.description}\n';
        
        if (recommendation != null) {
          response += '\n💡 $recommendation';
        }
        
        if (topInsights.length > 1) {
          response += '\n\n(พบอีก ${topInsights.length - 1} รายการ ดูได้ที่ Insights)';
        }
      } else {
        response = 'ยังไม่พบความเชื่อมโยงที่แน่นอนพอค่ะ เก็บข้อมูลอีกสัก ${10 - result.totalDaysAnalyzed} วันจะได้ผลที่แม่นยำกว่านะคะ 📊';
      }

      // 3. แจ้งเตือนถ้ามี insight สำคัญ
      final healthInsights = result.healthRelatedInsights
          .where((i) => i.confidence > 0.7)
          .toList();
      
      if (healthInsights.isNotEmpty) {
        await _insightNotification.notifyHealthInsight(healthInsights.first);
      }

      return response;

    } catch (e) {
      debugPrint('❌ Correlation analysis error: $e');
      return 'ขอโทษค่ะ วิเคราะห์ไม่สำเร็จ ลองใหม่ภายหลังนะคะ 🙏';
    }
  }

  /// 🔮 ดึง insights มาตอบคำถาม (RAG-based)
  Future<String> queryInsights(String question) async {
    debugPrint('🔮 Querying insights for: "$question"');

    try {
      // ค้นหา insights ที่เกี่ยวข้อง
      final relatedInsights = await _correlationWorker.findInsights(question);
      
      if (relatedInsights.isEmpty) {
        return 'ยังไม่มีข้อมูลความเชื่อมโยงที่เกี่ยวข้องค่ะ ลองวิเคราะห์ดูไหมคะ? 🔮';
      }

      // เรียงตามความน่าสนใจ
      relatedInsights.sort((a, b) => 
          (b.confidence * b.correlation.abs()).compareTo(a.confidence * a.correlation.abs()));

      final topInsight = relatedInsights.first;
      String response = 'จากการวิเคราะห์ข้อมูล ${topInsight.sampleSize} วัน พบว่า:\n\n';
      response += topInsight.description;
      
      final recommendation = topInsight.getRecommendation();
      if (recommendation != null) {
        response += '\n\n💡 $recommendation';
      }

      return response;

    } catch (e) {
      debugPrint('❌ Query insights error: $e');
      return 'ขอโทษค่ะ ไม่สามารถดึงข้อมูลได้ตอนนี้ 🙏';
    }
  }

  // ============================================================
  // 🔄 FALLBACK: Rule-based Detection
  // ============================================================

  /// Fallback ถ้า LLM fail
  String _fallbackDispatch(String message) {
    // ใช้ workers ตรวจจับแบบ rule-based
    _calendarWorker.detectEvents(message);
    _reminderWorker.detectReminders(message);
    _factWorker.processMessage(message);

    return 'รับทราบค่ะ';
  }

  /// Rule-based ถ้า LLM ไม่จับอะไรแต่เราอยากลองดู
  Future<void> _fallbackRuleBasedDispatch(String message) async {
    // Calendar
    final events = await _calendarWorker.detectEvents(message);
    if (events.isNotEmpty) {
      debugPrint('📅 Fallback detected ${events.length} events');
    }

    // Reminder
    final reminders = await _reminderWorker.detectReminders(message);
    if (reminders.isNotEmpty) {
      debugPrint('🔔 Fallback detected ${reminders.length} reminders');
    }

    // Fact
    final facts = await _factWorker.processMessage(message);
    if (facts.isNotEmpty) {
      debugPrint('📝 Fallback detected ${facts.length} facts');
    }
  }

  // ============================================================
  // 🎭 THE FACE - Quick Acknowledgment
  // ============================================================

  /// 🎭 สร้างข้อความตอบรับทันที (ไม่ต้องรอ LLM)
  String generateAcknowledgment(String userMessage) {
    // ตรวจจับ intent ง่ายๆ แล้วตอบตามนั้น
    final lower = userMessage.toLowerCase();

    if (lower.contains('นัด') || lower.contains('ไป') || lower.contains('ประชุม')) {
      return 'รับทราบค่ะ กำลังบันทึกนัดหมายให้นะคะ 📝';
    }
    if (lower.contains('เตือน') || lower.contains('อย่าลืม')) {
      return 'เตือนแล้วค่ะ! จะแจ้งเตือนตามที่ขอเลย ⏰';
    }
    if (lower.contains('ชอบ') || lower.contains('ไม่ชอบ')) {
      return 'จำไว้แล้วค่ะ ขอบคุณที่บอกนะ 😊';
    }
    if (lower.contains('หา') || lower.contains('ค้นหา') || lower.contains('ร้าน')) {
      return 'กำลังหาข้อมูลให้นะคะ 🔍';
    }

    return 'รับทราบค่ะ';
  }

  // ============================================================
  // 🧠 PREPROCESSING (จาก SmartPreprocessor)
  // ============================================================

  /// 🧠 Preprocess ข้อความก่อนส่งให้ LLM
  Future<PreprocessResult> preprocess(String userMessage) async {
    debugPrint('🧠 Preprocessing: "$userMessage"');

    String enrichedContext = '';
    DetectedIntent intent = DetectedIntent.general;

    // 0. Initialize services
    await Future.wait([
      _chatSummary.initialize(),
      _calendarWorker.initialize(),
      _reminderWorker.initialize(),
      _goalWorker.initialize(),
      _healthDoctor.initialize(),
    ]);

    // 1. Run rule-based detection
    final calendarEvents = await _calendarWorker.detectEvents(userMessage);
    final reminders = await _reminderWorker.detectReminders(userMessage);
    await _factWorker.processMessage(userMessage);
    await _goalWorker.detectGoals(userMessage);
    await _healthDoctor.detectHealth(userMessage);

    if (calendarEvents.isNotEmpty) intent = DetectedIntent.schedule;
    if (reminders.isNotEmpty) intent = DetectedIntent.reminder;

    // 2. Detect search intent
    final searchQuery = _detectSearchIntent(userMessage);
    if (searchQuery != null) {
      intent = DetectedIntent.search;
      try {
        final searchResult = await _webSearch.searchForAI(searchQuery);
        if (searchResult.isNotEmpty) {
          enrichedContext += '\n\n📊 ข้อมูลจากการค้นหา:\n$searchResult';
        }
      } catch (e) {
        debugPrint('⚠️ Web search failed: $e');
      }
    }

    // 3. Build context
    final chatContext = await _chatSummary.getContextForAI();
    final identity = _userProfile.getIdentityCard();

    final contextParts = <String>[];
    if (identity.isNotEmpty) contextParts.add(identity);
    contextParts.add(chatContext);
    enrichedContext = '${contextParts.join("\n")}\n$enrichedContext';

    return PreprocessResult(
      enrichedContext: enrichedContext.trim(),
      detectedIntent: intent,
      searchQuery: searchQuery,
    );
  }

  /// 🔍 Detect search intent
  String? _detectSearchIntent(String message) {
    final lower = message.toLowerCase();

    for (final pattern in _searchPatterns) {
      final match = pattern.firstMatch(lower);
      if (match != null) {
        if (match.groupCount > 0 && match.group(1)?.isNotEmpty == true) {
          return match.group(1)!.trim();
        }
        return message;
      }
    }

    final searchKeywords = ['อากาศ', 'ข่าว', 'ราคา', 'หุ้น'];
    for (final keyword in searchKeywords) {
      if (lower.contains(keyword)) return message;
    }

    return null;
  }

  /// ⚡ Detect quick action (no LLM needed)
  QuickAction? detectQuickAction(String message) {
    final lower = message.toLowerCase();

    // Greeting
    final greetings = ['สวัสดี', 'หวัดดี', 'ดีจ้า', 'hello', 'hi '];
    if (greetings.any((g) => lower.startsWith(g))) {
      final userName = _userProfile.name;
      final response = userName.isNotEmpty
          ? 'สวัสดีค่ะ คุณ$userName! วันนี้เป็นอย่างไรบ้างคะ? 😊'
          : 'สวัสดีค่ะ! ยินดีที่ได้พบ วันนี้เป็นอย่างไรบ้างคะ? 😊';
      return QuickAction(type: QuickActionType.greeting, response: response);
    }

    // Ask AI name
    if (lower.contains('ชื่ออะไร') && (lower.contains('เธอ') || lower.contains('คุณ'))) {
      return QuickAction(
        type: QuickActionType.askAIName,
        response: 'ฉันชื่อ Haku ค่ะ (箱 แปลว่า "กล่อง" ในภาษาญี่ปุ่น) ยินดีที่ได้รู้จักค่ะ! 📦✨',
      );
    }

    // Ask user name
    if ((lower.contains('ฉันชื่ออะไร') || lower.contains('ฉันคือใคร')) && _userProfile.name.isNotEmpty) {
      return QuickAction(
        type: QuickActionType.askUserName,
        response: 'คุณชื่อ ${_userProfile.name} ค่ะ! จำได้แม่นเลย 😊',
      );
    }

    return null;
  }

  /// ➕ Add message to chat history
  Future<void> addToChatHistory(String content, {required bool isUser}) async {
    await _chatSummary.initialize();
    await _chatSummary.addMessage(
      role: isUser ? 'user' : 'assistant',
      content: content,
    );
  }
}

// ============================================================
// 📦 DATA MODELS (จาก SmartPreprocessor)
// ============================================================

/// Intent ที่ตรวจจับได้
enum DetectedIntent {
  general,
  search,
  schedule,
  reminder,
}

/// Quick Action
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

/// ผลลัพธ์จากการ Preprocess
class PreprocessResult {
  final String enrichedContext;
  final DetectedIntent detectedIntent;
  final String? searchQuery;

  PreprocessResult({
    required this.enrichedContext,
    required this.detectedIntent,
    this.searchQuery,
  });
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

class _AnalysisResult {
  final String intent;
  final Map<String, dynamic>? calendar;
  final Map<String, dynamic>? reminder;
  final Map<String, dynamic>? fact;
  final Map<String, dynamic>? location;
  final Map<String, dynamic>? webSearch;
  final Map<String, dynamic>? correlation;
  final String? response;

  const _AnalysisResult({
    required this.intent,
    this.calendar,
    this.reminder,
    this.fact,
    this.location,
    this.webSearch,
    this.correlation,
    this.response,
  });
}
