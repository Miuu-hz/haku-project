import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battery_aware_service.dart';

/// ⏰ Deferred Task Service - จัดคิวงานหนักรอชาร์จ
///
/// Features:
/// - เพิ่มงานเข้าคิว (summarize, sync, cleanup)
/// - ทำงานอัตโนมัติเมื่อเริ่มชาร์จ
/// - Priority queue (high, normal, low)

class DeferredTaskService {
  static final DeferredTaskService _instance = DeferredTaskService._internal();
  factory DeferredTaskService() => _instance;
  DeferredTaskService._internal();

  final BatteryAwareService _batteryService = BatteryAwareService();

  static const String _queueKey = 'deferred_task_queue';

  List<DeferredTask> _taskQueue = [];
  bool _isInitialized = false;
  bool _isProcessing = false;

  // Task handlers
  final Map<String, Future<void> Function(Map<String, dynamic>)> _handlers = {};

  // Getters
  List<DeferredTask> get pendingTasks =>
      _taskQueue.where((t) => t.status == TaskStatus.pending).toList();
  int get pendingCount => pendingTasks.length;
  bool get isProcessing => _isProcessing;

  /// 🚀 Initialize service
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadQueue();

    // ลงทะเบียนกับ BatteryService
    _batteryService.onChargingStarted = _onChargingStarted;

