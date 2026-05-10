import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/context_retriever.dart';
import '../services/database_helper.dart';
import '../services/manager_dispatch_service.dart';
import '../services/mvp_trigger_service.dart';
import '../services/notification_service.dart';
import '../services/rag_service.dart';
import '../services/background_task_handlers.dart';
import '../services/chat_summary_service.dart';
import '../services/deferred_task_service.dart';
import '../services/litert_llm_provider.dart';
import '../services/llm_provider_manager.dart';
import '../services/prompt_builder.dart';
import '../services/secret_chat_service.dart';
import '../services/smart_preprocessor.dart';
import '../services/place_feedback_service.dart';
import '../services/place_service.dart';
import '../services/tag_context_service.dart';
import '../services/correlation_service.dart';
import '../services/geofence_service.dart';
import '../services/location_service.dart';
import '../services/scheduler_service.dart';
import '../services/web_search_service.dart';
import '../utils/haku_design_tokens.dart';

/// 💬 หน้าแชทกับ AI (Haku Assistant) - Phase 2: Real LLM
///
/// คุยกับ AI ที่รู้จักข้อมูลของคุณจาก Journal
/// รองรับ RAG (ค้นหาบันทึก) + LLM (ตอบคำถาม)

// Provider สำหรับเก็บประวัติแชท
final chatHistoryProvider = StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) => ChatNotifier());

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  static const String _historyKey = 'chat_history_v1';
  static const int _maxMessages = 50;

  ChatNotifier() : super([ChatMessage.welcome()]) {
    _loadHistory();
  }

  /// 📂 โหลด chat history จาก SharedPreferences ตอน startup
  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_historyKey);
      if (json != null && json.isNotEmpty) {
        final messages = ChatMessage.decodeList(json);
        if (messages.isNotEmpty) {
          state = messages;
          debugPrint('💬 Chat history loaded: ${messages.length} messages');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load chat history: $e');
    }
  }

  /// 💾 บันทึก chat history (เก็บแค่ $_maxMessages ล่าสุด)
  Future<void> _saveHistory() async {
    try {
      final persistable = state.where((m) => m.isPersistable).toList();
      final trimmed = persistable.length > _maxMessages
          ? persistable.sublist(persistable.length - _maxMessages)
          : persistable;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_historyKey, ChatMessage.encodeList(trimmed));
    } catch (e) {
      debugPrint('⚠️ Failed to save chat history: $e');
    }
  }

  void addMessage(ChatMessage message) {
    state = [...state, message];

    // 💾 บันทึก history (ข้าม loading/searching)
    if (message.isPersistable) {
      _saveHistory();
    }

    // 🔋 บันทึกประวัติแชทสำหรับสรุปแบบ Deferred (ไม่กินแบต)
    if (!message.isLoading && !message.isError) {
      ChatSummaryService().logChatMessage(
        message: message.content,
        isUser: message.isUser,
        intent: message.isProactive ? 'proactive' : 'chat',
      );
    }
  }

  /// 🗑️ ล้าง chat history + AI memory ทั้งหมด (Set Zero)
  Future<void> clearHistory() async {
    state = [ChatMessage.welcome()];
    // ล้าง UI history
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    // ล้าง secret chat English log
    await SecretChatService().clearAll();
    debugPrint('💬 Chat history + AI memory cleared (Set Zero)');
  }

  /// 🔧 Extract response text from JSON or plain text
  String _extractResponseText(String response) {
    // 🧹 ทำความสะอาดก่อนเสมอ (ตัด template leak + dialogue hallucination)
    var cleaned = PromptBuilder.cleanResponse(response);

    // ลบ Markdown code block ถ้ามี
    if (cleaned.startsWith('```json')) cleaned = cleaned.substring(7);
    if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.length - 3);
    cleaned = cleaned.trim();

    // ลอง parse JSON (Worker prompts return JSON, Face prompt returns plain text)
    try {
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      if (json.containsKey('response')) return json['response'] as String;
      return cleaned;
    } catch (_) {
      // plain text — return cleaned (ไม่ return raw เพื่อกันรั่ว dialogue)
      return cleaned;
    }
  }

  /// 🤖 ส่งข้อความไปให้ AI — Two-Stage Architecture
  ///
  /// Stage 1 (The Face): ตอบสนทนาไทยธรรมชาติ พร้อม context/RAG
  /// Stage 2 (Big Manager): lean classify + dispatch งาน urgent/deferred
  Future<void> sendToAI(String userMessage, {bool useContext = true}) async {
    debugPrint('🚀 ============================================');
    debugPrint('🚀 sendToAI called: $userMessage');

    // เพิ่มข้อความผู้ใช้
    addMessage(ChatMessage.user(userMessage));

    // แสดง "กำลังพิมพ์..."
    addMessage(ChatMessage.loading());

    String? response;

    try {
      String contextStr = '';
      PreprocessResult? preprocessResult;

      // ──────────────────────────────────────────────────────
      // 0. Quick Action (rule-based, 0 LLM tokens) — greeting, name, etc.
      // ──────────────────────────────────────────────────────
      final preprocessor = SmartPreprocessor();
      final quickAction = preprocessor.detectQuickAction(userMessage);
      if (quickAction != null) {
        debugPrint('⚡ Quick action: ${quickAction.type.name}');
        state = state.where((m) => !m.isLoading).toList();
        addMessage(ChatMessage.assistant(quickAction.response));
        return;
      }

      // ──────────────────────────────────────────────────────
      // 1. SmartPreprocessor (rule-based workers, 0 LLM tokens)
      // ──────────────────────────────────────────────────────
      if (useContext) {
        try {
          debugPrint('🧠 Running SmartPreprocessor...');
          preprocessResult = await preprocessor.preprocess(userMessage);
          contextStr = preprocessResult.enrichedContext;
          debugPrint('✅ Preprocessing complete:');
          debugPrint('   - Intent: ${preprocessResult.detectedIntent}');
          debugPrint('   - Context length: ${contextStr.length}');
          debugPrint('   - Worker results: ${preprocessResult.workerResults.getSummary()}');

        } catch (e, stackTrace) {
          debugPrint('⚠️ SmartPreprocessor failed: $e');
          debugPrint('Stack: $stackTrace');
          try {
            final contextData = await ContextRetriever().retrieveFullContext(
              userQuery: userMessage,
            );
            contextStr = ContextRetriever().buildContextString(contextData);
          } catch (e2) {
            debugPrint('⚠️ Fallback also failed: $e2');
          }
        }
      }

      // เตรียม LLM
      final llm = LLMProviderManager().provider;
      if (!llm.isInitialized && !llm.isLoading) {
        await llm.initialize();
      }

      // ──────────────────────────────────────────────────────
      // PATH A: Search detected by SmartPreprocessor (keyword)
      // ──────────────────────────────────────────────────────
      final needsSearch =
          preprocessResult?.detectedIntent == DetectedIntent.search;

      if (needsSearch) {
        debugPrint('🔍 Search path: showing intermediate message...');

        // แสดง intermediate message แทน loading
        state = state.where((m) => !m.isLoading).toList();
        addMessage(
            ChatMessage.searching('รับทราบค่ะ กำลังค้นหาให้นะคะ...'));

        // Execute web search
        final searchQuery = preprocessResult!.searchQuery ?? userMessage;
        ManagerDispatchService.markSearched(searchQuery); // dedup
        String? webResult;
        try {
          final webService = WebSearchService();
          await webService.initialize();

          // ตรวจว่าเป็น "nearby" query ไหม
          final lowerQuery = searchQuery.toLowerCase();
          final isNearby = lowerQuery.contains('ใกล้ฉัน') ||
              lowerQuery.contains('ใกล้ที่นี่') ||
              lowerQuery.contains('ใกล้บ้าน') ||
              lowerQuery.contains('แถวนี้') ||
              lowerQuery.contains('ในละแวก') ||
              lowerQuery.contains('nearby') ||
              lowerQuery.contains('near me');

          double? lat, lng;
          String? placesKey;

          if (isNearby) {
            // ดึง GPS + Google Places key พร้อมกัน
            final positionFuture = LocationService.getCurrentPosition();
            final prefsFuture = SharedPreferences.getInstance();
            final position = await positionFuture;
            final prefs = await prefsFuture;
            placesKey = prefs.getString('google_places_api_key');
            if (position != null) {
              lat = position.latitude;
              lng = position.longitude;
            }
          }

          webResult = await webService.searchForAI(
            searchQuery,
            lat: lat,
            lng: lng,
            googlePlacesKey: placesKey,
          );
          debugPrint('✅ Web search completed: $searchQuery');
        } catch (e) {
          debugPrint('⚠️ Web search failed: $e');
        }

        // Follow-up LLM: สรุปผลค้นหาเป็นคำตอบ
        if (llm.isInitialized &&
            webResult != null &&
            webResult.isNotEmpty) {
          try {
            final followUpPrompt =
                _buildSearchFollowUpPrompt(userMessage, webResult);
            response = await llm.generate(followUpPrompt);
            response = _extractResponseText(response);
          } catch (e) {
            debugPrint('⚠️ Follow-up generation failed: $e');
            response = webResult;
          }
        } else {
          // webResult == '' → search ran but found nothing; null → exception
          response = 'ขอโทษนะคะ ไม่พบข้อมูลที่ค้นหาได้ในขณะนี้ค่ะ ลองถามใหม่อีกครั้งนะคะ';
        }

        // Replace searching message with real response
        state = state.where((m) => !m.isSearching).toList();
        addMessage(ChatMessage.assistant(
          response,
          sources: useContext ? _extractSources(contextStr) : null,
        ));

      } else {
        // ──────────────────────────────────────────────────────
        // PATH B: General message
        //
        // 1.5: TagContextService — keyword search past entries (0 LLM)
        // 1.6: Calendar Context  — inject if schedule query (0 LLM)
        // 2:   Face LLM          — Thai natural response
        // ──────────────────────────────────────────────────────

        // 1.5. Tag Context — ดึง related past entries by keywords + location
        final tagCtx = await TagContextService().buildContext(
          userMessage: userMessage,
        );
        if (tagCtx != null && tagCtx.isNotEmpty) {
          contextStr = tagCtx + (contextStr.isNotEmpty ? '\n$contextStr' : '');
          debugPrint('🏷️ Tag context injected (${tagCtx.length} chars)');
        }

        // 1.6. Calendar Context — inject when message looks like a schedule query
        if (_isScheduleQuery(userMessage)) {
          final calCtx = await _buildCalendarContext(userMessage);
          if (calCtx.isNotEmpty) {
            contextStr = calCtx + (contextStr.isNotEmpty ? '\n$contextStr' : '');
            debugPrint('📅 Calendar context injected (${calCtx.length} chars)');
          }
        }

        // 2. Face LLM — Stage 1 (The Face)
        debugPrint('🎭 Stage 1 (The Face): generating natural response...');

        if (llm.isInitialized) {
          try {
            final isCloud = LLMProviderManager().activeType != ProviderType.onDevice;
            final ctx = contextStr.isNotEmpty ? contextStr : null;

            if (isCloud) {
              // Cloud: stateless full prompt
              final prompt = PromptBuilder.buildCloudPrompt(
                userMessage: userMessage,
                context: ctx,
              );
              response = await llm.generate(prompt).timeout(
                const Duration(seconds: 30),
                onTimeout: () { debugPrint('⏱️ Cloud LLM timeout'); return ''; },
              );
            } else {
              // On-device: stateful conversation — send only user turn, KV cache handles history
              final liteRT = llm as LiteRTLLMProvider;
              final turn = PromptBuilder.buildUserTurn(userMessage: userMessage, context: ctx);
              response = await liteRT.generateTurn(turn).timeout(
                const Duration(seconds: 120),
                onTimeout: () { debugPrint('⏱️ On-device LLM timeout'); return ''; },
              );
            }
          } catch (e) {
            debugPrint('❌ LLM generate error: $e');
            response = null;
          }
        }

        // Fallback to mock
        if (response == null || response.isEmpty) {
          response = await AIService.getMockResponse(userMessage);
        }

        var displayText = _extractResponseText(response);
        // ถ้า Gemma hallucinate dialogue ล้วน → cleanResponse คืน "" → fallback
        if (displayText.isEmpty) {
          displayText = await AIService.getMockResponse(userMessage);
        }

        // แสดงคำตอบ
        state = state.where((m) => !m.isLoading).toList();
        addMessage(ChatMessage.assistant(
          displayText,
          sources: useContext ? _extractSources(contextStr) : null,
        ));

        // Brain-Dump Summary Card (ถ้า workers จับอะไรได้)
        final brainDumpSummary = preprocessResult?.workerResults.buildBrainDumpSummary();
        if (brainDumpSummary != null && brainDumpSummary.isNotEmpty) {
          addMessage(ChatMessage.workerSummary(brainDumpSummary));
        }

        // 3. [async] Secret Chat log
        if (llm.isInitialized) {
          _runSecretChat(userMessage, displayText);
        }
      }

      debugPrint('✅ sendToAI completed successfully');
      debugPrint('🚀 ============================================');
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ CRITICAL ERROR in sendToAI: $e');
      debugPrint('Stack: $stackTrace');

      state = state
          .where((m) => !m.isLoading && !m.isSearching)
          .toList();

      addMessage(ChatMessage.error(
        'ขอโทษค่ะ เกิดข้อผิดพลาด (${e.runtimeType})\n'
        'กรุณาลองใหม่ หรือตรวจสอบว่ามีบันทึกอย่างน้อย 1 รายการ',
      ));
      debugPrint('🚀 ============================================');
    }
  }

  /// 📅 ดึง calendar events ของวันนี้ (และพรุ่งนี้ถ้าถาม) แล้วแปลงเป็น context string
  Future<String> _buildCalendarContext(String userMessage) async {
    try {
      final now = DateTime.now();
      final lowerMsg = userMessage.toLowerCase();
      final includeTomorrow = lowerMsg.contains('พรุ่งนี้') ||
          lowerMsg.contains('tomorrow') ||
          lowerMsg.contains('พรุ้งนี้');

      final dayStart = DateTime(now.year, now.month, now.day);
      final rangeEnd = includeTomorrow
          ? dayStart.add(const Duration(days: 2))
          : dayStart.add(const Duration(days: 1));

      final events = await SchedulerService().getCalendarEvents(dayStart, rangeEnd);
      if (events.isEmpty) return '';

      final buf = StringBuffer();
      buf.writeln(includeTomorrow ? 'Calendar (today+tomorrow):' : 'Calendar today:');
      for (final e in events) {
        final title = e['title'] as String? ?? 'กิจกรรม';
        final startMs = e['startTime'] as int?;
        if (startMs != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(startMs);
          final dayLabel = dt.day == now.day ? 'วันนี้' : 'พรุ่งนี้';
          final timeStr =
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          buf.writeln('- $dayLabel $timeStr $title');
        } else {
          buf.writeln('- $title');
        }
      }
      return buf.toString().trim();
    } catch (e) {
      debugPrint('⚠️ _buildCalendarContext failed: $e');
      return '';
    }
  }

  /// 🧠 Stage 2: Big Manager — async after Stage 1
  /// 🤫 Secret Chat: แปล Thai exchange → English log → Big Manager dispatch
  ///
  /// ทำ async หลัง Face ตอบ (ไม่ block UI)
  /// Big Manager ใช้ intent จาก extraction result โดยตรง (0 LLM calls เพิ่ม)
  void _runSecretChat(String userMessage, String aiResponse) {
    Future(() async {
      try {
        debugPrint('🤫 Secret Chat: translating exchange...');
        final secretChat = SecretChatService();
        final logEntry = await secretChat.logExchange(
          userMessage: userMessage,
          aiResponse: aiResponse,
        );

        if (logEntry != null) {
          debugPrint('🤫 Secret Chat done: ${logEntry.summaryEn}');
          // 📦 Replace Thai lean context with compact English (saves ~3-5x tokens)
          // 🏷️ Auto-tag + location → SQLite entry ล่าสุด (best-effort, ไม่ block)
          TagContextService().saveTagsToRecentEntry(logEntry);
          // 📍 Resolve place sentiment ถ้ามี active feedback request
          final feedbackSvc = PlaceFeedbackService();
          final activeId = feedbackSvc.activeRequestId;
          if (activeId != null) {
            final sentiment = feedbackSvc.resolveSentiment(
              logEntry: logEntry,
              rawMsg: userMessage,
            );
            final activeReq = feedbackSvc.getActiveRequest();
            if (activeReq?.placeId != null) {
              await PlaceService().updatePlaceSentiment(
                placeId: activeReq!.placeId!,
                sentiment: sentiment,
              );
            }
            await feedbackSvc.markDelivered(activeId);
          }
          // Big Manager dispatch based on English log (no extra LLM call)
          final actionData = await ManagerDispatchService()
              .dispatchFromLog(logEntry, userMessage);

          if (actionData != null && actionData.isNotEmpty) {
            addMessage(ChatMessage.assistant(actionData));
          }
        }
      } catch (e) {
        debugPrint('⚠️ Secret Chat failed: $e');
      }
    });
  }

  /// 🔨 สร้าง prompt สำหรับสรุปผลค้นหาให้ผู้ใช้
  String _buildSearchFollowUpPrompt(
          String originalQuestion, String searchResult) =>
      '''<start_of_turn>user
You are Haku, a helpful Thai-speaking AI assistant.

User asked: "$originalQuestion"

Search Results:
$searchResult

Task: Answer the user's question naturally in Thai based on the search results above.
Be helpful, concise, and friendly. Use emoji if appropriate.

Reply in Thai (1-2 sentences):
<end_of_turn>
<start_of_turn>model
''';

  /// 🔔 ตอบกลับ Trigger Event (Proactive)
  Future<void> respondToTrigger(TriggerEvent trigger) async {
    // ถ้าเป็น placeFeedback → mark active request เพื่อ resolve sentiment ภายหลัง
    if (trigger.type == TriggerType.placeFeedback) {
      final requestId =
          trigger.payloadJson?['feedbackRequestId'] as String?;
      if (requestId != null) PlaceFeedbackService().markAsked(requestId);
    }

    addMessage(ChatMessage.loading());

    try {
      // สร้าง prompt จาก trigger context
      final prompt = await _buildTriggerPrompt(trigger);

      String response;
      final llm = LLMProviderManager().provider;

      // 🔋 Lazy Loading: ลองโหลด LLM ถ้ายังไม่ได้โหลด
      if (!llm.isInitialized && !llm.isLoading) {
        await llm.initialize();
      }

      if (llm.isInitialized) {
        response = await llm.generate(prompt);
        response = _extractResponseText(response);
      } else {
        response = trigger.suggestedMessage ?? 'สวัสดีค่ะ!';
      }

      state = state.where((m) => !m.isLoading).toList();
      addMessage(ChatMessage.proactive(
        response,
        triggerTitle: trigger.displayTitle,
      ));

    } catch (e) {
      state = state.where((m) => !m.isLoading).toList();
      addMessage(ChatMessage.assistant(trigger.suggestedMessage ?? 'สวัสดีค่ะ!'));
    }
  }

  /// 📝 สร้าง Prompt สำหรับ Trigger (Gemma-3 format)
  Future<String> _buildTriggerPrompt(TriggerEvent trigger) async {
    final triggerContextStr = ContextRetriever().buildContextString(trigger.context);

    // ดึง context เพิ่มเติมจาก ContextRetriever
    final fullContextData = await ContextRetriever().retrieveFullContext();
    final fullContextStr = ContextRetriever().buildContextString(fullContextData);

    return PromptBuilder.buildProactivePrompt(
      triggerContext: triggerContextStr,
      suggestedMessage: trigger.suggestedMessage ?? 'สวัสดีค่ะ',
      context: fullContextStr.isNotEmpty ? fullContextStr : null,
    );
  }

  /// 📅 ตรวจว่าข้อความถามเรื่อง schedule/calendar
  bool _isScheduleQuery(String text) {
    final lower = text.toLowerCase();
    const queryWords = ['ต้องทำอะไร', 'มีอะไร', 'มีนัด', 'วางแผน', 'ตาราง',
        'schedule', 'calendar', 'appointment', 'plan', 'today', 'tomorrow'];
    return queryWords.any(lower.contains);
  }

  /// 🔗 ดึง sources จาก context (เฉพาะวันที่ที่เป็น log entries จริงๆ ไม่ใช่ future events)
  List<String>? _extractSources(String context) {
    if (context.contains('ไม่พบบันทึก')) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // แสดงเฉพาะวันที่ที่อยู่ในช่วง 90 วันที่ผ่านมา ถึง 1 วันข้างหน้า (log entries จริง)
    final earliest = today.subtract(const Duration(days: 90));
    final latest = today.add(const Duration(days: 1));

    final seen = <String>{};
    final dates = RegExp(r'\d{4}-\d{2}-\d{2}')
        .allMatches(context)
        .map((m) => m.group(0)!)
        .where((d) {
          if (!seen.add(d)) return false; // deduplicate
          try {
            final dt = DateTime.parse(d);
            return dt.isAfter(earliest) && dt.isBefore(latest);
          } catch (_) {
            return false;
          }
        })
        .toList();

    return dates.isEmpty ? null : dates;
  }

  // ─────────────────────────────────────────────────────────────────
  // ⚡ 0-Token Quick Actions — ดึงข้อมูลตรงจาก DB ไม่ใช้ LLM
  // ─────────────────────────────────────────────────────────────────

  /// ⚡ Dispatcher สำหรับ 0-token quick actions ทั้งหมด
  Future<void> quickAction0Token(String actionType) async {
    final label = _quickActionLabel(actionType);
    addMessage(ChatMessage.user(label));
    addMessage(ChatMessage.loading());
    try {
      final result = await _buildQuickActionResponse(actionType);
      state = state.where((m) => !m.isLoading).toList();
      addMessage(ChatMessage.assistant(result));
    } catch (e) {
      state = state.where((m) => !m.isLoading).toList();
      addMessage(ChatMessage.error('ดึงข้อมูลไม่ได้ค่ะ: $e'));
    }
  }

  String _quickActionLabel(String actionType) {
    switch (actionType) {
      case 'summarize_today': return 'สรุปวันนี้ให้หน่อย';
      case 'food_today':      return 'วันนี้กินอะไรไปบ้าง?';
      case 'day_review':      return 'วันนี้เป็นยังไงบ้าง?';
      case 'places_today':    return 'วันนี้ไปที่ไหนบ้าง?';
      case 'mood_today':      return 'ช่วงนี้อารมณ์ฉันเป็นยังไง?';
      default:                return actionType;
    }
  }

  Future<String> _buildQuickActionResponse(String actionType) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final allEntries = await DatabaseHelper.instance.getAllEntries();
    final todayEntries = allEntries
        .where((e) => e.createdAt.isAfter(startOfDay) && e.createdAt.isBefore(endOfDay))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    switch (actionType) {
      case 'summarize_today':
        return _summarizeTodayResponse(todayEntries, now);
      case 'food_today':
        return _foodTodayResponse(todayEntries);
      case 'day_review':
        return _dayReviewResponse(todayEntries);
      case 'places_today':
        return _placesTodayResponse(todayEntries);
      case 'mood_today':
        return _moodTodayResponse(todayEntries);
      default:
        return 'ไม่รู้จัก action นี้ค่ะ';
    }
  }

  Future<String> _summarizeTodayResponse(List<dynamic> todayEntries, DateTime now) async {
    final buf = StringBuffer();
    final dateStr = '${now.day}/${now.month}/${now.year}';

    // ดึง calendar events ของวันนี้
    final calEvents = await SchedulerService().getCalendarEvents(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day + 1),
    );

    if (todayEntries.isEmpty && calEvents.isEmpty) {
      return 'วันนี้ ($dateStr) ยังไม่มีบันทึกหรือนัดหมายเลยค่ะ ลองเริ่มบันทึกสิ่งที่ทำวันนี้กันนะคะ!';
    }

    buf.writeln('สรุปวันที่ $dateStr');

    // นัดหมายจาก Calendar
    if (calEvents.isNotEmpty) {
      buf.writeln('\nนัดหมายวันนี้ (${calEvents.length} รายการ):');
      for (final e in calEvents) {
        final title = e['title'] as String? ?? 'กิจกรรม';
        final ms = e['startTime'] as int?;
        final timeStr = ms != null
            ? () {
                final dt = DateTime.fromMillisecondsSinceEpoch(ms);
                return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              }()
            : null;
        buf.writeln('  • ${timeStr != null ? '$timeStr ' : ''}$title');
      }
    }

    // บันทึกจาก Diary
    if (todayEntries.isNotEmpty) {
      buf.writeln('\nบันทึกวันนี้ (${todayEntries.length} รายการ):');
      for (final entry in todayEntries) {
        final e = entry as dynamic;
        final t = e.createdAt as DateTime;
        final timeStr = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        final preview = (e.content as String).length > 50
            ? '${(e.content as String).substring(0, 50)}...'
            : e.content as String;
        final moodEmoji = e.mood != null ? _moodEmoji(e.mood as int) : '';
        buf.writeln('  • $timeStr $moodEmoji $preview');
      }

      // สรุป mood เฉลี่ย
      final moods = todayEntries
          .where((e) => (e as dynamic).mood != null)
          .map((e) => (e as dynamic).mood as int)
          .toList();
      if (moods.isNotEmpty) {
        final avg = moods.reduce((a, b) => a + b) / moods.length;
        final avgEmoji = _moodEmoji(avg.round());
        buf.writeln('\n$avgEmoji อารมณ์เฉลี่ยวันนี้: ${avg.toStringAsFixed(1)}/5');
      }
    }

    return buf.toString().trim();
  }

  String _foodTodayResponse(List<dynamic> todayEntries) {
    const foodKw = ['กิน', 'ข้าว', 'อาหาร', 'ร้าน', 'ชา', 'กาแฟ', 'ดื่ม', 'ขนม',
        'ก๋วยเตี๋ยว', 'ส้มตำ', 'ผัด', 'ต้ม', 'แกง', 'หมู', 'ไก่', 'ปลา',
        'pizza', 'sushi', 'burger', 'cafe', 'coffee', 'eat', 'lunch', 'dinner', 'breakfast'];
    final foodEntries = todayEntries.where((e) {
      final content = ((e as dynamic).content as String).toLowerCase();
      return foodKw.any((kw) => content.contains(kw));
    }).toList();

    if (foodEntries.isEmpty) {
      return 'วันนี้ยังไม่พบบันทึกเรื่องอาหารเลยค่ะ กินอะไรไปบ้างเล่าให้ฟังหน่อยนะคะ!';
    }

    final buf = StringBuffer('วันนี้กินอะไรไปบ้าง:\n');
    for (final entry in foodEntries) {
      final e = entry as dynamic;
      final t = e.createdAt as DateTime;
      final timeStr = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      buf.writeln('• $timeStr — ${e.content as String}');
    }
    return buf.toString().trim();
  }

  Future<String> _dayReviewResponse(List<dynamic> todayEntries) async {
    final buf = StringBuffer();

    if (todayEntries.isEmpty) {
      buf.writeln('วันนี้ยังไม่มีบันทึกเลยค่ะ เริ่มเล่าให้ฟังได้เลยนะคะ!');
    } else {
      buf.writeln('ไทม์ไลน์วันนี้:');
      for (final entry in todayEntries) {
        final e = entry as dynamic;
        final t = e.createdAt as DateTime;
        final timeStr = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        final moodStr = e.mood != null ? ' ${_moodEmoji(e.mood as int)}' : '';
        buf.writeln('$timeStr$moodStr — ${e.content as String}');
      }
    }

    // เพิ่ม Hidden Correlation insights (0 LLM, pure Dart)
    try {
      final insights = await CorrelationService().analyze();
      if (insights.isNotEmpty) {
        buf.writeln('\nสิ่งที่ฮาคุสังเกตเห็น:');
        for (final insight in insights.take(3)) {
          final icon = insight.isPositive ? '✓' : '!';
          buf.writeln('$icon ${insight.message}');
        }
      }
    } catch (_) {}

    return buf.toString().trim();
  }

  Future<String> _placesTodayResponse(List<dynamic> todayEntries) async {
    final withLocation = todayEntries
        .where((e) =>
            (e as dynamic).locationName != null &&
            ((e as dynamic).locationName as String).isNotEmpty)
        .toList();

    String? askAboutPlace; // สถานที่ที่จะถาม follow-up

    if (withLocation.isEmpty) {
      // ลอง parse จาก content (mention สถานที่ใน text)
      final mentionEntries = todayEntries.where((e) {
        final c = ((e as dynamic).content as String).toLowerCase();
        return c.contains('ที่') || c.contains('ไป') || c.contains('มา') || c.contains('@');
      }).toList();

      if (mentionEntries.isEmpty) {
        return 'วันนี้ยังไม่มีบันทึกสถานที่เลยค่ะ ลองเปิด GPS ไว้ขณะบันทึกนะคะ!';
      }
      final buf = StringBuffer('สถานที่ที่กล่าวถึงวันนี้:\n');
      for (final e in mentionEntries) {
        final en = e as dynamic;
        final t = en.createdAt as DateTime;
        final timeStr =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        buf.writeln('• $timeStr — ${en.content as String}');
      }
      return buf.toString().trim();
    }

    // รวม unique locations (เรียงตาม entry ล่าสุดก่อน)
    final seen = <String>{};
    final locations = <String>[];
    for (final e in withLocation.reversed) {
      final loc = (e as dynamic).locationName as String;
      if (seen.add(loc)) locations.add(loc);
    }

    final buf = StringBuffer('วันนี้ไปที่ไหนบ้าง (${locations.length} สถานที่):\n');
    for (final loc in locations) {
      buf.writeln('• $loc');
    }

    // เลือกสถานที่ล่าสุดที่ยังไม่มี sentiment บันทึกไว้
    askAboutPlace = await _pickPlaceToAsk(locations);
    if (askAboutPlace != null) {
      buf.writeln('\nแล้วที่ $askAboutPlace เป็นยังไงบ้างคะ?');

      // activate PlaceFeedbackService ถ้ามี request ที่ match
      final pending = PlaceFeedbackService().dequeuePending();
      if (pending != null &&
          locations.any((l) => l.contains(pending.placeName))) {
        PlaceFeedbackService().markAsked(pending.id);
      }
    }

    return buf.toString().trim();
  }

  /// เลือกสถานที่ล่าสุดที่ยังไม่มี mood บันทึกในวันนี้ สำหรับถาม follow-up
  Future<String?> _pickPlaceToAsk(List<String> locations) async {
    if (locations.isEmpty) return null;
    try {
      // ถ้ามี pending feedback request → ใช้ชื่อนั้นก่อน
      final pending = PlaceFeedbackService().hasPending
          ? PlaceFeedbackService().dequeuePending()
          : null;
      if (pending != null) {
        return pending.placeName;
      }
      // ไม่งั้นใช้สถานที่แรก (ล่าสุด)
      return locations.first;
    } catch (_) {
      return locations.first;
    }
  }

  String _moodTodayResponse(List<dynamic> todayEntries) {
    final withMood = todayEntries
        .where((e) => (e as dynamic).mood != null)
        .toList();

    if (withMood.isEmpty) {
      return 'วันนี้ยังไม่มีการบันทึกอารมณ์เลยค่ะ';
    }

    final moodCounts = <int, int>{};
    for (final e in withMood) {
      final m = (e as dynamic).mood as int;
      moodCounts[m] = (moodCounts[m] ?? 0) + 1;
    }
    final avgMood = withMood.map((e) => (e as dynamic).mood as int).reduce((a, b) => a + b) /
        withMood.length;

    final buf = StringBuffer('${_moodEmoji(avgMood.round())} อารมณ์วันนี้:\n');
    for (final entry in 5.downTo(1)) {
      final count = moodCounts[entry] ?? 0;
      if (count == 0) continue;
      buf.writeln('${_moodEmoji(entry)} ×$count  ${_moodLabel(entry)}');
    }
    buf.writeln('\nเฉลี่ย: ${avgMood.toStringAsFixed(1)}/5 ${_moodEmoji(avgMood.round())}');
    return buf.toString().trim();
  }

  String _moodEmoji(int mood) {
    switch (mood) {
      case 1: return '😢';
      case 2: return '😕';
      case 3: return '😐';
      case 4: return '🙂';
      case 5: return '😄';
      default: return '';
    }
  }

  String _moodLabel(int mood) {
    switch (mood) {
      case 1: return 'แย่มาก';
      case 2: return 'แย่';
      case 3: return 'เฉยๆ';
      case 4: return 'ดี';
      case 5: return 'ดีมาก';
      default: return '';
    }
  }
}

