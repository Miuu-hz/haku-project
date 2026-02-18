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

  /// แปล Thai exchange → EnglishLogEntry (async, ไม่ block UI)
  Future<EnglishLogEntry?> logExchange({
    required String userMessage,
    required String aiResponse,
  }) async {
    await initialize();
    try {
      final llm = LLMProviderManager().provider;
      if (!llm.isInitialized) return null;

      final prompt = PromptBuilder.buildWorkerExtractPrompt(userMessage, aiResponse);
      final raw = await llm.generate(prompt);

      final entry = _parseExtraction(raw, userMessage);
      if (entry == null) return null;

      _log.add(entry);

      // เก็บแค่ _maxEntries ล่าสุด
      if (_log.length > _maxEntries) {
        _log.removeAt(0);
      }

      await _persist();
      debugPrint('🤫 Secret Chat logged: ${entry.summaryEn}');
      return entry;
    } catch (e) {
      debugPrint('⚠️ SecretChatService.logExchange failed: $e');
      return null;
    }
  }

  /// Parse extraction JSON จาก LLM (robust — fallback ถ้า JSON พัง)
  EnglishLogEntry? _parseExtraction(String raw, String originalUserMsg) {
    try {
      // ลบ markdown code block ถ้ามี
      var clean = raw.trim();
      if (clean.startsWith('```')) {
        clean = clean.replaceAll(RegExp(r'```[a-z]*\n?'), '').trim();
      }

      final json = jsonDecode(clean) as Map<String, dynamic>;
      final data = json['extracted_data'] as Map<String, dynamic>? ?? {};
      final tags = (data['tags'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [];
      final entities = (data['entities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      return EnglishLogEntry(
        timestamp: DateTime.now(),
        summaryEn: (json['summary_en'] as String?)?.trim() ?? '',
        intent: (json['intent'] as String?) ?? 'chat',
        tags: [...tags, ...entities],
        location: data['location'] as String?,
        mood: (data['mood'] as num?)?.toInt(),
      );
    } catch (_) {
      // Fallback: ถ้า JSON พัง เก็บเป็น plain log
      debugPrint('⚠️ Secret Chat: JSON parse failed, using fallback');
      return EnglishLogEntry(
        timestamp: DateTime.now(),
        summaryEn: raw.trim().substring(0, raw.trim().length.clamp(0, 100)),
        intent: 'chat',
        tags: [],
      );
    }
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
