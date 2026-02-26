import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
import '../services/llm_provider_manager.dart';
import '../services/prompt_builder.dart';
import '../services/secret_chat_service.dart';
import '../services/smart_preprocessor.dart';
import '../services/web_search_service.dart';

/// 💬 หน้าแชทกับ AI (Haku Assistant) - Phase 2: Real LLM
/// 
/// คุยกับ AI ที่รู้จักข้อมูลของคุณจาก Journal
/// รองรับ RAG (ค้นหาบันทึก) + LLM (ตอบคำถาม)

// Provider สำหรับเก็บประวัติแชท
final chatHistoryProvider = StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) => ChatNotifier());

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  ChatNotifier() : super([
    ChatMessage.welcome(),
  ]);

  void addMessage(ChatMessage message) {
    state = [...state, message];
    
    // 🔋 บันทึกประวัติแชทสำหรับสรุปแบบ Deferred (ไม่กินแบต)
    if (!message.isLoading && !message.isError) {
      ChatSummaryService().logChatMessage(
        message: message.content,
        isUser: message.isUser,
        intent: message.isProactive ? 'proactive' : 'chat',
      );
    }
  }

  /// 🔧 Extract response text from JSON or plain text
  String _extractResponseText(String response) {
    try {
      // 🧹 Strip Gemma template tokens ที่รั่วออกมาจาก cloud models
      var cleanResponse = PromptBuilder.cleanResponse(response);

      // ลบ Markdown code block ถ้ามี
      if (cleanResponse.startsWith('```json')) {
        cleanResponse = cleanResponse.substring(7);
      }
      if (cleanResponse.endsWith('```')) {
        cleanResponse = cleanResponse.substring(0, cleanResponse.length - 3);
      }
      cleanResponse = cleanResponse.trim();
      
      // ลอง parse JSON
      final json = jsonDecode(cleanResponse) as Map<String, dynamic>;
      
      // ถ้ามี response field ให้ return ค่านั้น
      if (json.containsKey('response')) {
        return json['response'] as String;
      }
      
      // ถ้าไม่มี response field ให้ return ทั้งก้อน
      return response;
    } catch (e) {
      // ถ้า parse ไม่ได้ แสดงว่าเป็น plain text อยู่แล้ว
      return response;
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
        await preprocessor.addToLeanContext(userMessage, isUser: true);
        await preprocessor.addToLeanContext(quickAction.response, isUser: false);
        return;
      }

      // ──────────────────────────────────────────────────────
      // 1. SmartPreprocessor (rule-based workers, 0 LLM tokens)
      // ──────────────────────────────────────────────────────
      if (useContext) {
        try {
          debugPrint('🧠 Running SmartPreprocessor...');
          preprocessResult = await preprocessor.preprocess(
            userMessage,
            useLeanContext: true,
          );
          contextStr = preprocessResult.enrichedContext;
          debugPrint('✅ Preprocessing complete:');
          debugPrint('   - Intent: ${preprocessResult.detectedIntent}');
          debugPrint('   - Context length: ${contextStr.length}');
          debugPrint('   - Worker results: ${preprocessResult.workerResults.getSummary()}');

          await preprocessor.addToLeanContext(userMessage, isUser: true);
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
            ChatMessage.searching('รับทราบค่ะ กำลังค้นหาให้นะคะ... 🔍'));

        // Execute web search
        final searchQuery = preprocessResult!.searchQuery ?? userMessage;
        ManagerDispatchService.markSearched(searchQuery); // dedup
        String? webResult;
        try {
          final webService = WebSearchService();
          await webService.initialize();
          webResult = await webService.searchForAI(searchQuery);
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
          response = webResult ?? 'ไม่พบข้อมูลค่ะ';
        }

        // Replace searching message with real response
        state = state.where((m) => !m.isSearching).toList();
        addMessage(ChatMessage.assistant(
          response,
          sources: useContext ? _extractSources(contextStr) : null,
        ));

        // Save to lean context
        if (response.isNotEmpty) {
          await SmartPreprocessor()
              .addToLeanContext(response, isUser: false);
        }
      } else {
        // ──────────────────────────────────────────────────────
        // PATH B: General message — Secret Chat First Architecture
        //
        // Step 1: PreClassify (LLM) if rule-based intent = general
        //   → language-agnostic intent detection
        //   → Face gets context hint for correct response
        // Step 2: Face LLM — Thai natural response + intent hint
        // Step 3: [async] logExchange reuses preClassify (0 extra LLM call)
        // ──────────────────────────────────────────────────────

        // 1. PreClassify — runs only when rule-based couldn't classify
        PreClassifyResult? preClassify;
        final ruleIntent = preprocessResult?.detectedIntent ?? DetectedIntent.general;
        if (llm.isInitialized && ruleIntent == DetectedIntent.general) {
          debugPrint('🔬 PreClassify: rule-based missed, asking LLM...');
          preClassify = await SecretChatService().preClassify(userMessage);
          if (preClassify != null && preClassify.contextHint.isNotEmpty) {
            // Inject intent hint at front of context for Face
            contextStr = '${preClassify.contextHint}\n$contextStr';
            debugPrint('🔬 PreClassify injected: ${preClassify.contextHint}');
          }
        }

        // 2. Face LLM — Stage 1 (The Face)
        debugPrint('🎭 Stage 1 (The Face): generating natural response...');

        if (llm.isInitialized) {
          try {
            final isCloud = LLMProviderManager().activeType != ProviderType.onDevice;
            final prompt = isCloud
                ? PromptBuilder.buildCloudPrompt(
                    userMessage: userMessage,
                    context: contextStr.isNotEmpty ? contextStr : null,
                  )
                : PromptBuilder.buildGemmaPrompt(
                    userMessage: userMessage,
                    context: contextStr.isNotEmpty ? contextStr : null,
                  );
            response = await llm.generate(prompt);
          } catch (e) {
            response = null;
          }
        }

        // Fallback to mock
        if (response == null || response.isEmpty) {
          response = await AIService.getMockResponse(userMessage);
        }

        final displayText = _extractResponseText(response);

        // แสดงคำตอบ
        state = state.where((m) => !m.isLoading).toList();
        addMessage(ChatMessage.assistant(
          displayText,
          sources: useContext ? _extractSources(contextStr) : null,
        ));

        // Save to lean context
        await SmartPreprocessor()
            .addToLeanContext(displayText, isUser: false);

        // 3. [async] Secret Chat log — reuses preClassify (0 extra LLM call)
        if (llm.isInitialized) {
          _runSecretChat(userMessage, displayText, preClassify: preClassify);
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

  /// 🧠 Stage 2: Big Manager — async after Stage 1
  /// 🤫 Secret Chat: แปล Thai exchange → English log → Big Manager dispatch
  ///
  /// ทำ async หลัง Face ตอบ (ไม่ block UI)
  /// Big Manager ใช้ intent จาก extraction result โดยตรง (0 LLM calls เพิ่ม)
  void _runSecretChat(
    String userMessage,
    String aiResponse, {
    PreClassifyResult? preClassify,
  }) {
    Future(() async {
      try {
        debugPrint('🤫 Secret Chat: translating exchange...');
        final secretChat = SecretChatService();
        final logEntry = await secretChat.logExchange(
          userMessage: userMessage,
          aiResponse: aiResponse,
          preClassifyResult: preClassify,
        );

        if (logEntry != null) {
          debugPrint('🤫 Secret Chat done: ${logEntry.summaryEn}');
          // 📦 Replace Thai lean context with compact English (saves ~3-5x tokens)
          SmartPreprocessor().updateLeanContextWithEnglish(logEntry.summaryEn);
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



  /// 🔗 ดึง sources จาก context
  List<String>? _extractSources(String context) {
    if (context.contains('ไม่พบบันทึก')) return null;
    
    // ดึงวันที่จาก context
    final dates = RegExp(r'\d{4}-\d{2}-\d{2}')
        .allMatches(context)
        .map((m) => m.group(0))
        .whereType<String>()
        .toList();
    
    return dates.isEmpty ? null : dates;
  }

  /// 📅 สรุปวันนี้ (Quick Action)
  Future<void> summarizeToday() async {
    addMessage(ChatMessage.user('สรุปวันนี้ให้หน่อย'));
    addMessage(ChatMessage.loading());

    try {
      // ดึง entries วันนี้
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      
      final allEntries = await DatabaseHelper.instance.getAllEntries();
      final todayEntries = allEntries.where((e) => 
        e.createdAt.isAfter(startOfDay) && e.createdAt.isBefore(endOfDay)
      ).toList();

      if (todayEntries.isEmpty) {
        state = state.where((m) => !m.isLoading).toList();
        addMessage(ChatMessage.assistant('วันนี้คุณยังไม่มีบันทึกเลยค่ะ 📝'));
        return;
      }

      // สร้าง context และ prompt (Gemma-3 format)
      final entriesContent = todayEntries.map((e) =>
        '- ${e.createdAt.hour}:${e.createdAt.minute.toString().padLeft(2, '0')}: ${e.content}'
      ).join('\n');

      final prompt = PromptBuilder.buildDailySummaryPrompt(
        entriesContent: entriesContent,
        period: 'วันนี้',
      );

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
        // Mock response เมื่อ LLM ไม่พร้อม
        response = 'วันนี้คุณมี ${todayEntries.length} บันทึก ${todayEntries.any((e) => e.mood == 5) ? 'ดูเหมือนจะเป็นวันที่ดีนะคะ 😊' : 'เหนื่อยหน่อยแต่ก็ผ่านไปได้ค่ะ 💪'}';
      }

      state = state.where((m) => !m.isLoading).toList();
      addMessage(ChatMessage.assistant(response));

    } catch (e) {
      state = state.where((m) => !m.isLoading).toList();
      addMessage(ChatMessage.error('สรุปไม่ได้ค่ะ: $e'));
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
    QuickQuestion(icon: '📅', text: 'สรุปวันนี้', query: 'summarize_today', isAction: true),
    QuickQuestion(icon: '🍜', text: 'วันนี้กินอะไร?', query: 'วันนี้ฉันกินอะไรไปบ้าง?'),
    QuickQuestion(icon: '😊', text: 'วันนี้เป็นยังไง?', query: 'สรุปวันนี้ของฉันหน่อย'),
    QuickQuestion(icon: '📍', text: 'ไปไหนมาบ้าง?', query: 'วันนี้ฉันไปที่ไหนบ้าง?'),
    QuickQuestion(icon: '🎵', text: 'อารมณ์ดีไหม?', query: 'ช่วงนี้อารมณ์ฉันเป็นยังไง?'),
    QuickQuestion(icon: '🔍', text: 'หาเรื่อง...', query: '', isCustom: true),
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

      // 📝 NOTE: LLM จะถูกโหลดแบบ Lazy Loading
      // เมื่อมีการเรียก generate() ครั้งแรกเท่านั้น
      // ไม่โหลดตอน initState เพื่อประหยัดแบตเตอรี่
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
      FocusScope.of(context).requestFocus(FocusNode());
      return;
    }

    if (question.isAction && question.query == 'summarize_today') {
      setState(() => _isTyping = true);
      await ref.read(chatHistoryProvider.notifier).summarizeToday();
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
      orElse: () => QuickQuestion(icon: '❓', text: questionText, query: questionText),
    );

    await _sendQuickQuestion(question);
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatHistoryProvider);
    final llmService = LLMProviderManager().provider;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9B7CB6), Color(0xFF6B4E71)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Text('箱', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Haku AI', style: TextStyle(fontSize: 16)),
                Text(
                  llmService.isInitialized ? '${LLMProviderManager().providerName} 🟢' : 'Mock Mode 🟡',
                  style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Toggle Context
          IconButton(
            icon: Icon(_contextEnabled ? Icons.psychology : Icons.psychology_outlined),
            tooltip: _contextEnabled ? 'Context: ON' : 'Context: OFF',
            onPressed: () {
              setState(() => _contextEnabled = !_contextEnabled);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_contextEnabled ? 'บริบทอัจฉริยะ: เปิด' : 'บริบทอัจฉริยะ: ปิด')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Bar
          if (!llmService.isInitialized)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              color: Colors.orange.withValues(alpha: 0.12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.orange.shade300),
                  const SizedBox(width: 8),
                  Text(
                    'โหมดออฟไลน์: วางไฟล์ .task ในโฟลเดอร์ models/',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade300),
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
            avatar: Text(question.icon),
            label: Text(question.text),
            backgroundColor: const Color(0xFF2A2A3E),
            side: BorderSide.none,
            labelStyle: const TextStyle(color: Colors.white),
            onPressed: () => _sendQuickQuestion(question),
          );
        },
      ),
    );

  Widget _buildInputArea() => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.mic_none),
              color: Colors.white60,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ฟีเจอร์เสียงจะมาใน Phase 2.5')),
                );
              },
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'ถามฮาคุสิ...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  filled: true,
                  fillColor: const Color(0xFF2A2A3E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
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
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9B7CB6)),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.send),
                    color: const Color(0xFF9B7CB6),
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
                color: const Color(0xFF2A2A3E),
                borderRadius: BorderRadius.circular(20),
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
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF9B7CB6), Color(0xFF6B4E71)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(child: Text('箱', style: TextStyle(fontSize: 14))),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF9B7CB6) : const Color(0xFF2A2A3E),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.white.withValues(alpha: 0.9),
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
                        color: Colors.white.withValues(alpha: 0.4),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    timeFormat.format(message.timestamp),
                    style: TextStyle(
                      color: isUser ? Colors.white.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.4),
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

  Widget _buildDot(int index) => AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4 + (index * 0.2)),
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
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF9B7CB6), Color(0xFF6B4E71)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
                child: Text('箱', style: TextStyle(fontSize: 14))),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF2A2A3E),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(20),
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
                          color: Color(0xFF9B7CB6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          message.content,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
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
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
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
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFFA726), Color(0xFFFF7043)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(child: Text('🔔', style: TextStyle(fontSize: 14))),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A3E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFA726).withAlpha(100)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.triggerTitle != null) ...[
                    Text(
                      message.triggerTitle!,
                      style: const TextStyle(
                        color: Color(0xFFFFA726),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    message.content,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeFormat.format(message.timestamp),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
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

class QuickQuestion {
  final String icon;
  final String text;
  final String query;
  final bool isCustom;
  final bool isAction;

  QuickQuestion({
    required this.icon,
    required this.text,
    required this.query,
    this.isCustom = false,
    this.isAction = false,
  });
}
