import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/correlation_models.dart';
import 'battery_aware_service.dart';
import 'chat_summary_service.dart';
import 'mediapipe_llm_service.dart';
import 'prompt_builder.dart';
import 'user_profile_service.dart';
import 'workers/calendar_worker.dart';
import 'workers/correlation_worker.dart';
import 'workers/fact_worker.dart';
import 'workers/reminder_worker.dart';
import 'insight_notification_service.dart';

// Re-export models
export 'workers/reminder_worker.dart' show ReminderTime, ReminderFrequency, Reminder;
export 'user_profile_service.dart' show FactType;
export 'workers/calendar_worker.dart' show CalendarEvent, EventType, TimeOfDay;

/// ⏰ Unified Task Service - รวม LLM Queue + Deferred Task
///
/// จัดคิวงานทั้งหมดในระบบ:
/// - 🔥 LLM Tasks: Chat, Search, Action (ใช้ CPU หนัก)
/// - 🔋 Deferred Tasks: Calendar, Reminder, Fact (รอชาร์จ)
/// - 📚 Topics: Message grouping และสรุป
///
/// Priority Levels:
/// 1 = Critical (Chat response - user waiting)
/// 2 = High (Search, Actions)
/// 3 = Normal (Reminders, Facts)
/// 4 = Low (Worker extraction)
/// 5 = Lowest (RAG indexing, Topics)

class UnifiedTaskService {
  static final UnifiedTaskService _instance = UnifiedTaskService._internal();
  factory UnifiedTaskService() => _instance;
  UnifiedTaskService._internal();

  // Dependencies
  final MediaPipeLLMService _llm = MediaPipeLLMService();
  final BatteryAwareService _battery = BatteryAwareService();
  final ChatSummaryService _chatSummary = ChatSummaryService();

  // Workers
  CalendarWorker? _calendarWorker;
  CorrelationWorker? _correlationWorker;
  ReminderWorker? _reminderWorker;
  FactWorker? _factWorker;
  InsightNotificationService? _insightNotification;

  // ═══════════════════════════════════════════════════════════
  // 📊 Priority Constants
  // ═══════════════════════════════════════════════════════════

  static const int priorityCritical = 1;   // 🎭 Chat response
  static const int priorityHigh = 2;       // 🔍 Search/Actions
  static const int priorityNormal = 3;     // 📅 Calendar/Reminder
  static const int priorityLow = 4;        // 📝 Facts/Worker
  static const int priorityLowest = 5;     // 💾 RAG/Topics

  // ═══════════════════════════════════════════════════════════
  // 🔄 State
  // ═══════════════════════════════════════════════════════════

  // LLM Queue (in-memory, immediate)
  final SplayTreeMap<int, Queue<LLMTask>> _llmQueues = SplayTreeMap();
  bool _isProcessingLLM = false;

  // Deferred Queue (persistent, charging-only)
  static const String _deferredKey = 'deferred_tasks';
  List<DeferredTask> _deferredTasks = [];
  bool _isProcessingDeferred = false;

  // Topic Management
  static const String _topicsKey = 'task_topics';
  List<TaskTopic> _topics = [];
  Map<String, String> _messageIndex = {};

  bool _isInitialized = false;

  // ═══════════════════════════════════════════════════════════
  // 🚀 Initialization
  // ═══════════════════════════════════════════════════════════

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadDeferredTasks();
    await _loadTopics();
    await _initWorkers();

    _battery.onChargingStarted = _onChargingStarted;

