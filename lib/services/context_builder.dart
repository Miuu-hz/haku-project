import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'chat_history_service.dart';
import 'geofence_service.dart';
import 'topic_service.dart';
import 'user_profile_service.dart';
import 'vector_service.dart';

/// 🧱 Context Builder - Assembly Context for AI
///
/// รวมร่างข้อมูลจากหลายแหล่งเป็น Context สำหรับ LLM
///
/// Components:
/// - [Identity]: User profile (inject เสมอ)
/// - [Status]: Sensor data (time, location, battery)
/// - [Mem]: RAG results (topic summaries)
/// - [Recent]: Recent messages (Thai)
/// - [Reply]: Referenced context (±2 around reply)
///
/// Output: Lean Syntax เพื่อประหยัด Token

class ContextBuilder {
  static final ContextBuilder _instance = ContextBuilder._internal();
  factory ContextBuilder() => _instance;
  ContextBuilder._internal();

  final UserProfileService _profileService = UserProfileService();
  final ChatHistoryService _chatHistory = ChatHistoryService();
  final TopicService _topicService = TopicService();
  final VectorService _vectorService = VectorService();
  final GeofenceService _geofenceService = GeofenceService();

  bool _isInitialized = false;

  // Settings
  static const int recentMessageCount = 5;
  static const int replyContextRadius = 2; // ±2 messages
  static const int maxRagResults = 3;
  static const int maxContextTokens = 600; // Token budget for context

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _profileService.initialize();
    await _chatHistory.initialize();
    await _topicService.initialize();
    await _vectorService.initialize();
    await _geofenceService.initialize();

