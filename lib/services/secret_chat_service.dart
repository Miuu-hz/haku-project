import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'llm_provider_manager.dart';
import 'prompt_builder.dart';

/// 🤫 Secret Chat Service
///
/// หลัง Face LLM ตอบ user (Thai) → แปล exchange เป็น English log แบบ real-time
/// Big Manager อ่าน English log → dispatch workers → ไม่ต้องเรียก LLM ซ้ำ
///
/// Flow:
/// Face responds (Thai) → logExchange() → LLM extract → EnglishLogEntry
///                                      → store SharedPrefs
///                                      → return for Big Manager dispatch
class SecretChatService {
  static final SecretChatService _instance = SecretChatService._internal();
  factory SecretChatService() => _instance;
  SecretChatService._internal();

  static const String _storageKey = 'english_chat_log';
  static const int _maxEntries = 50;

  final List<EnglishLogEntry> _log = [];
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_storageKey) ?? [];
      _log.clear();
      for (final json in raw) {
        try {
          _log.add(EnglishLogEntry.fromJson(jsonDecode(json) as Map<String, dynamic>));
        } catch (_) {}
      }
      _isInitialized = true;
      debugPrint('🤫 SecretChatService: loaded ${_log.length} entries');
    } catch (e) {
      debugPrint('⚠️ SecretChatService init failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  // 🔬 PRE-CLASSIFY — runs BEFORE Face LLM (language-agnostic)
  // ──────────────────────────────────────────────────────────

  /// 🔬 Classify user message intent before Face responds
  ///
  /// ทำงานทุกภาษา — LLM แปล + classify ก่อนที่ Face จะตอบ
  /// Face จะได้รับ context hint เพื่อตอบได้ถูกต้อง
  /// Returns null ถ้า LLM ไม่พร้อมหรือ fail
  Future<PreClassifyResult?> preClassify(String userMessage) async {
    try {
      final llm = LLMProviderManager().provider;
      if (!llm.isInitialized) return null;

      final prompt = PromptBuilder.buildPreClassifyPrompt(userMessage: userMessage);
      final raw = await llm.generate(prompt);

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
      if (jsonMatch == null) return null;

      final json = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      final intent = (json['intent'] as String?) ?? 'chat';
      final summaryEn = (json['summary_en'] as String?) ?? userMessage.substring(0, userMessage.length.clamp(0, 60));
      final action = json['action'] as Map<String, dynamic>?;

      final result = PreClassifyResult(
        intent: intent,
        summaryEn: summaryEn,
        title: action?['title'] as String?,
        date: action?['date'] as String?,
        time: action?['time'] as String?,
      );
      debugPrint('🔬 PreClassify: intent=$intent summary="$summaryEn"');
      return result;
    } catch (e) {
      debugPrint('⚠️ PreClassify failed: $e');
      return null;
    }
  }

  /// แปล Thai exchange → EnglishLogEntry (async, ไม่ block UI)
  ///
  /// ถ้ามี [preClassifyResult] → ใช้ intent+summary จาก pre-classify (ไม่ต้อง LLM ซ้ำ)
  Future<EnglishLogEntry?> logExchange({
    required String userMessage,
    required String aiResponse,
    PreClassifyResult? preClassifyResult,
  }) async {
    await initialize();
    try {
      EnglishLogEntry? entry;

      // ถ้ามี preClassifyResult → ใช้ intent+summary โดยตรง (ไม่ต้อง LLM ซ้ำ)
      if (preClassifyResult != null) {
        entry = EnglishLogEntry(
          timestamp: DateTime.now(),
          summaryEn: preClassifyResult.summaryEn,
          intent: preClassifyResult.intent,
          // สกัด keywords จาก summaryEn เพื่อใช้ใน Tag Context Linker
          // รวม date/time จาก preClassify เพื่อให้ ManagerDispatch สร้าง event ได้ถูก
          tags: [
            if (preClassifyResult.title != null) preClassifyResult.title!,
            if (preClassifyResult.date != null) preClassifyResult.date!,
            if (preClassifyResult.time != null) preClassifyResult.time!,
            ..._summaryToKeywords(preClassifyResult.summaryEn),
          ],
          location: _extractLocation(preClassifyResult.summaryEn),
          mood: null,
        );
        debugPrint('🤫 Secret Chat (from preClassify): ${entry.summaryEn}');
      } else {
        // ไม่มี preClassify → run LLM extraction ตามปกติ
        final llm = LLMProviderManager().provider;
        if (!llm.isInitialized) return null;

        final prompt = PromptBuilder.buildWorkerExtractPrompt(userMessage, aiResponse);
        final raw = await llm.generate(prompt);
        entry = _parseExtraction(raw, userMessage);
        if (entry == null) return null;
        debugPrint('🤫 Secret Chat logged: ${entry.summaryEn}');
      }

      _log.add(entry);
      if (_log.length > _maxEntries) _log.removeAt(0);
      await _persist();
      return entry;
    } catch (e) {
      debugPrint('⚠️ SecretChatService.logExchange failed: $e');
      return null;
    }
  }

  /// Parse extraction JSON จาก LLM (robust)
  ///
  /// Gemma 3 1B อาจมี text ก่อน/หลัง JSON — ใช้ regex หา {...} block
  EnglishLogEntry? _parseExtraction(String raw, String originalUserMsg) {
    // หา JSON block แรกใน response (รองรับ text ก่อนหน้า/code block)
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (jsonMatch != null) {
      try {
        final json = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final data = json['extracted_data'] as Map<String, dynamic>? ?? {};
        final tags = (data['tags'] as List<dynamic>?)
                ?.whereType<String>()
                .toList() ??
            [];
        final entities = (data['entities'] as List<dynamic>?)
                ?.whereType<String>()
                .toList() ??
            [];
        final summaryRaw = json['summary_en'];
        final summaryEn = summaryRaw is String && summaryRaw.trim().isNotEmpty
            ? summaryRaw.trim()
            : originalUserMsg.substring(0, originalUserMsg.length.clamp(0, 60));

        final moodRaw = data['mood'];
        return EnglishLogEntry(
          timestamp: DateTime.now(),
          summaryEn: summaryEn,
          intent: (json['intent'] as String?) ?? 'chat',
          tags: [...tags, ...entities],
          location: data['location'] is String ? data['location'] as String : null,
          mood: moodRaw is num ? moodRaw.toInt() : null,
        );
      } catch (e) {
        debugPrint('⚠️ Secret Chat: JSON decode failed: $e');
      }
    }

    // Fallback: ไม่มี JSON เลย → log ภาษาไทยดิบแทน
    debugPrint('⚠️ Secret Chat: no JSON found, using raw fallback');
    return EnglishLogEntry(
      timestamp: DateTime.now(),
      summaryEn: originalUserMsg.substring(0, originalUserMsg.length.clamp(0, 80)),
      intent: 'chat',
      tags: [],
    );
  }

  /// สกัด keywords จาก English summary สำหรับ Tag Context Linker
  static List<String> _summaryToKeywords(String summary) {
    const stop = {
      'the', 'a', 'an', 'is', 'at', 'to', 'for', 'with', 'and', 'or',
      'in', 'of', 'i', 'my', 'me', 'was', 'went', 'had', 'have', 'user',
      'about', 'that', 'this', 'wants', 'will', 'has', 'be', 'are', 'it',
    };
    return summary
        .toLowerCase()
        .split(RegExp(r'[\s,\.\!\?\-\+]+'))
        .where((w) => w.length > 2 && !stop.contains(w))
        .toSet()
        .take(4)
        .toList();
  }

  /// ดึง location จาก summaryEn pattern เช่น "at X", "@ X"
  static String? _extractLocation(String summary) {
    final match = RegExp(
      r'\bat ([a-zA-Z][a-zA-Z\s]{2,30})(?:\s+with|\s+\d|$)',
      caseSensitive: false,
    ).firstMatch(summary);
    return match?.group(1)?.trim();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _log.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_storageKey, encoded);
    } catch (e) {
      debugPrint('⚠️ SecretChatService persist failed: $e');
    }
  }

  /// ดึง recent log สำหรับ ManagerSummaryStrategy
  List<EnglishLogEntry> getRecentLog({int limit = 20}) {
    return _log.reversed.take(limit).toList();
  }

  /// 🗑️ Clear all logs (in-memory + SharedPreferences)
  Future<void> clearAll() async {
    _log.clear();
    _isInitialized = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('⚠️ SecretChatService clearAll failed: $e');
    }
  }
}

