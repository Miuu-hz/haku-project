import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_helper.dart';
import 'deferred_task_service.dart';
import 'rag_service.dart';
import 'unified_vector_service.dart';
import 'user_profile_service.dart';
import 'workers/reminder_worker.dart';
import 'triggers/manager_summary_strategy.dart';

/// 🏭 Background Task Handlers
///
/// ลงทะเบียน handler สำหรับ DeferredTaskService
/// ทำงานตอนชาร์จ: วิเคราะห์ patterns, reindex vectors
class BackgroundTaskHandlers {
  static const String _analysisResultKey = 'last_manager_analysis';

  /// 📝 ลงทะเบียน handlers ทั้งหมด
  static void registerAll() {
    final service = DeferredTaskService();
    service.registerHandler('manager_summary', handleManagerSummary);
    service.registerHandler('reindex_vectors', handleReindexVectors);
  }

  /// 📊 Handler: วิเคราะห์ daily patterns ด้วย ManagerSummaryStrategy
  static Future<void> handleManagerSummary(
    Map<String, dynamic> payload,
  ) async {
    debugPrint('📊 Running ManagerSummaryStrategy...');

    final strategy = ManagerSummaryStrategy(
      vectorService: UnifiedVectorService(),
      userProfile: UserProfileService(),
    );

    final result = await strategy.analyze();

    // Dispatch worker tasks จากผลวิเคราะห์
    for (final task in result.workerTasks) {
      await _dispatchWorkerTask(task);
    }

    // บันทึกผลวิเคราะห์
    await _saveAnalysisResult(result);

    debugPrint(
      '✅ ManagerSummary complete: '
      '${result.insights.length} insights, '
      '${result.recommendations.length} recommendations',
    );
  }

  /// 🔄 Handler: Reindex vectors ใน RAG
  static Future<void> handleReindexVectors(
    Map<String, dynamic> payload,
  ) async {
    debugPrint('🔄 Reindexing vectors...');

    final entries = await DatabaseHelper.instance.getAllEntries();
    if (entries.isNotEmpty) {
      await RAGService().indexEntries(entries);
      debugPrint('✅ Reindexed ${entries.length} entries');
    }
  }

  /// 🎯 Dispatch worker task ไปยัง worker ที่เหมาะสม
  static Future<void> _dispatchWorkerTask(WorkerTask task) async {
    debugPrint('🎯 Dispatching: ${task.worker.name} → ${task.action}');

    switch (task.worker) {
      case WorkerType.reminder:
        await _handleReminderTask(task);
        break;
      case WorkerType.fact:
        // Profile summary update — ข้อมูลถูกบันทึกผ่าน UserProfileService แล้ว
        debugPrint('📝 Fact task: ${task.action}');
        break;
      case WorkerType.calendar:
      case WorkerType.health:
        debugPrint('📋 ${task.worker.name} task queued: ${task.action}');
        break;
    }
  }

  /// 🔔 สร้าง reminder จาก worker task
  static Future<void> _handleReminderTask(WorkerTask task) async {
    final data = task.data ?? {};
    final message = data['message'] as String? ?? 'แจ้งเตือนจาก Haku';
    final durationDays = data['duration_days'] as int? ?? 1;

    final worker = ReminderWorker();
    await worker.initialize();

    // สร้าง daily reminder สำหรับติดตามอาการ
    final reminder = Reminder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: message,
      time: ReminderTime(hour: 9, minute: 0),
      frequency: ReminderFrequency.daily,
      isActive: true,
      createdAt: DateTime.now(),
    );

    await worker.addReminder(reminder);
    debugPrint('🔔 Created reminder: $message (${durationDays}d)');
  }

  /// 💾 บันทึกผลวิเคราะห์ล่าสุด
  static Future<void> _saveAnalysisResult(
    ManagerSummaryResult result,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _analysisResultKey,
        jsonEncode(result.toJson()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving analysis result: $e');
    }
  }
}
