import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'mediapipe_llm_service.dart';
import 'prompt_builder.dart';

/// 🎯 LLM Queue Service - จัดคิว LLM tasks ตาม priority
///
/// LLM รันได้ทีละงาน ระบบนี้จัดลำดับความสำคัญ:
/// - Priority 1: Chat response (user กำลังรอ)
/// - Priority 2: Search/Action (user อาจรอ)
/// - Priority 3: Worker extraction (background)
/// - Priority 4: RAG indexing (deferred)

class LLMQueueService {
  static final LLMQueueService _instance = LLMQueueService._internal();
  factory LLMQueueService() => _instance;
  LLMQueueService._internal();

  final MediaPipeLLMService _llm = MediaPipeLLMService();

  // Priority Queue (lower number = higher priority)
  final SplayTreeMap<int, Queue<LLMTask>> _queues = SplayTreeMap();

  bool _isProcessing = false;
  final List<LLMTask> _pendingWorkerTasks = []; // เก็บ worker tasks สำหรับ batch

  // ═══════════════════════════════════════════════════════════
  // 📊 Priority Levels
  // ═══════════════════════════════════════════════════════════

  static const int priorityChat = 1;      // 🎭 User waiting for response
  static const int prioritySearch = 2;    // 🔍 User waiting for search results
  static const int priorityAction = 3;    // ⚡ Execute actions (schedule, reminder)
  static const int priorityWorker = 4;    // 👷 Background extraction
  static const int priorityRAG = 5;       // 💾 Deferred RAG indexing

  // ═══════════════════════════════════════════════════════════
  // 🎭 HIGH PRIORITY: Chat Response (user waiting)
  // ═══════════════════════════════════════════════════════════

  /// 🎭 ส่งข้อความ chat และรอ response (Priority 1)
  Future<String> chat(String userMessage, {String? context}) async {
    final prompt = PromptBuilder.buildGemmaPrompt(
      userMessage: userMessage,
      context: context,
    );

    final completer = Completer<String>();

    final task = LLMTask(
      id: _generateId(),
      type: LLMTaskType.chat,
      prompt: prompt,
      priority: priorityChat,
      completer: completer,
      metadata: {'userMessage': userMessage},
    );

    _enqueue(task);
    _processQueue();

    return completer.future;
  }

  // ═══════════════════════════════════════════════════════════
  // 🔍 HIGH PRIORITY: Search (user might be waiting)
  // ═══════════════════════════════════════════════════════════

  /// 🔍 Follow-up search/action response (Priority 2)
  Future<String> searchFollowUp(String question, String searchResults) async {
    final prompt = '''<start_of_turn>user
You are Haku, a Thai-speaking AI assistant.

User asked: "$question"

Search Results:
$searchResults

Answer naturally in Thai (1-2 sentences, friendly, emoji ok):
<end_of_turn>
<start_of_turn>model
''';

    final completer = Completer<String>();

    final task = LLMTask(
      id: _generateId(),
      type: LLMTaskType.search,
      prompt: prompt,
      priority: prioritySearch,
      completer: completer,
    );

    _enqueue(task);
    _processQueue();

    return completer.future;
  }

  // ═══════════════════════════════════════════════════════════
  // 👷 LOW PRIORITY: Worker Extraction (background)
  // ═══════════════════════════════════════════════════════════

  /// 👷 Queue worker extraction (Priority 4 - background)
  /// ไม่ต้องรอ result ทันที
  void queueWorkerExtraction(String userMessage, String aiResponse) {
    final prompt = PromptBuilder.buildWorkerExtractPrompt(userMessage, aiResponse);

    final task = LLMTask(
      id: _generateId(),
      type: LLMTaskType.worker,
      prompt: prompt,
      priority: priorityWorker,
      metadata: {
        'userMessage': userMessage,
        'aiResponse': aiResponse,
      },
      onComplete: (result) => _handleWorkerResult(result, userMessage, aiResponse),
    );

    _enqueue(task);
    _processQueue();
  }