    _isInitialized = true;
    debugPrint('✅ Deferred Task Service initialized');
    debugPrint('   - Pending tasks: $pendingCount');
  }

  /// 📝 ลงทะเบียน task handler
  void registerHandler(
    String taskType,
    Future<void> Function(Map<String, dynamic>) handler,
  ) {
    _handlers[taskType] = handler;
    debugPrint('📝 Registered handler for: $taskType');
  }

  /// ➕ เพิ่มงานเข้าคิว
  Future<void> enqueue({
    required String taskType,
    Map<String, dynamic>? payload,
    TaskPriority priority = TaskPriority.normal,
    Duration? maxAge, // งานหมดอายุหลังจากเวลานี้
  }) async {
    final task = DeferredTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: taskType,
      payload: payload ?? {},
      priority: priority,
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      expiresAt: maxAge != null ? DateTime.now().add(maxAge) : null,
    );

    _taskQueue.add(task);
    _sortQueue();
    await _saveQueue();

    debugPrint('➕ Task enqueued: $taskType (priority: ${priority.name})');

    // ถ้ากำลังชาร์จ ให้เริ่มทำเลย
    if (_batteryService.isChargingOrFull && !_isProcessing) {
      _processQueue();
    }
  }

  /// 🔌 Callback เมื่อเริ่มชาร์จ
  void _onChargingStarted() {
    debugPrint('🔌 Charging started - processing deferred tasks');
    _enqueueNightlyTasks();
    _processQueue();
  }

  /// ➕ auto-enqueue nightly maintenance tasks (dedup ด้วย maxAge)
  Future<void> _enqueueNightlyTasks() async {
    // memory_consolidation: ทำทุกวัน (maxAge 23h ป้องกัน enqueue ซ้ำ)
    final alreadyQueued = _taskQueue.any(
      (t) => t.type == 'memory_consolidation' && t.status == TaskStatus.pending,
    );
    if (!alreadyQueued) {
      await enqueue(
        taskType: 'memory_consolidation',
        priority: TaskPriority.normal,
        maxAge: const Duration(hours: 23),
      );
    }
    // wiki_update: ทำทุกวัน หลัง consolidation
    final wikiQueued = _taskQueue.any(
      (t) => t.type == 'wiki_update' && t.status == TaskStatus.pending,
    );
    if (!wikiQueued) {
      await enqueue(
        taskType: 'wiki_update',
        priority: TaskPriority.low,
        maxAge: const Duration(hours: 23),
      );
    }
  }

  /// ⚙️ ประมวลผลคิว
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    if (_taskQueue.isEmpty) return;

    _isProcessing = true;
    debugPrint('⚙️ Processing deferred task queue...');

    try {
      while (pendingTasks.isNotEmpty) {
        // ตรวจสอบว่ายังชาร์จอยู่
        if (!_batteryService.isChargingOrFull) {
          debugPrint('🔋 Stopped charging - pausing queue processing');
          break;
        }

        // หยิบงานถัดไป
        final task = pendingTasks.first;

        // ตรวจสอบหมดอายุ
        if (task.expiresAt != null && DateTime.now().isAfter(task.expiresAt!)) {
          debugPrint('⏰ Task expired: ${task.type}');
          _updateTaskStatus(task.id, TaskStatus.expired);
          continue;
        }

        // ทำงาน
        await _executeTask(task);
      }
    } finally {
      _isProcessing = false;
      await _saveQueue();
    }

    debugPrint('✅ Queue processing complete');
  }

  /// 🎯 Execute single task
  Future<void> _executeTask(DeferredTask task) async {
    debugPrint('🎯 Executing: ${task.type}');
    _updateTaskStatus(task.id, TaskStatus.running);

    try {
      final handler = _handlers[task.type];
      if (handler == null) {
        debugPrint('⚠️ No handler for: ${task.type}');
        _updateTaskStatus(task.id, TaskStatus.failed, error: 'No handler');
        return;
      }

      await handler(task.payload);
      _updateTaskStatus(task.id, TaskStatus.completed);
      debugPrint('✅ Completed: ${task.type}');
    } catch (e) {
      debugPrint('❌ Failed: ${task.type} - $e');
      _updateTaskStatus(task.id, TaskStatus.failed, error: e.toString());
    }
  }

  /// 🔄 Update task status
  void _updateTaskStatus(String taskId, TaskStatus status, {String? error}) {
    final index = _taskQueue.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      _taskQueue[index] = _taskQueue[index].copyWith(
        status: status,
        error: error,
        completedAt: status == TaskStatus.completed ? DateTime.now() : null,
      );
    }
  }

  /// 📊 Sort queue by priority
  void _sortQueue() {
    _taskQueue.sort((a, b) {
      // เรียงตาม status (pending ก่อน)
      if (a.status != b.status) {
        return a.status.index.compareTo(b.status.index);
      }
      // เรียงตาม priority (high ก่อน)
      return b.priority.index.compareTo(a.priority.index);
    });
  }

  /// 💾 Save to storage
  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // เก็บเฉพาะ pending และ running (ลบ completed/failed/expired)
      final toSave = _taskQueue
          .where((t) =>
              t.status == TaskStatus.pending || t.status == TaskStatus.running)
          .toList();

      await prefs.setString(
        _queueKey,
        jsonEncode(toSave.map((t) => t.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving task queue: $e');
    }
  }

  /// 📥 Load from storage
  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_queueKey);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _taskQueue = list.map((e) => DeferredTask.fromJson(e as Map<String, dynamic>)).toList();
        _sortQueue();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading task queue: $e');
    }
  }

  /// 🗑️ Clear completed tasks
  void clearCompleted() {
    _taskQueue.removeWhere((t) =>
        t.status == TaskStatus.completed ||
        t.status == TaskStatus.failed ||
        t.status == TaskStatus.expired);
    _saveQueue();
  }

  /// 🗑️ Clear all tasks
  Future<void> clearAll() async {
    _taskQueue.clear();
    await _saveQueue();
  }

  /// 🔄 Force process (สำหรับ debug)
  Future<void> forceProcess() async {
    await _processQueue();
  }
}

/// 📋 Deferred Task
class DeferredTask {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final TaskPriority priority;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? completedAt;
  final String? error;

  DeferredTask({
    required this.id,
    required this.type,
    required this.payload,
    required this.priority,
    required this.status,
    required this.createdAt,
    this.expiresAt,
    this.completedAt,
    this.error,
  });

  DeferredTask copyWith({
    TaskStatus? status,
    DateTime? completedAt,
    String? error,
  }) => DeferredTask(
        id: id,
        type: type,
        payload: payload,
        priority: priority,
        status: status ?? this.status,
        createdAt: createdAt,
        expiresAt: expiresAt,
        completedAt: completedAt ?? this.completedAt,
        error: error ?? this.error,
      );

  factory DeferredTask.fromJson(Map<String, dynamic> json) => DeferredTask(
        id: json['id'] as String,
        type: json['type'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        priority: TaskPriority.values[json['priority'] as int],
        status: TaskStatus.values[json['status'] as int],
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        error: json['error'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'priority': priority.index,
        'status': status.index,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'error': error,
      };
}

/// ⚡ Task Priority
enum TaskPriority {
  low,
  normal,
  high,
}

/// 📊 Task Status
enum TaskStatus {
  pending,
  running,
  completed,
  failed,
  expired,
}
