import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/context_retriever.dart';
import '../services/database_helper.dart';
import '../services/llm_service.dart';
import '../services/mvp_trigger_service.dart';
import '../services/rag_service.dart';

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
  }

  /// 🤖 ส่งข้อความไปให้ AI พร้อม Context Retriever
  Future<void> sendToAI(String userMessage, {bool useContext = true}) async {
    // เพิ่มข้อความผู้ใช้
    addMessage(ChatMessage.user(userMessage));
    
    // แสดง "กำลังพิมพ์..."
    addMessage(ChatMessage.loading());

    try {
      String contextStr = '';
      
      // 🧠 Context Retriever: ดึงข้อมูลจากหลายแหล่ง
      if (useContext) {
        try {
          final contextData = await ContextRetriever().retrieveFullContext(
            userQuery: userMessage,
          );
          contextStr = ContextRetriever().buildContextString(contextData);
        } catch (e) {
          debugPrint('⚠️ Context retrieval failed: $e');
          // ยังคงทำต่อโดยไม่มี context
        }
      }
      
      // 📝 สร้าง prompt ที่มี context
      final prompt = _buildPrompt(userMessage, contextStr);
      
      // 🎯 เรียก LLM (Lazy Loading - โหลดอัตโนมัติเมื่อใช้งาน)
      String response;
      try {
        // LLM จะโหลดอัตโนมัติถ้ายังไม่ได้โหลด (autoLoad: true by default)
        response = await LLMService().generate(
          prompt,
          temperature: 0.7,
          maxTokens: 512,
        );
        // ถ้า response ว่าง แปลว่าโหลดโมเดลไม่ได้ ใช้ mock แทน
        if (response.isEmpty) {
          debugPrint('⚠️ LLM returned empty, using mock');
          response = await AIService.getMockResponse(userMessage);
        }
      } catch (e) {
        debugPrint('⚠️ LLM generate failed: $e');
        response = await AIService.getMockResponse(userMessage);
      }
      
      // ลบ "กำลังพิมพ์..." ออก
      state = state.where((m) => !m.isLoading).toList();
      
      // เพิ่มคำตอบ
      addMessage(ChatMessage.assistant(
        response,
        sources: useContext ? _extractSources(contextStr) : null,
      ));
      
    } catch (e, stackTrace) {
      debugPrint('❌ sendToAI error: $e');
      debugPrint('Stack: $stackTrace');
      
      state = state.where((m) => !m.isLoading).toList();
      addMessage(ChatMessage.error('ขอโทษค่ะ เกิดข้อผิดพลาด กรุณาลองใหม่ ($e)'));
    }
  }

  /// 🔔 ตอบกลับ Trigger Event (Proactive)
  ///
  /// 🔋 Battery Note: Trigger ใช้ suggestedMessage โดยตรงถ้าไม่มี LLM
  /// เพื่อไม่โหลด LLM โดยไม่จำเป็น (ประหยัดแบต)
  Future<void> respondToTrigger(TriggerEvent trigger) async {
    addMessage(ChatMessage.loading());

    try {
      // 🔋 Battery Optimization: ใช้ suggested message ถ้า LLM ยังไม่โหลด
      // ไม่ต้องโหลด LLM เพื่อ trigger (ประหยัดแบต)
      String response;
      if (LLMService().isInitialized) {
        // ถ้า LLM โหลดแล้ว (จากการใช้งานก่อนหน้า) ก็ใช้ได้เลย
        final prompt = _buildTriggerPrompt(trigger);
        response = await LLMService().generate(
          prompt,
          temperature: 0.8,
          maxTokens: 256,
          autoLoad: false, // ไม่โหลดอัตโนมัติสำหรับ trigger
        );
        if (response.isEmpty) {
          response = trigger.suggestedMessage ?? 'สวัสดีค่ะ!';
        }
      } else {
        // ถ้า LLM ยังไม่โหลด ใช้ suggested message (ประหยัดแบต)
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

  /// 📝 สร้าง Prompt สำหรับ Trigger (Private Life OS - Proactive)
  ///
  /// Haku ทักทายผู้ใช้ก่อน ไม่รอให้ถาม (Proactive vs Passive)
  String _buildTriggerPrompt(TriggerEvent trigger) {
    final contextStr = ContextRetriever().buildContextString(trigger.context);
    return HakuPrompts.forProactiveTrigger(
        contextStr, trigger.suggestedMessage ?? '');
  }

  /// 📝 สร้าง Prompt สำหรับ LLM (Private Life OS - Contextual Intelligence)
  ///
  /// Haku รู้จักผู้ใช้จากข้อมูลที่มี ไม่ใช่แค่ตอบคำถาม
  String _buildPrompt(String userMessage, String context) {
    // ถ้ามี context ใช้ RAG prompt
    if (context.isNotEmpty && !context.contains('ไม่พบบันทึก')) {
      return HakuPrompts.forRAGQuestion(userMessage, [context]);
    }
    // ถ้าไม่มี context ใช้ chat prompt
    return HakuPrompts.forChat(userMessage);
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

      // สร้าง context
      final context = todayEntries
          .map((e) =>
              '- ${e.createdAt.hour}:${e.createdAt.minute.toString().padLeft(2, '0')}: ${e.content}')
          .join('\n');

      // 🔋 ใช้ HakuPrompts (Private Life OS concept)
      final prompt = HakuPrompts.forSummarization(context);

      // 🔋 LLM Lazy Loading: โหลดอัตโนมัติเมื่อใช้งาน
      String response;
      try {
        response = await LLMService().generate(prompt);
        if (response.isEmpty) {
          // Fallback to mock
          response =
              'วันนี้คุณมี ${todayEntries.length} บันทึก ${todayEntries.any((e) => e.mood == 5) ? 'ดูเหมือนจะเป็นวันที่ดีนะคะ 😊' : 'เหนื่อยหน่อยแต่ก็ผ่านไปได้ค่ะ 💪'}';
        }
      } catch (e) {
        // Mock
        response =
            'วันนี้คุณมี ${todayEntries.length} บันทึก ${todayEntries.any((e) => e.mood == 5) ? 'ดูเหมือนจะเป็นวันที่ดีนะคะ 😊' : 'เหนื่อยหน่อยแต่ก็ผ่านไปได้ค่ะ 💪'}';
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
      // Initialize RAG (lightweight, ไม่กินแบต)
      debugPrint('🔄 Initializing RAG...');
      await RAGService().initialize();
      debugPrint('✅ RAG initialized: ${RAGService().isInitialized}');

      // 🔋 Battery Optimization: ไม่โหลด LLM ตอน initState
      // LLM จะถูกโหลดแบบ lazy เมื่อมีการเรียกใช้งาน generate() จริงๆ
      // และจะ auto-unload หลังไม่ใช้งาน 5 นาที
      debugPrint('⏸️ LLM: Lazy loading enabled - จะโหลดเมื่อใช้งานจริง');

      // Index entries ถ้ายังไม่มี (lightweight operation)
      if (RAGService().isInitialized) {
        debugPrint('🔄 Indexing entries...');
        final entries = await DatabaseHelper.instance.getAllEntries();
        if (entries.isNotEmpty) {
          await RAGService().indexEntries(entries);
        }
        debugPrint('✅ Entries indexed');
      }

      // Initialize MVP Trigger Service (battery-optimized)
      debugPrint('🔄 Initializing Trigger Service...');
      final triggerService = MVPTriggerService();
      await triggerService.initialize();

      // ตั้ง callback เมื่อมี trigger
      triggerService.onTrigger = (event) {
        _handleTrigger(event);
      };
      debugPrint('✅ All services initialized (battery optimized)');
    } catch (e, stackTrace) {
      debugPrint('❌ Error initializing services: $e');
      debugPrint('Stack: $stackTrace');
    }
  }

  void _handleTrigger(TriggerEvent event) {
    // แสดง proactive message
    ref.read(chatHistoryProvider.notifier).respondToTrigger(event);
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
    final llmService = LLMService();

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
                  llmService.isInitialized ? 'Qwen3-VL-4B 🟢' : 'Mock Mode 🟡',
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
                    'โหมดทดสอบ: ยังไม่ได้โหลดโมเดล Qwen3',
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
