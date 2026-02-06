import 'dart:async';

import 'package:flutter/foundation.dart';

import 'battery_aware_service.dart';
import 'chat_history_service.dart';
import 'deferred_task_service.dart';
import 'llm_service.dart';
import 'topic_service.dart';
import 'user_profile_service.dart';
import 'vector_service.dart';

/// 👷 Worker Service - Background Batch Processing
///
/// ทำงานตอน: เครื่องว่าง / ชาร์จแบต
///
/// Jobs:
/// 1. Compression: Thai Log -> English Summary
/// 2. Vectorization: Summary -> Vector Embedding
/// 3. Indexing: Store in Topics DB
/// 4. Identity: Extract facts -> Update profile
///
/// ใช้ Split-Role Prompt: แยก "สรุป" กับ "คุย"

class WorkerService {
  static final WorkerService _instance = WorkerService._internal();
  factory WorkerService() => _instance;
  WorkerService._internal();

  final BatteryAwareService _batteryService = BatteryAwareService();
  final ChatHistoryService _chatHistory = ChatHistoryService();
  final TopicService _topicService = TopicService();
  final VectorService _vectorService = VectorService();
  final UserProfileService _profileService = UserProfileService();
  final DeferredTaskService _deferredService = DeferredTaskService();
  final LLMService _llmService = LLMService();

  bool _isInitialized = false;
  bool _isProcessing = false;

  // Callbacks
  void Function(String status)? onStatusChanged;
  void Function(double progress)? onProgressChanged;

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _topicService.initialize();
    await _vectorService.initialize();
    await _profileService.initialize();
    await _chatHistory.initialize();
    await _deferredService.initialize();

    // Register task handlers
    _registerTaskHandlers();

    // Listen to charging
    _batteryService.onChargingStarted = _onChargingStarted;

