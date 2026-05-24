import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/entry.dart';
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
import '../services/device_command_gate.dart';
import '../services/device_command_intent_detector.dart';
import '../services/device_command_notification_handler.dart';
import '../widgets/device_command_confirmation_card.dart';
import '../services/smart_preprocessor.dart';
import '../services/place_feedback_service.dart';
import '../services/place_service.dart';
import '../services/preset_service.dart';
import '../services/tag_context_service.dart';
import '../services/wiki_service.dart';
import '../services/correlation_service.dart';
import '../services/geofence_service.dart';
import '../services/location_service.dart';
import '../services/nominatim_service.dart';
import '../services/mcp_service.dart';
import '../services/scheduler_service.dart';
import '../services/session_resume_service.dart';
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

  // System context (resume + schedule) สำหรับ cloud prompt — on-device ใช้ KV cache แทน
  String _resume = '';
  String _scheduleBlock = '';

  ChatNotifier() : super([ChatMessage.welcome()]) {
    _loadHistory();
  }

  /// อัปเดต resume + schedule ที่ใช้ inject เข้า cloud prompt (เรียกจาก _startNewLiteRTSession)
  void updateSystemContext(String resume, String scheduleBlock) {
    _resume = resume;
    _scheduleBlock = scheduleBlock;
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

  /// 🗑️ ล้าง chat UI + in-memory log — แต่ preserve LTM ใน SQLite
  ///
  /// หลักการ: "ลบแชท ≠ ลืม" — Haku จะยังจำจาก facts + episodic log ใน DB
  Future<void> clearHistory() async {
    state = [ChatMessage.welcome()];
    // ล้าง UI history + in-memory SharedPreferences เท่านั้น
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    // ล้าง in-memory log แต่ไม่ลบ SQLite secret_chat_log (LTM preserved)
    await SecretChatService().clearAll();
    debugPrint('💬 Chat UI cleared — LTM (SQLite facts + episodic) preserved');
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
  Future<void> sendToAI(
    String userMessage, {
    bool useContext = true,
    List<Uint8List>? images,
    List<String>? imagePaths,
    BuildContext? context,
  }) async {
    debugPrint('🚀 ============================================');
    debugPrint('🚀 sendToAI called: $userMessage');

    // เพิ่มข้อความผู้ใช้ (พร้อม thumbnail ถ้ามีรูป)
    addMessage(ChatMessage.user(userMessage, imagePaths: imagePaths));

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
      // 0.5 Device Command (rule-based, 0 LLM, async execute)
      // ──────────────────────────────────────────────────────
      final detectedCmd = await DeviceCommandIntentDetector.detect(userMessage, context: context);
      if (detectedCmd != null) {
        final tier = DeviceCommandGate.getTier(detectedCmd.action);

        // 🛡️ Sensitive commands → แสดง inline confirmation card ในแชท
        if (tier == CommandTier.confirm || tier == CommandTier.biometric) {
          debugPrint('🛡️ Sensitive command: ${detectedCmd.action} → confirmation card');
          state = state.where((m) => !m.isLoading).toList();
          addMessage(ChatMessage.confirmationCard(
            content: DeviceCommandGate.summarizeCommand(
              detectedCmd.action,
              detectedCmd.params,
            ),
            command: detectedCmd.action,
            params: detectedCmd.params,
          ));
          return;
        }

        // 🟢 Auto / 🟡 Notify tier → execute ทันที
        if (context != null && !context.mounted) return;
        final result = await detectedCmd.execute(context);
        final success = result['success'] == true;
        final reply = detectedCmd.postExecuteReply != null
            ? detectedCmd.postExecuteReply!(result)
            : detectedCmd.replyTemplate;

        debugPrint('📱 Device command: ${detectedCmd.action} → success=$success');
        state = state.where((m) => !m.isLoading).toList();
        addMessage(ChatMessage.assistant(reply));
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
        debugPrint('🔍 Search path: MCP flow');
        state = state.where((m) => !m.isLoading).toList();
        addMessage(ChatMessage.searching('รับทราบค่ะ กำลังค้นหาให้นะคะ...'));

        final searchQuery = preprocessResult!.searchQuery ?? userMessage;
        ManagerDispatchService.markSearched(searchQuery);

        String? webResult;
        final mcp = McpService();
        await mcp.loadSettings();
        if (mcp.isConfigured) {
          try {
            final connected = await mcp.connect();
            if (connected) webResult = await mcp.search(searchQuery);
          } catch (e) {
            debugPrint('⚠️ MCP search failed: $e');
          }
        }

        if (llm.isInitialized && webResult != null && webResult.isNotEmpty) {
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
          // MCP ไม่ได้ตั้งค่า หรือค้นไม่เจอ → Face LLM ตอบจากความรู้เอง
          debugPrint('🔍 No MCP result, falling back to LLM knowledge...');
          try {
            final fallbackPrompt = 'User asked: "$userMessage"\n'
                '(ไม่มีข้อมูลจากการค้นหา ตอบจากความรู้ที่มีได้เลยค่ะ)\n\n'
                'Please respond in Thai naturally.';
            response = await llm.generate(fallbackPrompt);
            response = _extractResponseText(response);
          } catch (e) {
            debugPrint('⚠️ Fallback LLM failed: $e');
            response = 'ขอโทษนะคะ ไม่สามารถค้นหาข้อมูลได้ในขณะนี้ค่ะ';
          }
        }

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

        // 1.55. Wiki Context — knowledge pages สำหรับ entity ที่เกี่ยวข้อง (0 LLM)
        final wikiPages = await WikiService().query(userMessage);
        if (wikiPages.isNotEmpty) {
          final wikiCtx = WikiService().formatForContext(wikiPages);
          contextStr = wikiCtx + (contextStr.isNotEmpty ? '\n$contextStr' : '');
          debugPrint('📚 Wiki context injected (${wikiPages.length} pages)');
        }

        // 1.6. Calendar Context — ดึงตารางวันนี้เสมอ (ให้ LLM รู้เสมอว่ามีอะไร)
        final calCtx = await _buildCalendarContext(userMessage);
        if (calCtx.isNotEmpty) {
          contextStr = calCtx + (contextStr.isNotEmpty ? '\n$contextStr' : '');
          debugPrint('📅 Calendar context injected (${calCtx.length} chars)');
        }

        // 1.7. RAG Context — semantic vector search diary entries
        if (useContext && RAGService().isInitialized) {
          try {
            final ragCtx = await RAGService().buildContext(userMessage, topK: 3);
            if (ragCtx.isNotEmpty && !ragCtx.startsWith('No related')) {
              contextStr = ragCtx + (contextStr.isNotEmpty ? '\n$contextStr' : '');
              debugPrint('🔍 RAG context injected (${ragCtx.length} chars)');
            }
          } catch (e) {
            debugPrint('⚠️ RAG context failed (non-fatal): $e');
          }
        }

        // 2. Face LLM — Stage 1 (The Face)
        debugPrint('🎭 Stage 1 (The Face): generating natural response...');

        if (llm.isInitialized) {
          try {
            final isCloud = LLMProviderManager().activeType != ProviderType.onDevice;
            final ctx = contextStr.isNotEmpty ? contextStr : null;

            if (isCloud) {
              // Cloud: stateless full prompt — inject resume + schedule (same context as on-device)
              final systemExtra = [
                if (_resume.isNotEmpty) _resume,
                if (_scheduleBlock.isNotEmpty) _scheduleBlock,
              ].join('\n\n');
              final prompt = PromptBuilder.buildCloudPrompt(
                userMessage: userMessage,
                context: ctx,
                systemExtra: systemExtra.isNotEmpty ? systemExtra : null,
              );
              response = await llm.generate(prompt).timeout(
                const Duration(seconds: 30),
                onTimeout: () { debugPrint('⏱️ Cloud LLM timeout'); return ''; },
              );
            } else {
              // On-device: stateful conversation — KV cache carries system instruction + history
              final liteRT = llm as LiteRTLLMProvider;
              final turn = PromptBuilder.buildUserTurn(userMessage: userMessage, context: ctx);
              if (images != null && images.isNotEmpty) {
                response = await liteRT.generateTurnWithImages(turn, images).timeout(
                  const Duration(seconds: 180),
                  onTimeout: () { debugPrint('⏱️ Vision LLM timeout'); return ''; },
                );
              } else {
                response = await liteRT.generateTurn(turn).timeout(
                  const Duration(seconds: 120),
                  onTimeout: () { debugPrint('⏱️ On-device LLM timeout'); return ''; },
                );
              }
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

  /// 🔨 สร้าง prompt สำหรับสรุปผลค้นหา — universal format (cloud + on-device)
  String _buildSearchFollowUpPrompt(
      String originalQuestion, String searchResult) {
    final core = 'You are Haku, a helpful Thai-speaking AI assistant.\n\n'
        'User asked: "$originalQuestion"\n\n'
        'Search Results:\n$searchResult\n\n'
        'Task: Answer the user\'s question naturally in Thai based on the search results above. '
        'Be helpful, concise, and friendly. Use emoji if appropriate.\n\n'
        'Reply in Thai (1-2 sentences):';

    final isCloud = LLMProviderManager().activeType != ProviderType.onDevice;
    if (isCloud) return core;
    return '<start_of_turn>user\n$core\n<end_of_turn>\n<start_of_turn>model\n';
  }

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

  /// 📝 สร้าง Prompt สำหรับ Trigger — universal (cloud + on-device)
  Future<String> _buildTriggerPrompt(TriggerEvent trigger) async {
    final isCloud = LLMProviderManager().activeType != ProviderType.onDevice;

    if (isCloud) {
      // Cloud: plain prompt — ไม่ inject ContextRetriever dump
      // (English log entries ใน context ทำให้ cloud LLM echo กลับแทน Thai greeting)
      final suggestion = trigger.suggestedMessage ?? 'สวัสดีค่ะ';
      return 'You are Haku, a warm Thai AI life companion.\n\n'
          'Task: Respond naturally in Thai (1-2 sentences, friendly, with emoji).\n'
          'Based on: $suggestion\n\n'
          'Reply in Thai only:';
    }

    // On-device: Gemma format + full context
    final triggerContextStr = ContextRetriever().buildContextString(trigger.context);
    final fullContextData = await ContextRetriever().retrieveFullContext();
    final fullContextStr = ContextRetriever().buildContextString(fullContextData);
    final ragContext = trigger.payloadJson?['ragContext'] as String?;
    final combinedContext = [
      if (fullContextStr.isNotEmpty) fullContextStr,
      if (ragContext != null && ragContext.isNotEmpty) 'Recent diary:\n$ragContext',
    ].join('\n\n');

    return PromptBuilder.buildProactivePrompt(
      triggerContext: triggerContextStr,
      suggestedMessage: trigger.suggestedMessage ?? 'สวัสดีค่ะ',
      context: combinedContext.isNotEmpty ? combinedContext : null,
    );
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

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isTyping = false;
  bool _contextEnabled = true;
  List<XFile> _pendingImages = [];
  Timer? _midnightTimer;
  StreamSubscription<TriggerEvent>? _triggerStreamSub;
  bool _mcpConfigured = false;
  int _mcpToolCount = 0;

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
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialQuestion != null) {
        _sendQuickQuestionByText(widget.initialQuestion!);
      }
    });
  }

  /// 🔄 เริ่ม LiteRT Conversation session ใหม่
  /// รีเซ็ต KV cache + ตั้ง system instruction + inject resume + 3-day schedule
  Future<void> _startNewLiteRTSession() async {
    final provider = LLMProviderManager().provider;
    if (provider is! LiteRTLLMProvider) return;

    provider.resetConversation();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rangeEnd = today.add(const Duration(days: 3));

    final results = await Future.wait([
      SessionResumeService().buildResume(),
      SchedulerService().getCalendarEvents(today, rangeEnd),
    ]);

    final resume = results[0] as String;
    final events = results[1] as List<Map<String, dynamic>>;

    final scheduleBlock = PromptBuilder.buildScheduleBlock(events);
    final base = PromptBuilder.buildSystemInstruction();
    final full = [base, if (resume.isNotEmpty) resume, if (scheduleBlock.isNotEmpty) scheduleBlock]
        .join('\n\n');

    provider.setSystemInstruction(full);

    // ส่ง resume + schedule ไปเก็บใน ChatNotifier ด้วย — ใช้ inject เข้า cloud prompt
    ref.read(chatHistoryProvider.notifier).updateSystemContext(resume, scheduleBlock);

    debugPrint('🔄 LiteRT session ใหม่ — resume: ${resume.length} chars, events: ${events.length}');

    // ตั้ง timer รีเฟรช session เมื่อเที่ยงคืน (วันใหม่ → ตารางใหม่)
    _midnightTimer?.cancel();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final untilMidnight = midnight.difference(DateTime.now());
    _midnightTimer = Timer(untilMidnight, _startNewLiteRTSession);
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

      // รีเซ็ต stateful Conversation + inject LTM resume เมื่อเริ่ม session ใหม่
      await _startNewLiteRTSession();

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

      // Initialize Device Command Notification Handler (confirm/deny actions)
      DeviceCommandNotificationHandler().initialize();

      // Trigger wiring ย้ายไปที่ AppEntryPoint (main.dart) แล้ว
      // ChatScreen รอรับ trigger events ผ่าน NotificationService.onNotificationTap
      debugPrint('✅ All chat services initialized');

      // โหลด MCP status
      await _loadMcpStatus();

      // 📍 เริ่ม Geofence + DwellTracker monitoring (foreground เท่านั้น)
      debugPrint('🔄 Starting Geofence monitoring...');
      await GeofenceService().initialize();
      await GeofenceService().startMonitoring();
      debugPrint('✅ Geofence monitoring started');

      // 🎭 Wire preset change → chat message + notification
      PresetService().onPresetChanged = (oldPreset, newPreset) {
        debugPrint('🎭 Preset changed: ${oldPreset.name} → ${newPreset.name}');
        // Add proactive message to chat
        ref.read(chatHistoryProvider.notifier).addMessage(
          ChatMessage.proactive(
            '${newPreset.icon} ${newPreset.behavior.greeting}',
            triggerTitle: newPreset.name,
          ),
        );
        // Send local notification
        NotificationService().showPresetNotification(
          oldPresetName: oldPreset.name,
          newPresetName: newPreset.name,
          newPresetIcon: newPreset.icon,
          greeting: newPreset.behavior.greeting,
        );
      };

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
    await ref.read(chatHistoryProvider.notifier).sendToAI(reply, context: context);

    // Scroll ไปล่างสุด
    _scrollToBottom();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      DeviceCommandNotificationHandler().processPendingQueue();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _triggerStreamSub?.cancel();
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

  /// 📔 Photo→Auto-log — AI วิเคราะห์รูปแล้วบันทึกเป็น diary entry อัตโนมัติ
  Future<void> _autoLogPhoto(XFile imageFile) async {
    setState(() => _isTyping = true);
    try {
      final imageBytes = await imageFile.readAsBytes();

      // GPS → area name (non-blocking, ใช้ lastKnownPosition ก่อน)
      String? locationName;
      final pos = GeofenceService().lastKnownPosition ??
          await LocationService.getCurrentPosition();
      if (pos != null) {
        final addr = await NominatimService()
            .reverseGeocode(pos.latitude, pos.longitude);
        locationName = addr?.toString();
      }

      // AI บรรยายภาพเป็นภาษาไทย สั้น 1–2 ประโยค
      final llm = LLMProviderManager().provider;
      const descPrompt = 'บรรยายภาพนี้สั้นๆ ในภาษาไทย 1–2 ประโยค สำหรับบันทึกไดอารี่ส่วนตัว';
      String description;
      if (llm is LiteRTLLMProvider) {
        description = await llm.generateTurnWithImages(descPrompt, [imageBytes]);
      } else {
        description = await llm.generate(descPrompt);
      }
      if (description.trim().isEmpty) description = '📷 บันทึกรูปภาพ';

      // บันทึก diary entry
      final entry = Entry(
        content: description.trim(),
        createdAt: DateTime.now(),
        locationName: locationName,
        tags: ['photo', 'auto-log'],
      );
      await DatabaseHelper.instance.createEntry(entry);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('บันทึกแล้ว: ${description.substring(0, description.length.clamp(0, 60))}…'),
          backgroundColor: const Color(0xFF2C2C2E),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      debugPrint('❌ _autoLogPhoto error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกไม่สำเร็จ กรุณาลองใหม่')),
        );
      }
    } finally {
      setState(() => _isTyping = false);
    }
  }

  Future<void> _loadMcpStatus() async {
    final mcp = McpService();
    await mcp.loadSettings();
    if (mounted) {
      setState(() {
        _mcpConfigured = mcp.isConfigured;
        _mcpToolCount = mcp.tools.length;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _imagePicker.pickImage(source: source, imageQuality: 85);
    if (picked != null) setState(() => _pendingImages = [..._pendingImages, picked]);
  }

  // ── MCP Status Chip ──────────────────────────────────────────
  Widget _buildMcpChip() {
    final label = _mcpConfigured
        ? (_mcpToolCount > 0 ? 'MCP · $_mcpToolCount tools' : 'MCP · connected')
        : 'MCP · ไม่ได้ตั้งค่า';
    final color = _mcpConfigured ? kOk : kFg4;
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: _showMcpSheet,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withAlpha(_mcpConfigured ? 25 : 18),
            borderRadius: BorderRadius.circular(kRPill),
            border: Border.all(color: color.withAlpha(_mcpConfigured ? 90 : 55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.electric_bolt_rounded, size: 11, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Feature Guide Sheet ─────────────────────────────────────
  void _showCapabilitiesSheet({
    required bool supportsVision,
    required bool supportsThinking,
    required String modelLabel,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CapabilitiesSheet(
        modelLabel: modelLabel,
        supportsVision: supportsVision,
        supportsThinking: supportsThinking,
        onTryVision: () {
          Navigator.pop(context);
          _showImageSourceSheet();
        },
      ),
    );
  }

  void _showMcpSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _McpSheet(
        onStatusChanged: (bool configured, int toolCount) {
          if (mounted) setState(() { _mcpConfigured = configured; _mcpToolCount = toolCount; });
        },
      ),
    );
  }

  void _showImageSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: kCrystal400),
              title: const Text('ถ่ายภาพ', style: TextStyle(color: kFg1)),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: kCrystal400),
              title: const Text('เลือกจากแกลเลอรี', style: TextStyle(color: kFg1)),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final images = List<XFile>.from(_pendingImages);
    if (text.isEmpty && images.isEmpty) return;

    _messageController.clear();
    setState(() {
      _pendingImages = [];
      _isTyping = true;
    });

    List<Uint8List>? imageBytes;
    List<String>? imagePaths;
    if (images.isNotEmpty) {
      imageBytes = await Future.wait(images.map((f) => f.readAsBytes()));
      imagePaths = images.map((f) => f.path).toList();
    }

    if (!mounted) return;
    await ref.read(chatHistoryProvider.notifier).sendToAI(
      text.isEmpty ? '📷 วิเคราะห์รูปภาพนี้หน่อยได้ไหม?' : text,
      useContext: _contextEnabled,
      images: imageBytes,
      imagePaths: imagePaths,
      context: context,
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
        final mcp = McpService();
        await mcp.loadSettings();

        if (!mcp.isConfigured) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('กรุณาตั้งค่า MCP Server URL ก่อนนะคะ'),
              ),
            );
          }
          return;
        }

        setState(() => _isTyping = true);
        try {
          final connected = await mcp.connect();
          if (connected) {
            final result = await mcp.search(searchText);
            if (result != null && result.isNotEmpty && mounted) {
              await ref
                  .read(chatHistoryProvider.notifier)
                  .sendToAI('ค้นหาข้อมูลเกี่ยวกับ $searchText', context: context);
            }
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('เชื่อมต่อ MCP Server ไม่ได้')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('ค้นหาล้มเหลว: $e')),
            );
          }
        } finally {
          if (mounted) setState(() => _isTyping = false);
          _scrollToBottom();
        }
      }
      return;
    }

    if (question.actionType == 'open_vision') {
      _showImageSourceSheet();
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
    await ref.read(chatHistoryProvider.notifier).sendToAI(question.query, context: context);
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

    // ดึง model capabilities จาก LiteRTLLMProvider (ถ้าใช้ on-device)
    final liteRT = llmService is LiteRTLLMProvider ? llmService : null;
    final modelCfg = liteRT?.modelConfig;
    final supportsVision = modelCfg?.supportsVision ?? false;
    final supportsThinking = modelCfg?.supportsThinking ?? false;
    final modelLabel = llmService.isInitialized
        ? (modelCfg?.displayName ?? LLMProviderManager().providerName)
        : 'Gemma 4';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: HakuGlassAppBar(
        title: Row(
          children: [
            const HakuCrystalCore(size: 36),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Eyebrow chip — tappable capability badge
                GestureDetector(
                  onTap: () => _showCapabilitiesSheet(
                    supportsVision: supportsVision,
                    supportsThinking: supportsThinking,
                    modelLabel: modelLabel,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: kCrystal400.withAlpha(46),
                      borderRadius: BorderRadius.circular(kRPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          modelLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: kCrystal600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (supportsVision) ...[
                          const SizedBox(width: 5),
                          const Text('👁', style: TextStyle(fontSize: 9)),
                        ],
                        if (supportsThinking) ...[
                          const SizedBox(width: 2),
                          const Text('💭', style: TextStyle(fontSize: 9)),
                        ],
                        const SizedBox(width: 3),
                        const Icon(Icons.info_outline_rounded, size: 9, color: kCrystal500),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                const Text('Haku AI',
                    style: TextStyle(fontSize: 20, color: kFg1, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
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
                          'โหมดออฟไลน์: วางไฟล์ .litertlm ในโฟลเดอร์ Downloads/ หรือเลือกผ่านการตั้งค่า',
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

  Widget _buildQuickQuestions() {
    final provider = LLMProviderManager().provider;
    final visionSupported = provider is LiteRTLLMProvider
        ? provider.modelConfig.supportsVision
        : false;

    final questions = [
      ..._quickQuestions,
      if (visionSupported)
        QuickQuestion(
          icon: Icons.photo_camera_outlined,
          text: '📷 วิเคราะห์รูป',
          query: '',
          actionType: 'open_vision',
        ),
    ];

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: questions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final question = questions[index];
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
  }

  Widget _buildInputArea() => Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: const BoxDecoration(
        color: kGlassFillSoft,
        border: Border(top: BorderSide(color: kGlassEdge, width: 1)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Image preview strip + auto-log chip ─────────────
            if (_pendingImages.isNotEmpty) ...[
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _pendingImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_pendingImages[i].path),
                          width: 72, height: 72, fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 0, right: 0,
                        child: GestureDetector(
                          onTap: () => setState(() =>
                            _pendingImages = List.from(_pendingImages)..removeAt(i)),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.book_outlined, size: 14, color: kCrystal400),
                      label: const Text('บันทึก diary', style: TextStyle(fontSize: 12, color: kFg1)),
                      backgroundColor: kGlassFill,
                      side: const BorderSide(color: kGlassStroke),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final img = _pendingImages.first;
                        setState(() => _pendingImages = []);
                        _autoLogPhoto(img);
                      },
                    ),
                  ],
                ),
              ),
            ],
            // ── MCP status chip ──────────────────────────────────
            _buildMcpChip(),
            // ── Input row ────────────────────────────────────────
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  color: _pendingImages.isNotEmpty ? kCrystal400 : kFg3,
                  onPressed: _showImageSourceSheet,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: kFg1),
                    decoration: InputDecoration(
                      hintText: _pendingImages.isNotEmpty ? 'พิมพ์คำถามเพิ่ม (ไม่บังคับ)' : 'ถามฮาคุสิ...',
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
                        width: 48, height: 48,
                        child: Center(
                          child: SizedBox(
                            width: 24, height: 24,
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
                  left: BorderSide(color: kGlassEdge, width: 0.5),
                  right: BorderSide(color: kGlassEdge, width: 0.5),
                  bottom: BorderSide(color: kGlassEdge, width: 0.5),
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

    // 🛡️ Device Command Confirmation Card
    if (message.isConfirmationCard) {
      return DeviceCommandConfirmationCard(
        command: message.command ?? 'unknown',
        params: message.params ?? const {},
        onConfirmed: () {
          // ลบ card ออกจาก chat หลังยืนยัน (optional)
          // หรือแสดง success message
        },
        onCancelled: () {
          // ลบ card ออกจาก chat หลังยกเลิก (optional)
        },
      );
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
                        left: BorderSide(color: kGlassEdge, width: 0.5),
                        right: BorderSide(color: kGlassEdge, width: 0.5),
                        bottom: BorderSide(color: kGlassEdge, width: 0.5),
                      ),
              ),
              child: Builder(builder: (context) {
                // Parse <think>...</think> or <thinking>...</thinking> block
                // THaLLE / DeepSeek-R1 style models use <think>, Gemma 4 uses <thinking>
                final raw = message.content;
                final thinkMatch = RegExp(
                  r'<think(?:ing)?>([\s\S]*?)<\/think(?:ing)?>',
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
                    // รูปภาพที่แนบมากับข้อความ (user bubble เท่านั้น)
                    if (isUser && message.imagePaths != null && message.imagePaths!.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: message.imagePaths!.map((path) => ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(path),
                            width: 160, height: 160, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 160, height: 160,
                              color: kGlassFill,
                              child: const Icon(Icons.broken_image_outlined, color: kFg3),
                            ),
                          ),
                        )).toList(),
                      ),
                      if (reply.isNotEmpty) const SizedBox(height: 8),
                    ],
                    if (reply.isNotEmpty)
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
                  left: BorderSide(color: kGlassEdge, width: 0.5),
                  right: BorderSide(color: kGlassEdge, width: 0.5),
                  bottom: BorderSide(color: kGlassEdge, width: 0.5),
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
                const Text(
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

// ══════════════════════════════════════════════════════════════
// 🔌 MCP Config Sheet — ตั้งค่าและทดสอบ MCP Server
// ══════════════════════════════════════════════════════════════

class _McpSheet extends StatefulWidget {
  final void Function(bool configured, int toolCount) onStatusChanged;
  const _McpSheet({required this.onStatusChanged});

  @override
  State<_McpSheet> createState() => _McpSheetState();
}

class _McpSheetState extends State<_McpSheet> {
  late TextEditingController _urlCtrl;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  List<String> _toolNames = [];

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: McpService().serverUrl ?? '');
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() { _testing = true; _testResult = null; _toolNames = []; });
    try {
      await McpService().saveServerUrl(url);
      final ok = await McpService().connect();
      final tools = McpService().tools.map((t) => t.name).toList();
      setState(() {
        _testing = false;
        _testOk = ok;
        _toolNames = tools;
        _testResult = ok
            ? 'เชื่อมต่อสำเร็จ · ${tools.length} tools'
            : 'เชื่อมต่อไม่สำเร็จ';
      });
      widget.onStatusChanged(ok, tools.length);
    } catch (e) {
      setState(() {
        _testing = false;
        _testOk = false;
        _testResult = 'Error: $e';
      });
    }
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    await McpService().saveServerUrl(url);
    widget.onStatusChanged(url.isNotEmpty, McpService().tools.length);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: kFg4.withAlpha(100),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: kCrystal400.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.electric_bolt_rounded, size: 18, color: kCrystal400),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MCP Server', style: TextStyle(color: kFg1, fontSize: 16, fontWeight: FontWeight.w600)),
                  Text('Model Context Protocol', style: TextStyle(color: kFg3, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          // URL field
          TextField(
            controller: _urlCtrl,
            style: const TextStyle(color: kFg1, fontSize: 14),
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'http://localhost:3000',
              hintStyle: TextStyle(color: kFg4.withAlpha(160)),
              filled: true,
              fillColor: kGlassFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kGlassStroke),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kGlassStroke),
              ),
              prefixIcon: const Icon(Icons.link, size: 18, color: kFg3),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          // Test result
          if (_testResult != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (_testOk ? kOk : kErr).withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (_testOk ? kOk : kErr).withAlpha(80)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_testOk ? Icons.check_circle_outline : Icons.error_outline,
                          size: 14, color: _testOk ? kOk : kErr),
                      const SizedBox(width: 6),
                      Text(_testResult!,
                          style: TextStyle(fontSize: 13, color: _testOk ? kOk : kErr)),
                    ],
                  ),
                  if (_toolNames.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6, runSpacing: 4,
                      children: _toolNames.map((name) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: kCrystal400.withAlpha(25),
                          borderRadius: BorderRadius.circular(kRPill),
                          border: Border.all(color: kCrystal400.withAlpha(60)),
                        ),
                        child: Text(name, style: const TextStyle(fontSize: 11, color: kCrystal400)),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
          if (_testResult != null) const SizedBox(height: 12),
          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: kCrystal400))
                      : const Icon(Icons.wifi_tethering, size: 16),
                  label: Text(_testing ? 'กำลังทดสอบ...' : 'ทดสอบ'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kCrystal400,
                    side: const BorderSide(color: kGlassStroke),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: kCrystal500,
                    foregroundColor: kFgOnCyan,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('บันทึก'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 🌟 Capabilities Sheet — Feature Guide สำหรับ Gemma 4
// ══════════════════════════════════════════════════════════════

class _CapabilitiesSheet extends StatelessWidget {
  final String modelLabel;
  final bool supportsVision;
  final bool supportsThinking;
  final VoidCallback onTryVision;

  const _CapabilitiesSheet({
    required this.modelLabel,
    required this.supportsVision,
    required this.supportsThinking,
    required this.onTryVision,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: kFg4.withAlpha(100),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kCrystal400.withAlpha(30),
                  borderRadius: BorderRadius.circular(kRPill),
                  border: Border.all(color: kCrystal400.withAlpha(60)),
                ),
                child: Text(
                  modelLabel,
                  style: const TextStyle(fontSize: 12, color: kCrystal400, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              const Text('ความสามารถพิเศษ',
                  style: TextStyle(color: kFg1, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 20),

          // Vision
          if (supportsVision) ...[
            _FeatureCard(
              emoji: '👁',
              title: 'Vision — วิเคราะห์รูปภาพ',
              accentColor: kCrystal400,
              steps: const [
                'แตะ 📷 ในช่อง input ด้านล่าง',
                'เลือกรูปจากแกลเลอรีหรือถ่ายใหม่',
                'พิมพ์คำถาม (ไม่บังคับ) แล้วกดส่ง',
              ],
              examples: const [
                '"อาหารในรูปคืออะไร?"',
                '"แปลข้อความในรูปให้หน่อย"',
                '"สรุปเนื้อหาในสไลด์นี้"',
              ],
              action: FilledButton.icon(
                onPressed: onTryVision,
                icon: const Icon(Icons.photo_camera_outlined, size: 16),
                label: const Text('ลองเลย — เปิดกล้อง'),
                style: FilledButton.styleFrom(
                  backgroundColor: kCrystal500,
                  foregroundColor: kFgOnCyan,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Thinking
          if (supportsThinking) ...[
            const _FeatureCard(
              emoji: '💭',
              title: 'Thinking Mode — คิดก่อนตอบ',
              accentColor: kVividMint,
              steps: [
                'ถามคำถามซับซ้อนหรือขอให้วิเคราะห์',
                'Gemma 4 จะคิดทบทวนก่อนส่งคำตอบ',
                'แตะ "💭 reasoning" เหนือคำตอบเพื่อดูกระบวนการคิด',
              ],
              examples: [
                '"ช่วยวางแผนการเรียนสัปดาห์หน้าให้หน่อย"',
                '"วิเคราะห์นิสัยจากบันทึกของฉัน"',
                '"แก้โจทย์คณิตศาสตร์นี้ให้หน่อย"',
              ],
              note: 'ทำงานอัตโนมัติ — ไม่ต้องตั้งค่าอะไรเพิ่ม',
            ),
            const SizedBox(height: 14),
          ],

          if (!supportsVision && !supportsThinking)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'โมเดลปัจจุบัน ($modelLabel) ยังไม่รองรับ Vision หรือ Thinking Mode\nลองเปลี่ยนเป็น Gemma 4 E2B/E4B ในการตั้งค่า',
                style: const TextStyle(color: kFg3, fontSize: 13, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String emoji;
  final String title;
  final Color accentColor;
  final List<String> steps;
  final List<String> examples;
  final Widget? action;
  final String? note;

  const _FeatureCard({
    required this.emoji,
    required this.title,
    required this.accentColor,
    required this.steps,
    required this.examples,
    this.action,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: accentColor.withAlpha(12),
        borderRadius: BorderRadius.circular(kR4),
        border: Border.all(color: accentColor.withAlpha(60)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: accentColor, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Steps
          ...steps.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 16, height: 16,
                  margin: const EdgeInsets.only(top: 1, right: 8),
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${e.key + 1}',
                        style: TextStyle(fontSize: 9, color: accentColor, fontWeight: FontWeight.w700)),
                  ),
                ),
                Expanded(child: Text(e.value, style: const TextStyle(color: kFg1, fontSize: 13))),
              ],
            ),
          )),

          const SizedBox(height: 10),

          // Examples
          Text('ตัวอย่าง:', style: TextStyle(color: accentColor.withAlpha(200), fontSize: 11,
              fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6, runSpacing: 4,
            children: examples.map((ex) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: kGlassFill,
                borderRadius: BorderRadius.circular(kRPill),
                border: Border.all(color: kGlassStroke),
              ),
              child: Text(ex, style: const TextStyle(color: kFg2, fontSize: 11)),
            )).toList(),
          ),

          if (note != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 12, color: accentColor.withAlpha(180)),
                const SizedBox(width: 4),
                Text(note!, style: TextStyle(color: accentColor.withAlpha(180), fontSize: 11)),
              ],
            ),
          ],

          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}