// ──────────────────────────────────────────────────────────────────
// 🔬 Pre-Classify Result
// ──────────────────────────────────────────────────────────────────

/// ผลจาก preClassify() — intent จาก user message ก่อน Face ตอบ
class PreClassifyResult {
  final String intent;      // schedule | remind | search | log | chat
  final String summaryEn;   // English summary สำหรับ lean context
  final String? title;      // สำหรับ schedule/remind
  final String? date;       // YYYY-MM-DD
  final String? time;       // HH:MM

  const PreClassifyResult({
    required this.intent,
    required this.summaryEn,
    this.title,
    this.date,
    this.time,
  });

  /// Context hint ที่ Face LLM จะได้รับ เพื่อตอบให้ถูกต้อง
  String get contextHint {
    switch (intent) {
      case 'schedule':
        final parts = [
          if (title != null) title!,
          if (date != null) date!,
          if (time != null) time!,
        ].join(',');
        return '[INTENT:SCHEDULE:$parts]';
      case 'remind':
        return '[INTENT:REMIND:${title ?? ""}]';
      case 'search':
        return '[INTENT:SEARCH]';
      default:
        return ''; // log/chat ไม่ต้อง hint
    }
  }
}

/// 📝 English log entry (1 exchange = 1 entry)
class EnglishLogEntry {
  final DateTime timestamp;
  final String summaryEn;
  final String intent; // log | schedule | query | chat
  final List<String> tags;
  final String? location;
  final int? mood;

  EnglishLogEntry({
    required this.timestamp,
    required this.summaryEn,
    required this.intent,
    required this.tags,
    this.location,
    this.mood,
  });

  factory EnglishLogEntry.fromJson(Map<String, dynamic> json) => EnglishLogEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        summaryEn: json['summaryEn'] as String,
        intent: json['intent'] as String,
        tags: List<String>.from(json['tags'] as List<dynamic>? ?? []),
        location: json['location'] as String?,
        mood: json['mood'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'summaryEn': summaryEn,
        'intent': intent,
        'tags': tags,
        'location': location,
        'mood': mood,
      };
}
