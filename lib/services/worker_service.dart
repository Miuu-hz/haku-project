import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

import '../models/entry.dart';
import 'battery_aware_service.dart';
import 'database_helper.dart';
import 'chat_history_service.dart';
import 'deferred_task_service.dart';
import 'llm_service.dart';
import 'rag_service.dart';
import 'secret_chat_service.dart';
import 'topic_service.dart';
import 'unified_vector_service.dart';
import 'user_profile_service.dart';
import 'vector_service.dart';
import 'workers/translator_worker.dart';

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
  final RAGService _ragService = RAGService();
  final TranslatorWorker _translatorWorker = TranslatorWorker();

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
    await _ragService.initialize(); // 🔍 Initialize RAG for vector search

    // Register task handlers
    _registerTaskHandlers();

    // Listen to charging
    _batteryService.onChargingStarted = _onChargingStarted;

    // Check vector schema migration (tokenizer upgrade)
    await _checkVectorMigration();

    _isInitialized = true;
    debugPrint('✅ Worker Service initialized');
  }

  /// 🔄 Check if vector re-index is needed (tokenizer changed)
  Future<void> _checkVectorMigration() async {
    const currentVersion = 2; // Bumped for Thai n-gram tokenizer
    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getInt('vector_schema_version') ?? 0;

    if (storedVersion < currentVersion) {
      debugPrint('🔄 Vector schema upgrade $storedVersion → $currentVersion, queueing re-index');
      _deferredService.enqueue(
        taskType: 'reindex_vectors',
        priority: TaskPriority.high,
      );
      await prefs.setInt('vector_schema_version', currentVersion);
    }
  }

  /// 📝 Register deferred task handlers
  void _registerTaskHandlers() {
    _deferredService.registerHandler('summarize_chat', _handleSummarizeChat);
    _deferredService.registerHandler('process_topics', _handleProcessTopics);
    _deferredService.registerHandler('extract_facts', _handleExtractFacts);
    _deferredService.registerHandler('vectorize_topics', _handleVectorizeTopics);
    _deferredService.registerHandler('health_analysis', _handleHealthAnalysis);
    _deferredService.registerHandler('translate_entries', _handleTranslateEntries);
  }

  /// 💊 Handle health analysis task
  Future<void> _handleHealthAnalysis(Map<String, dynamic> payload) async {
    debugPrint('💊 Running health analysis...');

    final recentLogs = SecretChatService().getRecentLog(limit: 30);
    if (recentLogs.isEmpty) return;

    final vectorService = UnifiedVectorService();
    final now = DateTime.now();

    // pattern → category / label
    const patterns = <String, ({String category, String label})>{
      'period':   (category: 'health_log', label: 'period'),
      'menstr':   (category: 'health_log', label: 'period'),
      'cramp':    (category: 'health_log', label: 'cramp'),
      'headache': (category: 'health_log', label: 'headache'),
      'pain':     (category: 'health_log', label: 'pain'),
      'tired':    (category: 'health_log', label: 'fatigue'),
      'exhaust':  (category: 'health_log', label: 'fatigue'),
      'sick':     (category: 'health_log', label: 'sick'),
      'fever':    (category: 'health_log', label: 'fever'),
      'nausea':   (category: 'health_log', label: 'nausea'),
    };

    for (final entry in recentLogs) {
      final lower = entry.summaryEn.toLowerCase();
      for (final kv in patterns.entries) {
        if (lower.contains(kv.key)) {
          await vectorService.addFact(
            category: kv.value.category,
            content: entry.summaryEn,
            metadata: {
              'condition': kv.value.label,
              'date': entry.timestamp.toIso8601String(),
              'daysAgo': now.difference(entry.timestamp).inDays,
            },
          );
          debugPrint('💊 Health fact stored: ${kv.value.label} — ${entry.summaryEn}');
          break; // one fact per log entry
        }
      }
    }
  }

  /// 🌐 Handle translate entries task
  Future<void> _handleTranslateEntries(Map<String, dynamic> payload) async {
    debugPrint('🌐 Running entry translation...');
    await _translatorWorker.initialize();

    final entries = await DatabaseHelper.instance.getAllEntries();
    final translated = await _translatorWorker.translatePending(entries);

    // NOTE: ไม่ re-index ด้วย English text เพราะ embedding ต้องเป็นไทย
    // (user ค้นหาเป็นไทย → Thai query ต้อง match Thai embedding)
    // English translations ใช้แค่ตอน buildContext() เพื่อประหยัด token
    if (translated > 0) {
      debugPrint('✅ Translated $translated entries (cached for context display)');
    }
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
      onProgressChanged?.call(0.7);
      await _vectorizeTopics();

      // 5. Translate entries (Thai → English)
      onStatusChanged?.call('Translating entries...');
      onProgressChanged?.call(0.85);
      await _translateEntries();

      // 6. Process deferred tasks
      onStatusChanged?.call('Processing deferred tasks...');
      onProgressChanged?.call(0.95);
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
  // 🌐 TRANSLATION
  // ============================================================

  /// 🌐 Translate pending entries (Thai → English)
  Future<void> _translateEntries() async {
    await _translatorWorker.initialize();
    final entries = await DatabaseHelper.instance.getAllEntries();
    await _translatorWorker.translatePending(entries);
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
      final maxTokens = _llmService.modelConfig.summaryMaxTokens;
      final result = await _llmService.generate(prompt, maxTokens: maxTokens);
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
      final maxTokens = _llmService.modelConfig.workerMaxTokens.clamp(20, 100);
      final result = await _llmService.generate(prompt, maxTokens: maxTokens);
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
      final maxTokens = _llmService.modelConfig.workerMaxTokens;
      final result = await _llmService.generate(prompt, maxTokens: maxTokens);

      // Try to parse JSON
      final jsonStr = result.trim();
      if (jsonStr.startsWith('{')) {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;

        void queue(FactType type, dynamic value) {
          final v = value?.toString().trim() ?? '';
          if (v.isNotEmpty) _profileService.queueFact(PendingFact(type: type, value: v, source: text));
        }

        for (final v in (data['likes']    as List<dynamic>? ?? [])) { queue(FactType.like,    v); }
        for (final v in (data['dislikes'] as List<dynamic>? ?? [])) { queue(FactType.dislike, v); }
        for (final v in (data['goals']    as List<dynamic>? ?? [])) { queue(FactType.goal,    v); }
        queue(FactType.name, data['name']);
        queue(FactType.role, data['role']);

        debugPrint('📝 Queued facts from LLM extraction');
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

  /// 🔢 Vectorize all topics (Store in BOTH VectorService + RAG SQLite)
  Future<void> _vectorizeTopics() async {
    final topics = _topicService.topics.where((t) => !t.isPending).toList();

    for (final topic in topics) {
      // 1. Store in VectorService (SharedPreferences) - for quick lookup
      if (_vectorService.getVector(topic.id) == null) {
        await _vectorService.storeTopicVector(topic.id, topic.summary);
      }

      // 2. Store in RAG Database (SQLite) - for semantic search 🔍
      await _indexTopicInRAG(topic);
    }

    debugPrint('📊 Vectorized ${topics.length} topics to VectorService + RAG');
  }

  /// 🔍 Index topic in RAG database (SQLite)
  Future<void> _indexTopicInRAG(dynamic topic) async {
    try {
      // Convert topic to Entry for RAG indexing
      final entry = Entry(
        id: int.tryParse(topic.id.toString()) ?? 0,
        content: '${topic.name}\n${topic.summary}',
        createdAt: topic.createdAt as DateTime,
      );

      // Index in RAG (HybridVectorSearch SQLite)
      await _ragService.indexEntry(entry);
    } catch (e) {
      debugPrint('⚠️ Failed to index topic in RAG: $e');
    }
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

  /// ➕ Queue health analysis
  void queueHealthAnalysis() {
    _deferredService.enqueue(
      taskType: 'health_analysis',
      priority: TaskPriority.normal,
    );
  }

  /// ➕ Queue entry translation
  void queueTranslation() {
    _deferredService.enqueue(
      taskType: 'translate_entries',
      priority: TaskPriority.low,
    );
  }

  // ============================================================
  // 📊 STATUS
  // ============================================================

  /// 📊 Get worker status
  Map<String, dynamic> getStatus() => {
    'isProcessing': _isProcessing,
    'pendingTasks': _deferredService.pendingCount,
    'topics': _topicService.topicCount,
    'vectors': _vectorService.getStats(),
    'ragInitialized': _ragService.isInitialized,
    'hasProfile': _profileService.hasProfile,
  };
}