  /// 👷 Batch worker extraction - รวมหลายๆ chat แล้ว process ทีเดียว
  void queueBatchWorkerExtraction(List<ChatPair> chats) {
    for (final chat in chats) {
      queueWorkerExtraction(chat.userMessage, chat.aiResponse);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 💾 LOWEST PRIORITY: RAG Indexing (deferred)
  // ═══════════════════════════════════════════════════════════

  /// 💾 Queue RAG summarization (Priority 5 - very low)
  void queueRAGSummary(String content) {
    final prompt = PromptBuilder.buildWorkerSummarizePrompt(content);

    final task = LLMTask(
      id: _generateId(),
      type: LLMTaskType.rag,
      prompt: prompt,
      priority: priorityRAG,
      metadata: {'content': content},
      onComplete: (result) => _handleRAGResult(result, content),
    );

    _enqueue(task);
    _processQueue();
  }

  // ═══════════════════════════════════════════════════════════
  // 🔧 Queue Management
  // ═══════════════════════════════════════════════════════════

  void _enqueue(LLMTask task) {
    _queues.putIfAbsent(task.priority, () => Queue());
    _queues[task.priority]!.add(task);

    debugPrint('📥 LLMQueue: Added ${task.type.name} (priority ${task.priority})');
    debugPrint('📊 Queue status: ${_getQueueStatus()}');
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    if (!_llm.isInitialized) {
      debugPrint('⚠️ LLMQueue: LLM not initialized, skipping');
      return;
    }

    _isProcessing = true;

    try {
      while (_hasNextTask()) {
        final task = _dequeue();
        if (task == null) break;

        debugPrint('🔄 LLMQueue: Processing ${task.type.name} (priority ${task.priority})');
        final stopwatch = Stopwatch()..start();

        try {
          final result = await _llm.generate(task.prompt);
          stopwatch.stop();

          debugPrint('✅ LLMQueue: ${task.type.name} completed in ${stopwatch.elapsedMilliseconds}ms');

          // Complete the future if waiting
          if (task.completer != null && !task.completer!.isCompleted) {
            task.completer!.complete(result);
          }

          // Call callback if provided
          if (task.onComplete != null) {
            task.onComplete!(result);
          }

        } catch (e) {
          debugPrint('❌ LLMQueue: ${task.type.name} failed: $e');

          if (task.completer != null && !task.completer!.isCompleted) {
            task.completer!.completeError(e);
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  LLMTask? _dequeue() {
    for (final priority in _queues.keys) {
      final queue = _queues[priority]!;
      if (queue.isNotEmpty) {
        return queue.removeFirst();
      }
    }
    return null;
  }

  bool _hasNextTask() {
    return _queues.values.any((q) => q.isNotEmpty);
  }

  String _getQueueStatus() {
    final parts = <String>[];
    for (final entry in _queues.entries) {
      if (entry.value.isNotEmpty) {
        parts.add('P${entry.key}:${entry.value.length}');
      }
    }
    return parts.isEmpty ? 'empty' : parts.join(', ');
  }

  // ═══════════════════════════════════════════════════════════
  // 🎯 Result Handlers
  // ═══════════════════════════════════════════════════════════

  void _handleWorkerResult(String result, String userMessage, String aiResponse) {
    debugPrint('👷 Worker extraction completed');
    debugPrint('   Result: ${result.substring(0, result.length > 100 ? 100 : result.length)}...');

    // TODO: Parse JSON and dispatch to workers
    // TODO: Save to RAG
  }

  void _handleRAGResult(String summary, String originalContent) {
    debugPrint('💾 RAG summary completed');
    debugPrint('   Summary: $summary');

    // TODO: Save to UnifiedVectorService
  }

  // ═══════════════════════════════════════════════════════════
  // 📊 Stats & Control
  // ═══════════════════════════════════════════════════════════

  /// ดู queue status
  Map<String, int> getQueueStats() {
    return {
      'chat': _queues[priorityChat]?.length ?? 0,
      'search': _queues[prioritySearch]?.length ?? 0,
      'action': _queues[priorityAction]?.length ?? 0,
      'worker': _queues[priorityWorker]?.length ?? 0,
      'rag': _queues[priorityRAG]?.length ?? 0,
      'total': _queues.values.fold(0, (sum, q) => sum + q.length),
    };
  }

  /// เคลียร์ low priority tasks (ถ้า queue เยอะเกิน)
  void clearLowPriorityTasks() {
    _queues[priorityWorker]?.clear();
    _queues[priorityRAG]?.clear();
    debugPrint('🧹 LLMQueue: Cleared low priority tasks');
  }

  /// หยุด processing ชั่วคราว
  void pause() {
    _isProcessing = false;
    debugPrint('⏸️ LLMQueue: Paused');
  }

  /// Resume processing
  void resume() {
    _processQueue();
    debugPrint('▶️ LLMQueue: Resumed');
  }

  int _taskIdCounter = 0;
  String _generateId() => 'task_${++_taskIdCounter}_${DateTime.now().millisecondsSinceEpoch}';
}

// ═══════════════════════════════════════════════════════════
// 📦 Data Models
// ═══════════════════════════════════════════════════════════

enum LLMTaskType {
  chat,    // 🎭 User chat response
  search,  // 🔍 Search follow-up
  action,  // ⚡ Action execution
  worker,  // 👷 Background extraction
  rag,     // 💾 RAG indexing
}

class LLMTask {
  final String id;
  final LLMTaskType type;
  final String prompt;
  final int priority;
  final Completer<String>? completer;
  final Map<String, dynamic>? metadata;
  final void Function(String result)? onComplete;
  final DateTime createdAt;

  LLMTask({
    required this.id,
    required this.type,
    required this.prompt,
    required this.priority,
    this.completer,
    this.metadata,
    this.onComplete,
  }) : createdAt = DateTime.now();
}

class ChatPair {
  final String userMessage;
  final String aiResponse;
  final DateTime timestamp;

  ChatPair({
    required this.userMessage,
    required this.aiResponse,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