    _isInitialized = true;
    debugPrint('✅ Unified Task Service initialized');
  }

  Future<void> _initWorkers() async {
    _calendarWorker = CalendarWorker();
    _reminderWorker = ReminderWorker();
    _factWorker = FactWorker();

    await _calendarWorker!.initialize();
    await _reminderWorker!.initialize();
  }

  // ═══════════════════════════════════════════════════════════
  // 🎭 LLM TASKS (Immediate)
  // ═══════════════════════════════════════════════════════════

  /// 🎭 Chat response (Priority 1)
  Future<String> chat(String userMessage, {String? context}) async {
    return _llmWithPrompt(
      PromptBuilder.buildGemmaPrompt(userMessage: userMessage, context: context),
      priority: priorityCritical,
      type: TaskType.chat,
    );
  }

  /// 🔧 Custom prompt (for BigManager)
  Future<String> llmPrompt(String prompt, {int priority = priorityHigh}) async {
    return _llmWithPrompt(prompt, priority: priority, type: TaskType.action);
  }

  /// 🔍 Search follow-up (Priority 2)
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
    return _llmWithPrompt(prompt, priority: priorityHigh, type: TaskType.search);
  }

  Future<String> _llmWithPrompt(String prompt, {required int priority, required TaskType type}) async {
    final completer = Completer<String>();

    final task = LLMTask(
      id: _generateId(),
      type: type,
      prompt: prompt,
      priority: priority,
      completer: completer,
    );

    _enqueueLLM(task);
    _processLLMQueue();

    return completer.future;
  }

  /// 👷 Queue background extraction (Priority 4)
  void queueExtraction(String userMessage, String aiResponse) {
    final prompt = PromptBuilder.buildWorkerExtractPrompt(userMessage, aiResponse);

    final task = LLMTask(
      id: _generateId(),
      type: TaskType.worker,
      prompt: prompt,
      priority: priorityLow,
      onComplete: (result) => _handleExtractionResult(result, userMessage, aiResponse),
    );

    _enqueueLLM(task);
    _processLLMQueue();
  }

  /// 💾 Queue RAG summarization (Priority 5)
  void queueRAGSummary(String content) {
    final prompt = PromptBuilder.buildWorkerSummarizePrompt(content);

    final task = LLMTask(
      id: _generateId(),
      type: TaskType.rag,
      prompt: prompt,
      priority: priorityLowest,
      onComplete: (result) => _handleRAGResult(result, content),
    );

    _enqueueLLM(task);
    _processLLMQueue();
  }

  void _enqueueLLM(LLMTask task) {
    _llmQueues.putIfAbsent(task.priority, () => Queue());
    _llmQueues[task.priority]!.add(task);
    debugPrint('📥 LLM Task: ${task.type.name} (P${task.priority})');
  }

  Future<void> _processLLMQueue() async {
    if (_isProcessingLLM) return;
    if (!_llm.isInitialized) return;

    _isProcessingLLM = true;

    try {
      while (_llmQueues.values.any((q) => q.isNotEmpty)) {
        final task = _dequeueLLM();
        if (task == null) break;

        debugPrint('🔄 Processing LLM: ${task.type.name}');
        final stopwatch = Stopwatch()..start();

        try {
          final result = await _llm.generate(task.prompt);
          stopwatch.stop();
          debugPrint('✅ LLM ${task.type.name}: ${stopwatch.elapsedMilliseconds}ms');

          if (task.completer != null && !task.completer!.isCompleted) {
            task.completer!.complete(result);
          }
          if (task.onComplete != null) {
            task.onComplete!(result);
          }
        } catch (e) {
          debugPrint('❌ LLM ${task.type.name} failed: $e');
          if (task.completer != null && !task.completer!.isCompleted) {
            task.completer!.completeError(e);
          }
        }
      }
    } finally {
      _isProcessingLLM = false;
    }
  }

  LLMTask? _dequeueLLM() {
    for (final priority in _llmQueues.keys) {
      final queue = _llmQueues[priority]!;
      if (queue.isNotEmpty) return queue.removeFirst();
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // 🔋 DEFERRED TASKS (Charging only)
  // ═══════════════════════════════════════════════════════════

  /// ➕ Add deferred task
  Future<void> enqueue({
    required TaskType type,
    Map<String, dynamic>? payload,
    int priority = priorityNormal,
  }) async {
    final task = DeferredTask(
      id: _generateId(),
      type: type,
      payload: payload ?? {},
      priority: priority,
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
    );

    _deferredTasks.add(task);
    await _saveDeferredTasks();
    debugPrint('➕ Deferred: ${type.name} (P$priority)');

    // Critical/High: do immediately
    if (priority <= priorityHigh) {
      await _processDeferredTasks(immediate: true);
    }

    // If charging: process queue
    if (_battery.isChargingOrFull && !_isProcessingDeferred) {
      await _processDeferredTasks();
    }
  }

  /// 🔌 Charging callback
  void _onChargingStarted() {
    debugPrint('🔌 Charging - processing deferred tasks');
    _processDeferredTasks();
  }

  Future<void> _processDeferredTasks({bool immediate = false}) async {
    if (_isProcessingDeferred) return;
    if (_deferredTasks.isEmpty) return;

    _isProcessingDeferred = true;

    try {
      final pending = _deferredTasks.where((t) => t.status == TaskStatus.pending).toList();
      pending.sort((a, b) => a.priority.compareTo(b.priority));

      for (final task in pending) {
        if (!immediate && !_battery.isChargingOrFull && task.priority > priorityHigh) {
          debugPrint('🔋 Stopped charging - pausing');
          break;
        }

        await _executeDeferredTask(task);
        if (!immediate) await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      _isProcessingDeferred = false;
      await _saveDeferredTasks();
    }
  }

  Future<void> _executeDeferredTask(DeferredTask task) async {
    debugPrint('🎯 Executing: ${task.type.name}');
    task.status = TaskStatus.running;

    try {
      switch (task.type) {
        case TaskType.calendar:
          await _handleCalendarTask(task.payload);
          break;
        case TaskType.reminder:
          await _handleReminderTask(task.payload);
          break;
        case TaskType.fact:
          await _handleFactTask(task.payload);
          break;
        case TaskType.location:
          await _handleLocationTask(task.payload);
          break;
        case TaskType.webSearch:
          await _handleWebSearchTask(task.payload);
          break;
        case TaskType.correlation:
          await _handleCorrelationTask(task.payload);
          break;
        default:
          debugPrint('⚠️ Unknown deferred type: ${task.type.name}');
      }
      task.status = TaskStatus.completed;
    } catch (e) {
      debugPrint('❌ Failed: ${task.type.name} - $e');
      task.status = TaskStatus.failed;
    }
  }

  // Task Handlers
  Future<void> _handleCalendarTask(Map<String, dynamic> payload) async {
    final title = payload['title'] as String? ?? '';
    if (title.isEmpty) return;

    final date = payload['date'] != null ? DateTime.parse(payload['date'] as String) : DateTime.now();
    final timeStr = payload['time'] as String?;
    
    // Parse time string like "10:00"
    TimeOfDay? time;
    if (timeStr != null) {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        time = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 10,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    final event = CalendarEvent(
      id: _generateId(),
      type: EventType.event,
      title: title,
      date: date,
      time: time,
      location: payload['location'] as String?,
      createdAt: DateTime.now(),
    );

    await _calendarWorker?.addEvent(event);
    debugPrint('📅 Calendar: $title');
  }

  Future<void> _handleReminderTask(Map<String, dynamic> payload) async {
    final content = payload['content'] as String? ?? '';
    if (content.isEmpty) return;

    final reminder = Reminder(
      id: _generateId(),
      content: content,
      time: _parseReminderTime(payload['time'] as String?),
      frequency: ReminderFrequency.once,
      isActive: true,
      createdAt: DateTime.now(),
    );

    await _reminderWorker?.addReminder(reminder);
    debugPrint('🔔 Reminder: $content');
  }

  Future<void> _handleFactTask(Map<String, dynamic> payload) async {
    final type = payload['type'] as String? ?? '';
    final value = payload['value'] as String? ?? '';
    if (type.isEmpty || value.isEmpty) return;

    final factType = _parseFactType(type);
    await _factWorker?.saveFact(type: factType, value: value);
    debugPrint('📝 Fact: $type = $value');
  }

  Future<void> _handleLocationTask(Map<String, dynamic> payload) async {
    final name = payload['name'] as String? ?? '';
    if (name.isEmpty) return;

    await enqueue(
      type: TaskType.webSearch,
      payload: {'query': '$name รีวิว'},
      priority: priorityHigh,
    );
    debugPrint('📍 Location: $name');
  }

  Future<void> _handleWebSearchTask(Map<String, dynamic> payload) async {
    final query = payload['query'] as String? ?? '';
    if (query.isEmpty) return;
    debugPrint('🌐 Web search: $query');
  }

  Future<void> _handleCorrelationTask(Map<String, dynamic> payload) async {
    final scope = payload['scope'] as String? ?? 'quick';
    debugPrint('🔮 Correlation analysis: scope=$scope');

    _correlationWorker ??= CorrelationWorker();
    _insightNotification ??= InsightNotificationService();

    try {
      CorrelationAnalysisResult? result;
      
      if (scope == 'full') {
        result = await _correlationWorker!.runFullAnalysis();
      } else {
        result = await _correlationWorker!.runQuickAnalysis();
      }

      if (result != null && result.insights.isNotEmpty) {
        // แจ้งเตือน insights ใหม่
        await _insightNotification!.checkAndNotifyNewInsights(result);
        debugPrint('✅ Correlation: ${result.insights.length} insights found, notified');
      } else {
        debugPrint('ℹ️ Correlation: No significant insights found');
      }
    } catch (e) {
      debugPrint('❌ Correlation task failed: $e');
    }
  }

  ReminderTime? _parseReminderTime(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return ReminderTime(hour: hour, minute: minute);
  }

  FactType _parseFactType(String type) {
    switch (type.toLowerCase()) {
      case 'like': return FactType.like;
      case 'dislike': return FactType.dislike;
      case 'goal': return FactType.goal;
      case 'place': return FactType.place;
      case 'name': return FactType.name;
      default: return FactType.custom;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📚 Topic Management
  // ═══════════════════════════════════════════════════════════

  List<TaskTopic> get topics => List.unmodifiable(_topics);
  int get topicCount => _topics.length;

  Future<void> processTopics() async {
    final pending = _topics.where((t) => t.isPending).toList();

    for (final topic in pending) {
      if (topic.messageCount < 3) continue;

      try {
        final messages = await _getMessagesInRange(topic.startIndex, topic.endIndex);
        final summary = messages.take(3).join('. ');

        topic.name = summary.split(' ').take(3).join(' ');
        topic.summary = summary;
        topic.isPending = false;
        topic.updatedAt = DateTime.now();

        debugPrint('✅ Topic: ${topic.name}');
      } catch (e) {
        debugPrint('⚠️ Topic error: $e');
      }
    }

    await _saveTopics();
  }

  Future<List<String>> _getMessagesInRange(int start, int end) async {
    final messages = <String>[];
    final history = await _chatSummary.getRawHistory();
    for (var i = start; i <= end && i < history.length; i++) {
      if (i >= 0) messages.add(history[i].content);
    }
    return messages;
  }

  TaskTopic? getTopicForMessage(String messageId) {
    final topicId = _messageIndex[messageId];
    if (topicId == null) return null;
    return _topics.firstWhere((t) => t.id == topicId, orElse: () => TaskTopic.empty());
  }

  // ═══════════════════════════════════════════════════════════
  // 💾 Persistence
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadDeferredTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_deferredKey);
      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _deferredTasks = list.map((e) => DeferredTask.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading deferred: $e');
    }
  }

  Future<void> _saveDeferredTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = _deferredTasks.where((t) => t.status == TaskStatus.pending).toList();
      await prefs.setString(_deferredKey, jsonEncode(toSave.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('⚠️ Error saving deferred: $e');
    }
  }

  Future<void> _loadTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_topicsKey);
      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _topics = list.map((e) => TaskTopic.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading topics: $e');
    }
  }

  Future<void> _saveTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_topicsKey, jsonEncode(_topics.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('⚠️ Error saving topics: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 📊 Stats & Control
  // ═══════════════════════════════════════════════════════════

  Map<String, dynamic> getStats() {
    return {
      'llm': {
        'chat': _llmQueues[priorityCritical]?.length ?? 0,
        'search': _llmQueues[priorityHigh]?.length ?? 0,
        'worker': _llmQueues[priorityLow]?.length ?? 0,
        'rag': _llmQueues[priorityLowest]?.length ?? 0,
      },
      'deferred': {
        'pending': _deferredTasks.where((t) => t.status == TaskStatus.pending).length,
        'total': _deferredTasks.length,
      },
      'topics': _topics.length,
    };
  }

  Future<void> forceProcess() async {
    await _processDeferredTasks(immediate: true);
  }

  void pause() {
    _isProcessingLLM = false;
    debugPrint('⏸️ UnifiedTask: Paused');
  }

  void resume() {
    _processLLMQueue();
    debugPrint('▶️ UnifiedTask: Resumed');
  }

  int _taskId = 0;
  String _generateId() => 'task_${++_taskId}_${DateTime.now().millisecondsSinceEpoch}';

  void _handleExtractionResult(String result, String userMsg, String aiResp) {
    debugPrint('👷 Extraction: ${result.substring(0, result.length > 50 ? 50 : result.length)}...');
  }

  void _handleRAGResult(String summary, String original) {
    debugPrint('💾 RAG: $summary');
  }
}

// ═══════════════════════════════════════════════════════════
// 📦 Data Models
// ═══════════════════════════════════════════════════════════

enum TaskType {
  chat,        // 🎭 User chat
  search,      // 🔍 Search follow-up
  action,      // ⚡ Action execution
  worker,      // 👷 Background extraction
  rag,         // 💾 RAG indexing
  calendar,    // 📅 Calendar event
  reminder,    // 🔔 Reminder
  fact,        // 📝 Fact extraction
  location,    // 📍 Location
  webSearch,   // 🌐 Web search
  correlation, // 🔮 Correlation analysis
}

enum TaskStatus {
  pending,
  running,
  completed,
  failed,
}

class LLMTask {
  final String id;
  final TaskType type;
  final String prompt;
  final int priority;
  final Completer<String>? completer;
  final void Function(String result)? onComplete;
  final DateTime createdAt;

  LLMTask({
    required this.id,
    required this.type,
    required this.prompt,
    required this.priority,
    this.completer,
    this.onComplete,
  }) : createdAt = DateTime.now();
}

class DeferredTask {
  final String id;
  final TaskType type;
  final Map<String, dynamic> payload;
  final int priority;
  TaskStatus status;
  final DateTime createdAt;

  DeferredTask({
    required this.id,
    required this.type,
    required this.payload,
    required this.priority,
    required this.status,
    required this.createdAt,
  });

  factory DeferredTask.fromJson(Map<String, dynamic> json) => DeferredTask(
        id: json['id'] as String,
        type: TaskType.values.firstWhere((e) => e.name == json['type'], orElse: () => TaskType.fact),
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        priority: json['priority'] as int,
        status: TaskStatus.values[json['status'] as int],
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'payload': payload,
        'priority': priority,
        'status': status.index,
        'createdAt': createdAt.toIso8601String(),
      };
}

class TaskTopic {
  final String id;
  String name;
  String summary;
  int startIndex;
  int endIndex;
  bool isPending;
  final DateTime createdAt;
  DateTime updatedAt;

  TaskTopic({
    required this.id,
    required this.name,
    required this.summary,
    required this.startIndex,
    required this.endIndex,
    required this.isPending,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  int get messageCount => endIndex - startIndex + 1;

  factory TaskTopic.empty() => TaskTopic(
        id: '',
        name: '',
        summary: '',
        startIndex: 0,
        endIndex: 0,
        isPending: true,
        createdAt: DateTime.now(),
      );

  factory TaskTopic.fromJson(Map<String, dynamic> json) => TaskTopic(
        id: json['id'] as String,
        name: json['name'] as String,
        summary: json['summary'] as String,
        startIndex: json['startIndex'] as int,
        endIndex: json['endIndex'] as int,
        isPending: json['isPending'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'summary': summary,
        'startIndex': startIndex,
        'endIndex': endIndex,
        'isPending': isPending,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