    _isInitialized = true;
    debugPrint('✅ Context Builder initialized');
  }

  // ============================================================
  // 🧱 BUILD CONTEXT
  // ============================================================

  /// 🧱 Build full context for AI
  ///
  /// [userInput] - Current user message
  /// [replyToMessageId] - If replying to specific message
  Future<AIContext> buildContext({
    required String userInput,
    String? replyToMessageId,
  }) async {
    final parts = <String>[];

    // 1. Identity Card (always included)
    final identity = _profileService.getIdentityCard();
    if (identity.isNotEmpty) {
      parts.add(identity);
    }

    // 2. Status Bar
    final status = await _buildStatusBar();
    parts.add(status);

    // 3. Reply Context (if replying)
    String? replyContext;
    if (replyToMessageId != null) {
      replyContext = await _buildReplyContext(replyToMessageId);
      if (replyContext.isNotEmpty) {
        parts.add('[Reply]\n$replyContext');
      }
    }

    // 4. RAG Memory (topic summaries)
    final ragContext = await _buildRagContext(userInput);
    if (ragContext.isNotEmpty) {
      parts.add('[Mem]\n$ragContext');
    }

    // 5. Recent Messages (Thai)
    final recentContext = _buildRecentContext();
    if (recentContext.isNotEmpty) {
      parts.add('[Recent]\n$recentContext');
    }

    final fullContext = parts.join('\n');

    return AIContext(
      identity: identity,
      status: status,
      memory: ragContext,
      recent: recentContext,
      replyContext: replyContext,
      fullContext: fullContext,
      estimatedTokens: _estimateTokens(fullContext),
    );
  }

  /// 📊 Build status bar
  ///
  /// Format: [Fri 18:00|📍Home|🔋80%|🎵Spotify]
  Future<String> _buildStatusBar() async {
    final now = DateTime.now();
    final parts = <String>[];

    // Time
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final day = dayNames[now.weekday - 1];
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    parts.add('$day $time');

    // Location
    final currentZone = _geofenceService.currentZone;
    if (currentZone != null) {
      parts.add('📍${currentZone.name}');
    }

    // TODO: Add battery, music, etc.

    return '[${parts.join("|")}]';
  }

  /// 💬 Build reply context (±2 around target)
  Future<String> _buildReplyContext(String messageId) async {
    final history = _chatHistory.rawHistory;

    // Find message index
    int targetIndex = -1;
    for (var i = 0; i < history.length; i++) {
      if (history[i].id == messageId) {
        targetIndex = i;
        break;
      }
    }

    if (targetIndex < 0) return '';

    // Get ±2 messages
    final start = (targetIndex - replyContextRadius).clamp(0, history.length);
    final end = (targetIndex + replyContextRadius + 1).clamp(0, history.length);

    final messages = <String>[];

    // Get topic summary for context
    final topic = _topicService.getTopicForMessage(messageId);
    if (topic != null && topic.summary.isNotEmpty) {
      messages.add('Topic:${topic.name}|${topic.summary}');
    }

    // Get messages
    for (var i = start; i < end; i++) {
      final msg = history[i];
      final prefix = msg.role == 'user' ? 'U' : 'H';
      final marker = i == targetIndex ? '→' : ' ';
      messages.add('$marker$prefix:${msg.content}');
    }

    return messages.join('\n');
  }

  /// 🧠 Build RAG context (topic summaries)
  Future<String> _buildRagContext(String query) async {
    // Search similar topics
    final results = _vectorService.searchSimilar(query, topK: maxRagResults);

    if (results.isEmpty) return '';

    final summaries = <String>[];

    for (final result in results) {
      final topic = _topicService.getTopicById(result.topicId);
      if (topic != null && topic.summary.isNotEmpty) {
        // Lean format: Topic:Name|Summary
        summaries.add('${topic.name}|${topic.summary}');
      }
    }

    return summaries.join('\n');
  }

  /// 💬 Build recent messages context
  String _buildRecentContext() {
    final history = _chatHistory.rawHistory;
    if (history.isEmpty) return '';

    final recent = history.length > recentMessageCount
        ? history.sublist(history.length - recentMessageCount)
        : history;

    final messages = <String>[];

    for (final msg in recent) {
      final prefix = msg.role == 'user' ? 'U' : 'H';
      messages.add('$prefix:${msg.content}');
    }

    return messages.join('\n');
  }

  /// 📊 Estimate token count
  int _estimateTokens(String text) {
    // Rough estimate: Thai ~1.5 tokens/char, English ~0.25 tokens/char
    final thaiChars = text.runes.where((r) => r >= 0x0E00 && r <= 0x0E7F).length;
    final otherChars = text.length - thaiChars;

    return (thaiChars * 1.5 + otherChars * 0.25).round();
  }

  // ============================================================
  // 🎯 SPECIALIZED CONTEXTS
  // ============================================================

  /// 🎯 Build context for proactive trigger
  Future<AIContext> buildProactiveContext({
    String? triggerReason,
    Position? currentPosition,
  }) async {
    final parts = <String>[];

    // Identity
    final identity = _profileService.getIdentityCard();
    if (identity.isNotEmpty) {
      parts.add(identity);
    }

    // Status
    final status = await _buildStatusBar();
    parts.add(status);

    // Trigger reason
    if (triggerReason != null) {
      parts.add('[Trigger:$triggerReason]');
    }

    // Recent context (shorter for proactive)
    final history = _chatHistory.rawHistory;
    if (history.isNotEmpty) {
      final lastMsg = history.last;
      parts.add('[Last:${lastMsg.content}]');
    }

    // Relevant topics
    if (triggerReason != null) {
      final ragContext = await _buildRagContext(triggerReason);
      if (ragContext.isNotEmpty) {
        parts.add('[Mem]\n$ragContext');
      }
    }

    final fullContext = parts.join('\n');

    return AIContext(
      identity: identity,
      status: status,
      memory: '',
      recent: '',
      replyContext: null,
      fullContext: fullContext,
      estimatedTokens: _estimateTokens(fullContext),
    );
  }

  /// 📅 Build context for event extraction
  Future<AIContext> buildEventContext(String text) async {
    final parts = <String>[];

    // Identity (for name references)
    final identity = _profileService.getIdentityCard();
    if (identity.isNotEmpty) {
      parts.add(identity);
    }

    // Status (for time context)
    final status = await _buildStatusBar();
    parts.add(status);

    // Relevant places
    final placeTopic = await _buildRagContext('สถานที่ นัด');
    if (placeTopic.isNotEmpty) {
      parts.add('[Places]\n$placeTopic');
    }

    final fullContext = parts.join('\n');

    return AIContext(
      identity: identity,
      status: status,
      memory: placeTopic,
      recent: '',
      replyContext: null,
      fullContext: fullContext,
      estimatedTokens: _estimateTokens(fullContext),
    );
  }

  // ============================================================
  // 📊 UTILITIES
  // ============================================================

  /// 📊 Get context stats
  Map<String, dynamic> getContextStats() {
    return {
      'hasProfile': _profileService.hasProfile,
      'topicCount': _topicService.topicCount,
      'vectorCount': _vectorService.getStats()['storedVectors'],
      'historyCount': _chatHistory.rawHistory.length,
    };
  }

  /// 🔍 Preview context for debugging
  Future<String> previewContext(String userInput) async {
    final context = await buildContext(userInput: userInput);
    return '''
=== AI Context Preview ===
Estimated Tokens: ${context.estimatedTokens}

${context.fullContext}
=========================
''';
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// 🧱 AI Context
class AIContext {
  final String identity;
  final String status;
  final String memory;
  final String recent;
  final String? replyContext;
  final String fullContext;
  final int estimatedTokens;

  AIContext({
    required this.identity,
    required this.status,
    required this.memory,
    required this.recent,
    this.replyContext,
    required this.fullContext,
    required this.estimatedTokens,
  });

  /// Has reply reference
  bool get hasReply => replyContext != null && replyContext!.isNotEmpty;

  /// Has memory context
  bool get hasMemory => memory.isNotEmpty;

  /// Is within token budget
  bool get isWithinBudget => estimatedTokens <= ContextBuilder.maxContextTokens;
}
