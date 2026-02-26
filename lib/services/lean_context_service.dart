import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_profile_service.dart';

/// 📦 Lean Context Service - บีบอัด Context ให้ประหยัด Token
///
/// ปัญหา: Gemma 3 1B มี context ~2048 tokens
/// ทางแก้: Compress chat history จาก ~150 tokens → ~30 tokens ต่อคู่สนทนา
///
/// ผลลัพธ์:
/// - Normal: 5 chats × 150 = 750 tokens
/// - Lean: 25 chats × 30 = 750 tokens (5x memory!)
///
/// Format:
/// - Chat 1-3: Full Thai (เพื่อ context ใกล้)
/// - Chat 4+: Lean Syntax Thai (บีบอัด)
/// - Summary: English (ประหยัดสุด)

class LeanContextService {
  static final LeanContextService _instance = LeanContextService._internal();
  factory LeanContextService() => _instance;
  LeanContextService._internal();

  final UserProfileService _userProfile = UserProfileService();

  static const String _sessionSummariesKey = 'session_summaries';
  static const String _currentSessionKey = 'current_session';

  // Lean Syntax messages
  List<LeanMessage> _leanMessages = [];

  // Session summaries (English)
  List<SessionSummary> _sessionSummaries = [];

  // Current session start time
  DateTime? _sessionStart;

  bool _isInitialized = false;