    _isInitialized = true;
    debugPrint('✅ Worker Service initialized');
  }

  /// 📝 Register deferred task handlers
  void _registerTaskHandlers() {
    _deferredService.registerHandler('summarize_chat', _handleSummarizeChat);
    _deferredService.registerHandler('process_topics', _handleProcessTopics);
    _deferredService.registerHandler('extract_facts', _handleExtractFacts);
    _deferredService.registerHandler('vectorize_topics', _handleVectorizeTopics);
  }

  /// 🔌 On charging started
  void _onChargingStarted() {
    debugPrint('🔌 Worker: Charging started, beginning batch processing');
    runBatchProcess();
  }

  // ============================================================
  // 🔄 BATCH PROCESSING
  // ============================================================

  /// 🔄 Run full batch process
  Future<void> runBatchProcess() async {
    if (_isProcessing) {
      debugPrint('⚠️ Worker already processing');
      return;
    }

    if (!_batteryService.isChargingOrFull) {
      debugPrint('🔋 Not charging, skipping batch process');
      return;
    }

    _isProcessing = true;
    onStatusChanged?.call('Starting batch process...');

    try {
      // 1. Summarize chat history
      onStatusChanged?.call('Summarizing conversations...');
      onProgressChanged?.call(0.2);
      await _summarizeChat();

      // 2. Process pending topics
      onStatusChanged?.call('Processing topics...');
      onProgressChanged?.call(0.4);
      await _processTopics();

      // 3. Extract user facts
      onStatusChanged?.call('Extracting facts...');
      onProgressChanged?.call(0.6);
      await _extractFacts();

      // 4. Vectorize topics
      onStatusChanged?.call('Building search index...');
      onProgressChanged?.call(0.8);
      await _vectorizeTopics();

      // 5. Process deferred tasks
      onStatusChanged?.call('Processing deferred tasks...');
      onProgressChanged?.call(0.9);
      await _deferredService.forceProcess();

      onStatusChanged?.call('Batch process complete!');
      onProgressChanged?.call(1.0);
      debugPrint('✅ Worker: Batch process complete');
    } catch (e) {
      debugPrint('❌ Worker batch process error: $e');
      onStatusChanged?.call('Error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // ============================================================
  // 📝 SUMMARIZATION
  // ============================================================

  /// 📝 Summarize chat history
  Future<void> _summarizeChat() async {
    await _chatHistory.forceSummarize();
  }

  /// 📝 Handle summarize task
  Future<void> _handleSummarizeChat(Map<String, dynamic> payload) async {
    await _summarizeChat();
  }

  // ============================================================
  // 📚 TOPIC PROCESSING
  // ============================================================

  /// 📚 Process pending topics
  Future<void> _processTopics() async {
    await _topicService.processPendingTopics(
      summarizeCallback: _summarizeMessages,
      nameCallback: _generateTopicName,
      getMessagesCallback: _getMessageRange,
    );
  }

  /// 📝 Summarize messages to English
  Future<String> _summarizeMessages(List<String> messages) async {
    if (messages.isEmpty) return '';

    final joined = messages.join('\n');
    final prompt = '''
Summarize this Thai conversation in English (2-3 sentences).
Focus on: main topic, emotions, key facts/dates.

Conversation:
$joined

English summary:''';

    try {
      final result = await _llmService.generate(prompt, maxTokens: 100);
      return result.trim();
    } catch (e) {
      debugPrint('⚠️ Summarize error: $e');
      return '';
    }
  }

  /// 📝 Generate topic name from summary
  Future<String> _generateTopicName(String summary) async {
    if (summary.isEmpty) return 'Untitled';

    final prompt = '''
Create a short topic name (2-4 words) for this summary:
$summary

Topic name:''';

    try {
      final result = await _llmService.generate(prompt, maxTokens: 20);
      return result.trim().replaceAll(RegExp(r'[^\w\s]'), '');
    } catch (e) {
      debugPrint('⚠️ Topic name error: $e');
      // Extract first few words as fallback
      final words = summary.split(' ').take(3).join(' ');
      return words.isNotEmpty ? words : 'Untitled';
    }
  }

  /// 📋 Get messages in range
  List<String> _getMessageRange(int start, int end) {
    final messages = <String>[];
    final history = _chatHistory.rawHistory;

    for (var i = start; i <= end && i < history.length; i++) {
      if (i >= 0) {
        messages.add(history[i].content);
      }
    }

    return messages;
  }

  /// 📚 Handle process topics task
  Future<void> _handleProcessTopics(Map<String, dynamic> payload) async {
    await _processTopics();
  }

  // ============================================================
  // 🧠 FACT EXTRACTION
  // ============================================================

  /// 🧠 Extract user facts from recent messages
  Future<void> _extractFacts() async {
    final recentMessages = _chatHistory.rawHistory.take(20).toList();

    for (final msg in recentMessages) {
      if (msg.role == 'user') {
        // Try simple extraction first
        final simpleFacts = _profileService.extractFactsSimple(msg.content);

        if (simpleFacts.isNotEmpty) {
          for (final fact in simpleFacts) {
            _profileService.queueFact(fact);
          }
        } else {
          // Try LLM extraction for complex cases
          await _extractFactsWithLLM(msg.content);
        }
      }
    }

    // Process queued facts
    await _profileService.processPendingFacts();
  }

  /// 🧠 Extract facts using LLM
  Future<void> _extractFactsWithLLM(String text) async {
    if (text.length < 10) return;

    final prompt = '''
Extract personal facts from this Thai message.
Return JSON only, empty {} if none found.

Message: $text

Format: {"likes":[],"dislikes":[],"goals":[],"name":"","role":""}
JSON:''';

    try {
      final result = await _llmService.generate(prompt, maxTokens: 100);

      // Try to parse JSON
      final jsonStr = result.trim();
      if (jsonStr.startsWith('{')) {
        // TODO: Parse and queue facts
        debugPrint('📝 Extracted facts: $jsonStr');
      }
    } catch (e) {
      debugPrint('⚠️ LLM fact extraction error: $e');
    }
  }

  /// 🧠 Handle extract facts task
  Future<void> _handleExtractFacts(Map<String, dynamic> payload) async {
    await _extractFacts();
  }

  // ============================================================
  // 🔢 VECTORIZATION
  // ============================================================

  /// 🔢 Vectorize all topics
  Future<void> _vectorizeTopics() async {
    final topics = _topicService.topics.where((t) => !t.isPending).toList();

    for (final topic in topics) {
      // Check if already vectorized
      if (_vectorService.getVector(topic.id) != null) continue;

      // Vectorize using English summary
      await _vectorService.storeTopicVector(topic.id, topic.summary);
    }

    debugPrint('📊 Vectorized ${topics.length} topics');
  }

  /// 🔢 Handle vectorize task
  Future<void> _handleVectorizeTopics(Map<String, dynamic> payload) async {
    await _vectorizeTopics();
  }

  // ============================================================
  // 🎯 QUEUE TASKS
  // ============================================================

  /// ➕ Queue summarize task
  void queueSummarize() {
    _deferredService.enqueue(
      taskType: 'summarize_chat',
      priority: TaskPriority.normal,
    );
  }

  /// ➕ Queue topic processing
  void queueTopicProcessing() {
    _deferredService.enqueue(
      taskType: 'process_topics',
      priority: TaskPriority.normal,
    );
  }

  /// ➕ Queue fact extraction
  void queueFactExtraction() {
    _deferredService.enqueue(
      taskType: 'extract_facts',
      priority: TaskPriority.low,
    );
  }

  /// ➕ Queue vectorization
  void queueVectorization() {
    _deferredService.enqueue(
      taskType: 'vectorize_topics',
      priority: TaskPriority.low,
    );
  }

  // ============================================================
  // 📊 STATUS
  // ============================================================

  /// 📊 Get worker status
  Map<String, dynamic> getStatus() {
    return {
      'isProcessing': _isProcessing,
      'pendingTasks': _deferredService.pendingCount,
      'topics': _topicService.topicCount,
      'vectors': _vectorService.getStats(),
      'hasProfile': _profileService.hasProfile,
    };
  }
}
