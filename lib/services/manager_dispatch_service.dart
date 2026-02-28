import 'package:flutter/foundation.dart';

import 'ai_action_service.dart';
import 'llm_provider_manager.dart';
import 'prompt_builder.dart';
import 'secret_chat_service.dart';
import 'web_search_service.dart';

/// 🧠 Manager Dispatch Service (Big Manager)
///
/// Stage 2 ของ Two-Stage LLM Architecture:
/// - รับ user message
/// - เรียก LLM ด้วย lean prompt (~120 tokens input, ~20 tokens output)
/// - Classify intent (SEARCH, SCHEDULE, REMIND, PLACE, NONE)
/// - Urgent → execute ทันที + return ผลให้ UI
/// - Low priority → enqueue ใน DeferredTaskService

class ManagerDispatchService {
  static final ManagerDispatchService _instance =
      ManagerDispatchService._internal();
  factory ManagerDispatchService() => _instance;
  ManagerDispatchService._internal();

  final WebSearchService _webSearch = WebSearchService();
  final AIActionService _actionService = AIActionService();

  // Deduplication: เก็บ recent searches (TTL 60s)
  static final Map<String, DateTime> _recentSearches = {};

  /// 🧠 Classify intent + execute urgent actions
  ///
  /// Returns [ManagerResult] with:
  /// - intent: ประเภทงาน
  /// - payload: ข้อมูลจาก LLM output
  /// - actionData: ผลจากการ execute urgent action (ถ้ามี)
  Future<ManagerResult> classifyAndDispatch(String userMessage) async {
    final llm = LLMProviderManager().provider;
    if (!llm.isInitialized) {
      return ManagerResult(intent: ManagerIntent.none, payload: '');
    }

    try {
      // 1. เรียก LLM ด้วย lean manager prompt
      final prompt =
          PromptBuilder.buildManagerPrompt(userMessage: userMessage);
      final raw = await llm.generate(prompt);
      debugPrint('🧠 Manager raw output: ${raw.trim()}');

      // 2. Parse output
      final result = _parseManagerOutput(raw.trim());
      debugPrint('🧠 Manager classified: ${result.intent.name}');

      // 3. Execute urgent actions or enqueue low priority
      if (result.intent != ManagerIntent.none) {
        final actionData = await _executeUrgent(result, userMessage);
        return ManagerResult(
          intent: result.intent,
          payload: result.payload,
          actionData: actionData,
        );
      }

      return result;
    } catch (e) {
      debugPrint('⚠️ Manager dispatch failed: $e');
      return ManagerResult(intent: ManagerIntent.none, payload: '');
    }
  }

  /// 🤫 Dispatch from Secret Chat English log (0 extra LLM calls)
  ///
  /// Intent + tags มาจาก Secret Chat extraction แล้ว — ไม่ต้องเรียก LLM ซ้ำ
  /// Returns action confirmation string ถ้ามี urgent action
  Future<String?> dispatchFromLog(
    EnglishLogEntry logEntry,
    String originalUserMessage,
  ) async {
    debugPrint('🧠 Big Manager: dispatching from English log '
        '(intent=${logEntry.intent})');

    // Map Secret Chat intent → ManagerIntent
    final intent = switch (logEntry.intent) {
      'schedule' => ManagerIntent.schedule,
      'search' => ManagerIntent.search,
      'query' => ManagerIntent.none, // query = ถามเรื่องของตัวเอง ไม่ใช่ search web
      'log' || 'chat' => ManagerIntent.none,
      _ => ManagerIntent.none,
    };

    if (intent == ManagerIntent.none) return null;

    final result = ManagerResult(
      intent: intent,
      payload: logEntry.tags.join(', '),
    );

    return _executeUrgent(result, originalUserMessage);
  }

  /// 📝 Parse manager LLM output (single line)
  ManagerResult _parseManagerOutput(String output) {
    // ดึงบรรทัดแรกที่มีความหมาย
    final line = output
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => 'NONE');