  // Settings
  static const int fullContextCount = 3;    // จำนวน chat ที่แสดงแบบ full
  static const int maxLeanMessages = 25;    // จำนวน lean messages สูงสุด
  static const int maxSummaries = 10;       // จำนวน session summaries สูงสุด

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadFromStorage();
    _isInitialized = true;
    debugPrint('✅ Lean Context Service initialized');
    debugPrint('   - Lean messages: ${_leanMessages.length}');
    debugPrint('   - Session summaries: ${_sessionSummaries.length}');
  }

  /// 📥 Load from storage
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load lean messages
      final leanJson = prefs.getString(_currentSessionKey);
      if (leanJson != null) {
        final data = jsonDecode(leanJson) as Map<String, dynamic>;
        _leanMessages = (data['messages'] as List<dynamic>?)
            ?.map((e) => LeanMessage.fromJson(e as Map<String, dynamic>))
            .toList() ?? [];
        _sessionStart = data['start'] != null
            ? DateTime.parse(data['start'] as String)
            : null;
      }

      // Load session summaries
      final summaryJson = prefs.getString(_sessionSummariesKey);
      if (summaryJson != null) {
        final List<dynamic> list = jsonDecode(summaryJson) as List<dynamic>;
        _sessionSummaries = list
            .map((e) => SessionSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading lean context: $e');
    }
  }

  /// 💾 Save to storage
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save current session
      await prefs.setString(_currentSessionKey, jsonEncode({
        'messages': _leanMessages.map((m) => m.toJson()).toList(),
        'start': _sessionStart?.toIso8601String(),
      }));

      // Save summaries
      await prefs.setString(
        _sessionSummariesKey,
        jsonEncode(_sessionSummaries.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving lean context: $e');
    }
  }

  // ============================================================
  // 📝 ADD MESSAGES
  // ============================================================

  /// 🔄 Update the last AI message's lean content with English translation
  /// Called after SecretChatService produces an English summary.
  /// English is ~3-5x more token-efficient than Thai for Gemma tokenizer.
  void updateLastPairWithEnglish(String englishSummary) {
    if (_leanMessages.isEmpty) return;
    for (int i = _leanMessages.length - 1; i >= 0; i--) {
      if (_leanMessages[i].role == MessageRole.assistant) {
        final msg = _leanMessages[i];
        _leanMessages[i] = LeanMessage(
          role: msg.role,
          content: msg.content,
          leanContent: englishSummary,
          timestamp: msg.timestamp,
          actions: msg.actions,
        );
        _saveToStorage();
        debugPrint('📦 Lean→EN: "$englishSummary"');
        return;
      }
    }
  }

  /// ➕ Add user message
  Future<void> addUserMessage(String content) async {
    _ensureSessionStarted();

    _leanMessages.add(LeanMessage(
      role: MessageRole.user,
      content: content,
      leanContent: _compressToLean(content),
      timestamp: DateTime.now(),
    ));

    await _trimIfNeeded();
    await _saveToStorage();
  }

  /// ➕ Add AI response
  Future<void> addAIMessage(String content, {List<String>? actions}) async {
    _ensureSessionStarted();

    _leanMessages.add(LeanMessage(
      role: MessageRole.assistant,
      content: content,
      leanContent: _compressToLean(content),
      timestamp: DateTime.now(),
      actions: actions,
    ));

    await _trimIfNeeded();
    await _saveToStorage();
  }

  /// 🔄 Ensure session is started
  void _ensureSessionStarted() {
    _sessionStart ??= DateTime.now();
  }

  /// ✂️ Trim if exceeds max
  Future<void> _trimIfNeeded() async {
    if (_leanMessages.length > maxLeanMessages * 2) { // user + AI pairs
      // เก็บข้อความเก่าเป็น summary
      final toSummarize = _leanMessages.sublist(0, _leanMessages.length - maxLeanMessages * 2);

      // สร้าง quick summary (rule-based, ไม่ใช้ LLM)
      final quickSummary = _createQuickSummary(toSummarize);
      if (quickSummary != null) {
        _sessionSummaries.add(quickSummary);

        // เก็บ summaries ไม่เกิน max
        if (_sessionSummaries.length > maxSummaries) {
          _sessionSummaries = _sessionSummaries.sublist(_sessionSummaries.length - maxSummaries);
        }
      }

      // ตัดข้อความเก่าออก
      _leanMessages = _leanMessages.sublist(toSummarize.length);
      debugPrint('✂️ Trimmed ${toSummarize.length} messages, created summary');
    }
  }

  // ============================================================
  // 📦 LEAN SYNTAX COMPRESSION
  // ============================================================

  /// 🗜️ Compress Thai text to lean syntax
  String _compressToLean(String text) {
    // 1. ตัดคำลงท้าย
    String lean = text
        .replaceAll(RegExp(r'ครับ|ค่ะ|นะครับ|นะคะ|คะ|จ้า|จ๊ะ|นะ'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // 2. ตัดคำซ้ำและคำเชื่อม
    lean = lean
        .replaceAll(RegExp(r'แล้วก็|และก็|แล้ว|และ'), ',')
        .replaceAll(RegExp(r'ก็คือ|คือว่า|คือ'), ':')
        .replaceAll(RegExp(r'เพราะว่า|เพราะ'), '>')
        .replaceAll(RegExp(r'แต่ว่า|แต่'), '/')
        .replaceAll(RegExp(r',+'), ',')
        .replaceAll(RegExp(r'\s*,\s*'), ',');

    // 3. ย่อคำที่พบบ่อย
    lean = lean
        .replaceAll('วันนี้', 'วนน')
        .replaceAll('พรุ่งนี้', 'พนน')
        .replaceAll('เมื่อวาน', 'มวน')
        .replaceAll('ตอนเช้า', 'ช.')
        .replaceAll('ตอนเย็น', 'ย.')
        .replaceAll('ตอนกลางคืน', 'คน.')
        .replaceAll('ไม่ได้', '!ได้')
        .replaceAll('ไม่มี', '!มี')
        .replaceAll('ไม่ใช่', '!ใช่');

    // 4. จำกัดความยาว
    if (lean.length > 50) {
      lean = '${lean.substring(0, 47)}...';
    }

    return lean;
  }

  /// 📊 Create quick summary (rule-based)
  SessionSummary? _createQuickSummary(List<LeanMessage> messages) {
    if (messages.isEmpty) return null;

    // Extract keywords/topics
    final topics = <String>{};
    final actions = <String>[];

    for (final msg in messages) {
      // ตรวจจับ topics จาก keywords
      final content = msg.content.toLowerCase();

      if (content.contains('งาน') || content.contains('ทำงาน')) topics.add('work');
      if (content.contains('อาหาร') || content.contains('กิน')) topics.add('food');
      if (content.contains('เหนื่อย') || content.contains('พัก')) topics.add('rest');
      if (content.contains('สุขภาพ') || content.contains('ป่วย') || content.contains('เมน')) topics.add('health');
      if (content.contains('เพื่อน') || content.contains('ครอบครัว')) topics.add('social');
      if (content.contains('เป้า') || content.contains('อยาก')) topics.add('goals');
      if (content.contains('ร้าน') || content.contains('ไป')) topics.add('places');

      // Collect actions
      if (msg.actions != null) {
        actions.addAll(msg.actions!);
      }
    }

    final firstTime = messages.first.timestamp;
    final lastTime = messages.last.timestamp;

    return SessionSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      summaryEn: 'Talked about: ${topics.join(", ")}. ${actions.isNotEmpty ? "Actions: ${actions.join(", ")}" : ""}',
      topics: topics.toList(),
      startTime: firstTime,
      endTime: lastTime,
      messageCount: messages.length,
      createdAt: DateTime.now(),
    );
  }

  // ============================================================
  // 📤 GET CONTEXT FOR AI
  // ============================================================

  /// 📝 Build context for AI prompt
  ///
  /// Format:
  /// [Identity] + [Summaries] + [Lean History] + [Full Recent]
  String buildContextForAI() {
    final buffer = StringBuffer();

    // 1. Identity Card (Lean)
    final identity = _userProfile.getIdentityCard();
    if (identity.isNotEmpty) {
      buffer.writeln(identity);
    }

    // 2. Session Summaries (English, compact)
    if (_sessionSummaries.isNotEmpty) {
      buffer.writeln('[History]');
      for (final summary in _sessionSummaries.take(3)) {
        buffer.writeln('• ${summary.summaryEn}');
      }
    }

    // 3. Lean History (Chat 4 to N-3)
    if (_leanMessages.length > fullContextCount * 2) {
      buffer.writeln('[Context]');
      final leanPart = _leanMessages.sublist(0, _leanMessages.length - fullContextCount * 2);
      for (final msg in leanPart) {
        final prefix = msg.role == MessageRole.user ? 'U' : 'H';
        buffer.writeln('$prefix:${msg.leanContent}');
      }
    }

    // 4. Full Recent (Last 3 pairs)
    if (_leanMessages.isNotEmpty) {
      buffer.writeln('[Recent]');
      final recentStart = (_leanMessages.length - fullContextCount * 2).clamp(0, _leanMessages.length);
      final recent = _leanMessages.sublist(recentStart);
      for (final msg in recent) {
        final prefix = msg.role == MessageRole.user ? 'User' : 'Haku';
        buffer.writeln('$prefix: ${msg.content}');
      }
    }

    return buffer.toString().trim();
  }

  /// 📊 Get estimated token count
  int getEstimatedTokenCount() {
    final context = buildContextForAI();
    // Thai uses ~1.5 tokens per character on average
    return (context.length * 0.5).round();
  }

  /// 📋 Get message count
  int get messageCount => _leanMessages.length;

  /// 📋 Get summary count
  int get summaryCount => _sessionSummaries.length;

  // ============================================================
  // 🔄 SESSION MANAGEMENT
  // ============================================================

  /// 🔚 End current session and create summary
  Future<SessionSummary?> endSession() async {
    if (_leanMessages.isEmpty) return null;

    final summary = _createQuickSummary(_leanMessages);
    if (summary != null) {
      _sessionSummaries.add(summary);

      // Trim summaries
      if (_sessionSummaries.length > maxSummaries) {
        _sessionSummaries = _sessionSummaries.sublist(_sessionSummaries.length - maxSummaries);
      }
    }

    // Clear current session
    _leanMessages.clear();
    _sessionStart = null;

    await _saveToStorage();
    debugPrint('✅ Session ended, summary created');

    return summary;
  }

  /// 🗑️ Clear all
  Future<void> clearAll() async {
    _leanMessages.clear();
    _sessionSummaries.clear();
    _sessionStart = null;
    await _saveToStorage();
  }

  /// 📊 Get session info
  Map<String, dynamic> getSessionInfo() => {
    'messageCount': _leanMessages.length,
    'summaryCount': _sessionSummaries.length,
    'sessionStart': _sessionStart?.toIso8601String(),
    'estimatedTokens': getEstimatedTokenCount(),
  };
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// Message role
enum MessageRole { user, assistant }

/// 📝 Lean Message
class LeanMessage {
  final MessageRole role;
  final String content;       // Original Thai
  final String leanContent;   // Compressed
  final DateTime timestamp;
  final List<String>? actions;

  LeanMessage({
    required this.role,
    required this.content,
    required this.leanContent,
    required this.timestamp,
    this.actions,
  });

  factory LeanMessage.fromJson(Map<String, dynamic> json) => LeanMessage(
    role: json['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
    content: json['content'] as String,
    leanContent: json['leanContent'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    actions: (json['actions'] as List<dynamic>?)?.cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'role': role == MessageRole.user ? 'user' : 'assistant',
    'content': content,
    'leanContent': leanContent,
    'timestamp': timestamp.toIso8601String(),
    'actions': actions,
  };
}

/// 📊 Session Summary (English)
class SessionSummary {
  final String id;
  final String summaryEn;        // English summary
  final List<String> topics;     // Detected topics
  final DateTime startTime;
  final DateTime endTime;
  final int messageCount;
  final DateTime createdAt;

  // Optional extended data
  final Map<String, dynamic>? healthFlags;
  final List<String>? factsLearned;

  SessionSummary({
    required this.id,
    required this.summaryEn,
    required this.topics,
    required this.startTime,
    required this.endTime,
    required this.messageCount,
    required this.createdAt,
    this.healthFlags,
    this.factsLearned,
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) => SessionSummary(
    id: json['id'] as String,
    summaryEn: json['summaryEn'] as String,
    topics: List<String>.from(json['topics'] as Iterable<dynamic>),
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: DateTime.parse(json['endTime'] as String),
    messageCount: json['messageCount'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    healthFlags: json['healthFlags'] as Map<String, dynamic>?,
    factsLearned: (json['factsLearned'] as List<dynamic>?)?.cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'summaryEn': summaryEn,
    'topics': topics,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'messageCount': messageCount,
    'createdAt': createdAt.toIso8601String(),
    'healthFlags': healthFlags,
    'factsLearned': factsLearned,
  };
}