extension _IntRange on int {
  Iterable<int> downTo(int end) sync* {
    for (var i = this; i >= end; i--) {
      yield i;
    }
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  final String? initialQuestion;

  const ChatScreen({super.key, this.initialQuestion});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  bool _contextEnabled = true;

  final List<QuickQuestion> _quickQuestions = [
    QuickQuestion(icon: Icons.calendar_today_outlined, text: 'สรุปวันนี้',   query: 'summarize_today', isAction: true, actionType: 'summarize_today'),
    QuickQuestion(icon: Icons.restaurant_outlined, text: 'วันนี้กินอะไร?', query: '',             isAction: true, actionType: 'food_today'),
    QuickQuestion(icon: Icons.sentiment_satisfied_outlined, text: 'วันนี้เป็นยังไง?', query: '',           isAction: true, actionType: 'day_review'),
    QuickQuestion(icon: Icons.place_outlined, text: 'ไปไหนมาบ้าง?', query: '',              isAction: true, actionType: 'places_today'),
    QuickQuestion(icon: Icons.mood_outlined, text: 'อารมณ์ดีไหม?',  query: '',             isAction: true, actionType: 'mood_today'),
    QuickQuestion(icon: Icons.language_outlined, text: 'ค้นเว็บ',        query: '',             isCustom: true),
  ];

  @override
  void initState() {
    super.initState();
    _initializeServices();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialQuestion != null) {
        _sendQuickQuestionByText(widget.initialQuestion!);
      }
    });
  }

  /// 🔄 เริ่ม LiteRT Conversation session ใหม่
  /// รีเซ็ต KV cache + ตั้ง system instruction ครั้งเดียวต่อ session
  void _startNewLiteRTSession() {
    final provider = LLMProviderManager().provider;
    if (provider is LiteRTLLMProvider) {
      provider.resetConversation();
      provider.setSystemInstruction(PromptBuilder.buildSystemInstruction());
      debugPrint('🔄 LiteRT session ใหม่ — system instruction ตั้งแล้ว');
    }
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize RAG (Lightweight - ไม่ใช้ LLM)
      debugPrint('🔄 Initializing RAG...');
      await RAGService().initialize();
      debugPrint('✅ RAG initialized: ${RAGService().isInitialized}');

      // 🎛️ Initialize LLM Provider Manager (load saved preference)
      debugPrint('🔄 Initializing LLM Provider Manager...');
      await LLMProviderManager().initialize();
      debugPrint('✅ LLM Provider: ${LLMProviderManager().providerName}');

      // รีเซ็ต stateful Conversation เมื่อเริ่ม chat session ใหม่
      // System instruction ตั้งครั้งเดียว — Conversation จัดการ KV cache เอง
      _startNewLiteRTSession();

      debugPrint('💡 LLM จะโหลดแบบ Lazy Loading (เมื่อใช้งานจริง)');

      // 🔋 Initialize Chat Summary Service (Deferred Processing)
      debugPrint('🔄 Initializing Chat Summary Service...');
      await ChatSummaryService().initialize();
      debugPrint('✅ Chat Summary Service initialized (Deferred to Charging)');

      // 🏭 Initialize Deferred Task Service + register background handlers
      debugPrint('🔄 Initializing Deferred Task Service...');
      await DeferredTaskService().initialize();
      BackgroundTaskHandlers.registerAll();
      debugPrint('✅ Deferred Task Service initialized');

      // Index entries ถ้ายังไม่มี
      if (RAGService().isInitialized) {
        debugPrint('🔄 Indexing entries...');
        final entries = await DatabaseHelper.instance.getAllEntries();
        if (entries.isNotEmpty) {
          await RAGService().indexEntries(entries);
        }
        debugPrint('✅ Entries indexed');
      }

      // Initialize Notification Service
      debugPrint('🔄 Initializing Notification Service...');
      final notificationService = NotificationService();
      await notificationService.initialize();
      notificationService.onQuickReply = (triggerId, response) {
        // ส่งข้อความตอบกลับจาก notification ตรงไปที่ AI
        _sendQuickReplyFromNotification(response);
      };
      notificationService.onNotificationTap = (event) {
        _handleTrigger(event);
      };

      // Initialize MVP Trigger Service
      debugPrint('🔄 Initializing Trigger Service...');
      final triggerService = MVPTriggerService();
      await triggerService.initialize();

      // ตั้ง callback เมื่อมี trigger - แสดงทั้งในแอพและ notification
      triggerService.onTrigger = (event) {
        _handleTrigger(event);
        notificationService.showTriggerNotification(event);
      };
      debugPrint('✅ All services initialized');

      // 📍 เริ่ม Geofence + DwellTracker monitoring (foreground เท่านั้น)
      debugPrint('🔄 Starting Geofence monitoring...');
      await GeofenceService().initialize();
      await GeofenceService().startMonitoring();
      debugPrint('✅ Geofence monitoring started');

      // เช็ค pending place feedback — ยิง trigger หลัง UI ตั้ง settle 2s
      await PlaceFeedbackService().initialize();
      PlaceFeedbackService().pruneExpired();
      final pendingFeedback = PlaceFeedbackService().dequeuePending();
      if (pendingFeedback != null) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _handleTrigger(
              PlaceFeedbackService().buildTriggerEvent(pendingFeedback),
            );
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error initializing services: $e');
      debugPrint('Stack: $stackTrace');
    }
  }

  void _handleTrigger(TriggerEvent event) {
    // แสดง proactive message
    ref.read(chatHistoryProvider.notifier).respondToTrigger(event);
  }

  /// 💬 ส่งข้อความตอบกลับจาก Quick Reply Notification
  Future<void> _sendQuickReplyFromNotification(String reply) async {
    debugPrint('💬 Quick reply from notification: $reply');

    // ส่งข้อความไปให้ AI เหมือนกับผู้ใช้พิมพ์เอง
    await ref.read(chatHistoryProvider.notifier).sendToAI(reply);

    // Scroll ไปล่างสุด
    _scrollToBottom();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    setState(() => _isTyping = true);

    await ref.read(chatHistoryProvider.notifier).sendToAI(
      text,
      useContext: _contextEnabled,
    );

    setState(() => _isTyping = false);
    _scrollToBottom();
  }

  Future<void> _sendQuickQuestion(QuickQuestion question) async {
    if (question.isCustom) {
      // ค้นเว็บ: แสดง dialog ให้พิมพ์คำค้นหา
      final searchText = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.language, color: kCrystal400),
                SizedBox(width: 8),
                Text('ค้นหาบนเว็บ'),
              ],
            ),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'พิมพ์สิ่งที่ต้องการค้นหา...',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('ค้นหา', style: TextStyle(color: kCrystal600)),
              ),
            ],
          );
        },
      );
      if (searchText != null && searchText.isNotEmpty) {
        setState(() => _isTyping = true);
        await ref.read(chatHistoryProvider.notifier).sendToAI('ค้นหาข้อมูลเกี่ยวกับ $searchText');
        setState(() => _isTyping = false);
        _scrollToBottom();
      }
      return;
    }

    if (question.actionType != null) {
      setState(() => _isTyping = true);
      await ref.read(chatHistoryProvider.notifier).quickAction0Token(question.actionType!);
      setState(() => _isTyping = false);
      _scrollToBottom();
      return;
    }

    setState(() => _isTyping = true);
    await ref.read(chatHistoryProvider.notifier).sendToAI(question.query);
    setState(() => _isTyping = false);
    _scrollToBottom();
  }

  Future<void> _sendQuickQuestionByText(String questionText) async {
    final question = _quickQuestions.firstWhere(
      (q) => questionText.contains(q.text) || q.text.contains(questionText),
      orElse: () => QuickQuestion(icon: Icons.help_outline, text: questionText, query: questionText),
    );

    await _sendQuickQuestion(question);
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatHistoryProvider);
    final llmService = LLMProviderManager().provider;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: HakuGlassAppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kCrystal300, kCrystal500],
                ),
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
              child: const Center(
                child: Text('箱', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kFgOnCyan)),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Haku AI', style: TextStyle(fontSize: 16, color: kFg1, fontWeight: FontWeight.w600)),
                Text(
                  llmService.isInitialized ? '${LLMProviderManager().providerName} Online' : 'Mock Mode',
                  style: TextStyle(
                    fontSize: 11,
                    color: llmService.isInitialized ? kOk : kWarn,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Toggle Context
          IconButton(
            icon: Icon(_contextEnabled ? Icons.psychology : Icons.psychology_outlined, color: kFg3),
            tooltip: _contextEnabled ? 'Context: ON' : 'Context: OFF',
            onPressed: () {
              setState(() => _contextEnabled = !_contextEnabled);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_contextEnabled ? 'บริบทอัจฉริยะ: เปิด' : 'บริบทอัจฉริยะ: ปิด')),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: kFg3),
            onSelected: (value) async {
              if (value == 'clear') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('ล้างประวัติแชท'),
                    content: const Text('ข้อความทั้งหมดจะถูกลบออก ยืนยันไหมคะ?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ', style: TextStyle(color: kErr))),
                    ],
                  ),
                );
                if (confirm == true) {
                  ref.read(chatHistoryProvider.notifier).clearHistory();
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear', child: Row(children: [
                Icon(Icons.delete_outline, size: 18, color: kErr),
                SizedBox(width: 8),
                Text('ล้างประวัติแชท'),
              ])),
            ],
          ),
        ],
      ),
      body: HakuAuroraBackground(
        children: [
          Column(
            children: [
              // Status Bar
              if (!llmService.isInitialized)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: kWarn.withAlpha(20),
                    borderRadius: BorderRadius.circular(kR3),
                    border: Border.all(color: kWarn.withAlpha(60)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: kWarn.withAlpha(180)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'โหมดออฟไลน์: วางไฟล์ .gguf ในโฟลเดอร์ Downloads/ หรือเลือกผ่านการตั้งค่า',
                          style: TextStyle(fontSize: 12, color: kFg3),
                        ),
                      ),
                    ],
                  ),
                ),

              // Messages
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => _ChatBubble(message: messages[index]),
                ),
              ),

              // Quick Questions
              if (!_isTyping) _buildQuickQuestions(),

              // Input
              _buildInputArea(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickQuestions() => Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _quickQuestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final question = _quickQuestions[index];
          return ActionChip(
            avatar: Icon(question.icon, size: 18, color: kFg3),
            label: Text(question.text),
            backgroundColor: kGlassFillSoft,
            side: const BorderSide(color: kGlassStroke),
            labelStyle: const TextStyle(color: kFg1, fontSize: 13),
            onPressed: () => _sendQuickQuestion(question),
          );
        },
      ),
    );

  Widget _buildInputArea() => Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: kGlassFillSoft,
        border: Border(
          top: BorderSide(color: kGlassEdge, width: 1),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.mic_none),
              color: kFg3,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ฟีเจอร์เสียงจะมาใน Phase 2.5')),
                );
              },
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: kFg1),
                decoration: InputDecoration(
                  hintText: 'ถามฮาคุสิ...',
                  hintStyle: TextStyle(color: kFg4.withAlpha(180)),
                  filled: true,
                  fillColor: kGlassFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kRPill),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            _isTyping
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: kCrystal400),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.send),
                    color: kCrystal500,
                    onPressed: _sendMessage,
                  ),
          ],
        ),
      ),
    );
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');

    if (message.isLoading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: kGlassFill,
                borderRadius: BorderRadius.circular(20),
                border: const Border(
                  top: BorderSide(color: kGlassEdge, width: 1),
                  left: BorderSide(color: kGlassStroke, width: 0.5),
                  right: BorderSide(color: kGlassStroke, width: 0.5),
                  bottom: BorderSide(color: kGlassStroke, width: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDot(0),
                  const SizedBox(width: 4),
                  _buildDot(1),
                  const SizedBox(width: 4),
                  _buildDot(2),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 🔍 Searching Message (intermediate)
    if (message.isSearching) {
      return _buildSearchingBubble(message);
    }

    // 🗃️ Brain-Dump Summary Card
    if (message.isWorkerSummary) {
      return _buildWorkerSummaryCard(message);
    }

    // 🔔 Proactive Message (จาก Trigger)
    if (message.isProactive) {
      return _buildProactiveBubble(message);
    }

    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [kCrystal300, kCrystal500]),
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              child: const Center(child: Text('箱', style: TextStyle(fontSize: 14, color: kFgOnCyan))),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: isUser
                    ? const LinearGradient(colors: [kCrystal300, kCrystal500])
                    : null,
                color: isUser ? null : kGlassFill,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                border: isUser
                    ? null
                    : const Border(
                        top: BorderSide(color: kGlassEdge, width: 1),
                        left: BorderSide(color: kGlassStroke, width: 0.5),
                        right: BorderSide(color: kGlassStroke, width: 0.5),
                        bottom: BorderSide(color: kGlassStroke, width: 0.5),
                      ),
              ),
              child: Builder(builder: (context) {
                // Parse <thinking>...</thinking> block from model response
                final raw = message.content;
                final thinkMatch = RegExp(
                  r'<thinking>([\s\S]*?)<\/thinking>',
                  caseSensitive: false,
                ).firstMatch(raw);
                final thinking = thinkMatch?.group(1)?.trim();
                final reply = thinkMatch != null
                    ? raw.replaceFirst(thinkMatch.group(0)!, '').trim()
                    : raw;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUser && thinking != null && thinking.isNotEmpty)
                      _ThinkingSection(thinking: thinking),
                    Text(
                      reply,
                      style: TextStyle(
                        color: isUser ? kFgOnCyan : kFg1,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    if (message.sources != null && message.sources!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'อ้างอิง: ${message.sources!.join(', ')}',
                        style: TextStyle(
                          fontSize: 10,
                          color: kFg3.withAlpha(180),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      timeFormat.format(message.timestamp),
                      style: TextStyle(
                        color: isUser ? kFgOnCyan.withAlpha(180) : kFg4,
                        fontSize: 10,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) => AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: kCrystal400.withAlpha(100 + (index * 60)),
        borderRadius: BorderRadius.circular(4),
      ),
    );

  /// 🔍 แสดง Searching Bubble (intermediate message)
  Widget _buildSearchingBubble(ChatMessage message) {
    final timeFormat = DateFormat('HH:mm');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [kCrystal300, kCrystal500]),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: const Center(
                child: Text('箱', style: TextStyle(fontSize: 14, color: kFgOnCyan))),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: kGlassFill,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(20),
                ),
                border: Border(
                  top: BorderSide(color: kGlassEdge, width: 1),
                  left: BorderSide(color: kGlassStroke, width: 0.5),
                  right: BorderSide(color: kGlassStroke, width: 0.5),
                  bottom: BorderSide(color: kGlassStroke, width: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kCrystal400,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          message.content,
                          style: const TextStyle(
                            color: kFg1,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeFormat.format(message.timestamp),
                    style: const TextStyle(
                      color: kFg4,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 🗃️ แสดง Brain-Dump Summary Card
  Widget _buildWorkerSummaryCard(ChatMessage message) {
    final lines = message.content.split('\n');
    final header = lines.first;
    final items = lines.skip(1).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: kVividMint.withAlpha(20),
          borderRadius: BorderRadius.circular(kR4),
          border: Border.all(
            color: kVividMint.withAlpha(80),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 16, color: kOk),
                const SizedBox(width: 6),
                Text(
                  header,
                  style: const TextStyle(
                    color: kOk,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...items.map((line) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  line,
                  style: const TextStyle(
                    color: kFg1,
                    fontSize: 13,
                  ),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  /// 🔔 แสดง Proactive Bubble (Trigger message)
  Widget _buildProactiveBubble(ChatMessage message) {
    final timeFormat = DateFormat('HH:mm');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [kVividGold, kVividCoral]),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: const Center(child: Icon(Icons.notifications_active_outlined, size: 16, color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: kGlassFill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kVividGold.withAlpha(100)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.triggerTitle != null) ...[
                    Text(
                      message.triggerTitle!,
                      style: const TextStyle(
                        color: kVividCoral,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    message.content,
                    style: const TextStyle(
                      color: kFg1,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeFormat.format(message.timestamp),
                    style: const TextStyle(
                      color: kFg4,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 💭 Thinking Section — collapsible reasoning block (Gemma 4)
// ══════════════════════════════════════════════════════════════

class _ThinkingSection extends StatefulWidget {
  final String thinking;
  const _ThinkingSection({required this.thinking});

  @override
  State<_ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<_ThinkingSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: kFg3,
                ),
                const SizedBox(width: 4),
                Text(
                  '💭 reasoning',
                  style: TextStyle(
                    fontSize: 11,
                    color: kFg3,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kFg4.withAlpha(60)),
              ),
              child: Text(
                widget.thinking,
                style: const TextStyle(
                  fontSize: 12,
                  color: kFg2,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class QuickQuestion {
  final IconData icon;
  final String text;
  final String query;
  final bool isCustom;
  final bool isAction;
  // actionType สำหรับ 0-token quick actions
  // 'summarize_today' | 'food_today' | 'day_review' | 'places_today' | 'mood_today' | 'web_search'
  final String? actionType;

  QuickQuestion({
    required this.icon,
    required this.text,
    required this.query,
    this.isCustom = false,
    this.isAction = false,
    this.actionType,
  });
}
