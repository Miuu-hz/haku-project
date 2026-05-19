import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_helper.dart';
import 'deferred_task_service.dart';
import 'llm_provider_manager.dart';
import 'prompt_builder.dart';
import 'rag_service.dart';
import 'unified_vector_service.dart';
import 'user_profile_service.dart';
import 'wiki_service.dart';
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
    service.registerHandler('memory_consolidation', handleMemoryConsolidation);
    service.registerHandler('wiki_update', handleWikiUpdate);
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

  /// 🧠 Handler: consolidate episodic log เก่า → facts (LTM distillation)
  ///
  /// ดึง chat log อายุ >7 วัน → LLM summarize → บันทึกเป็น fact + mark consolidated
  /// prune entries อายุ >30 วัน ที่ consolidated แล้ว
  static Future<void> handleMemoryConsolidation(
    Map<String, dynamic> payload,
  ) async {
    debugPrint('🧠 Running MemoryConsolidation...');
    final db = DatabaseHelper.instance;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String();

    final rows = await db.database.then((d) => d.query(
          DatabaseHelper.tableChatLog,
          where: 'consolidated = 0 AND timestamp < ?',
          whereArgs: [cutoff],
          orderBy: 'timestamp ASC',
          limit: 20,
        ));

    if (rows.isEmpty) {
      debugPrint('✅ No entries to consolidate');
      return;
    }

    // รวม summaries เป็น batch แล้วสรุปด้วย LLM 1 ครั้ง
    final llm = LLMProviderManager().provider;
    if (!llm.isInitialized) {
      debugPrint('⚠️ LLM not ready — skipping consolidation');
      return;
    }

    final texts = rows
        .map((r) => r['summary_en'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .join('. ');

    final prompt = PromptBuilder.buildConsolidationPrompt(texts);
    try {
      final result = await llm.generate(prompt);
      if (result.trim().isNotEmpty) {
        await UnifiedVectorService().addFact(
          category: 'consolidated_memory',
          content: result.trim(),
          metadata: {
            'source_count': rows.length,
            'from': rows.first['timestamp'],
            'to': rows.last['timestamp'],
          },
        );
        debugPrint('✅ Consolidated ${rows.length} entries → 1 fact');
      }
    } catch (e) {
      debugPrint('⚠️ Consolidation LLM failed: $e');
    }

    // mark consolidated + prune เก่า >30 วัน
    final ids = rows.map((r) => r['id'] as int).toList();
    await db.markChatLogsConsolidated(ids);
    final pruned = await db.pruneOldChatLogs(olderThanDays: 30);
    debugPrint('🗑️ Pruned $pruned old consolidated entries');
  }

  /// 📚 Handler: อัปเดต Wiki summaries สำหรับ knowledge pages ที่รอ
  static Future<void> handleWikiUpdate(
    Map<String, dynamic> payload,
  ) async {
    debugPrint('📚 Running WikiUpdate...');
    await WikiService().updatePendingSummaries(batchSize: 5);
    debugPrint('✅ WikiUpdate complete');
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