    if (line.startsWith('SEARCH:')) {
      return ManagerResult(
        intent: ManagerIntent.search,
        payload: line.substring(7).trim(),
      );
    }
    if (line.startsWith('SCHEDULE:')) {
      return ManagerResult(
        intent: ManagerIntent.schedule,
        payload: line.substring(9).trim(),
      );
    }
    if (line.startsWith('REMIND:')) {
      return ManagerResult(
        intent: ManagerIntent.remind,
        payload: line.substring(7).trim(),
      );
    }
    if (line.startsWith('PLACE:')) {
      return ManagerResult(
        intent: ManagerIntent.place,
        payload: line.substring(6).trim(),
      );
    }

    return ManagerResult(intent: ManagerIntent.none, payload: '');
  }

  /// ⚡ Execute urgent actions immediately, return result for UI
  Future<String?> _executeUrgent(
    ManagerResult result,
    String userMessage,
  ) async {
    switch (result.intent) {
      case ManagerIntent.search:
        // Deduplication check
        if (_isDuplicateSearch(result.payload)) {
          debugPrint('🔄 Skipping duplicate search: ${result.payload}');
          return null;
        }
        try {
          await _webSearch.initialize();
          final searchResult = await _webSearch.searchForAI(result.payload);
          debugPrint('✅ Manager web search done: ${result.payload}');
          return searchResult;
        } catch (e) {
          debugPrint('⚠️ Manager web search failed: $e');
          return null;
        }

      case ManagerIntent.schedule:
        // Parse payload format: "title,date,time"
        final parts = result.payload.split(',').map((s) => s.trim()).toList();
        final action = AIAction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: AIActionType.schedule,
          params: {
            'title': parts.isNotEmpty ? parts[0] : userMessage,
            if (parts.length > 1) 'date': parts[1],
            if (parts.length > 2) 'time': parts[2],
          },
          rawText: result.payload,
          createdAt: DateTime.now(),
        );
        final actionResult = await _actionService.executeAction(action);
        if (actionResult.success) {
          return '📅 สร้างนัดหมาย: ${parts.isNotEmpty ? parts[0] : userMessage}';
        }
        return null;

      case ManagerIntent.remind:
        // Parse payload format: "message,time"
        final parts = result.payload.split(',').map((s) => s.trim()).toList();
        final action = AIAction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: AIActionType.reminder,
          params: {
            'message': parts.isNotEmpty ? parts[0] : userMessage,
            if (parts.length > 1) 'minutes': parts[1],
          },
          rawText: result.payload,
          createdAt: DateTime.now(),
        );
        final actionResult = await _actionService.executeAction(action);
        if (actionResult.success) {
          return '🔔 ตั้งเตือน: ${parts.isNotEmpty ? parts[0] : userMessage}';
        }
        return null;

      case ManagerIntent.place:
        final action = AIAction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: AIActionType.searchPlace,
          params: {'query': result.payload},
          rawText: result.payload,
          createdAt: DateTime.now(),
        );
        final actionResult = await _actionService.executeAction(action);
        if (actionResult.hasDataForAI) {
          return actionResult.data;
        }
        return null;

      case ManagerIntent.none:
        return null;
    }
  }

  /// 🔄 Check if this search was recently done (TTL 60s)
  static bool _isDuplicateSearch(String query) {
    final normalized = query.toLowerCase().trim();

    // Cleanup expired entries
    _recentSearches.removeWhere(
      (_, time) => DateTime.now().difference(time).inSeconds > 60,
    );

    final lastSearch = _recentSearches[normalized];
    if (lastSearch != null) {
      return true;
    }
    _recentSearches[normalized] = DateTime.now();
    return false;
  }

  /// 📝 Mark a query as recently searched (for deduplication with SmartPreprocessor)
  static void markSearched(String query) {
    _recentSearches[query.toLowerCase().trim()] = DateTime.now();
  }
}

/// 🎯 Manager Intent Types
enum ManagerIntent {
  search,
  schedule,
  remind,
  place,
  none,
}

/// 📦 Manager Result
class ManagerResult {
  final ManagerIntent intent;
  final String payload;
  final String? actionData;

  ManagerResult({
    required this.intent,
    required this.payload,
    this.actionData,
  });
}
