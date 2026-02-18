import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/entry.dart';
import '../llm_provider_manager.dart';
import '../prompt_builder.dart';

/// 🌐 Translator Worker - แปล diary entries ไทย→อังกฤษ (background)
///
/// ทำงานตอนชาร์จ:
/// - แปล entries ที่ยังไม่ได้แปล
/// - เก็บ English summary ไว้ใน SharedPreferences
/// - ประหยัด token (~83% ต่อ entry)
/// - ช่วยให้ vector search ทำงานดีขึ้น (English มี word boundaries)
///
/// Limit: 20 entries ต่อ charging session

class TranslatorWorker {
  static final TranslatorWorker _instance = TranslatorWorker._internal();
  factory TranslatorWorker() => _instance;
  TranslatorWorker._internal();

  static const String _storageKey = 'entry_translations';
  static const int _batchLimit = 20;

  final Map<int, EntryTranslation> _translations = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  int get translatedCount => _translations.length;

  /// 🚀 Initialize — load cached translations
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadFromStorage();
    _isInitialized = true;
    debugPrint('✅ TranslatorWorker initialized: ${_translations.length} translations');
  }

  /// 🔍 Get translation for an entry (null if not yet translated)
  EntryTranslation? getTranslation(int entryId) => _translations[entryId];

  /// 🌐 Translate a single entry Thai→English
  Future<EntryTranslation?> translateEntry(Entry entry) async {
    if (entry.id == null || entry.content.isEmpty) return null;

    final llm = LLMProviderManager().provider;
    if (!llm.isInitialized) {
      debugPrint('⚠️ LLM not initialized, skipping translation');
      return null;
    }

    try {
      final prompt = PromptBuilder.buildTranslateEntryPrompt(entry.content);
      final englishSummary = await llm.generate(prompt);

      if (englishSummary.isEmpty) return null;

      final translation = EntryTranslation(
        entryId: entry.id!,
        englishSummary: englishSummary.trim(),
        contentHash: entry.content.hashCode.toString(),
        translatedAt: DateTime.now(),
      );

      _translations[entry.id!] = translation;
      return translation;
    } catch (e) {
      debugPrint('⚠️ Translation failed for entry ${entry.id}: $e');
      return null;
    }
  }

  /// 📦 Batch translate untranslated entries (background task)
  ///
  /// Returns number of entries translated this session.
  /// Processes oldest-first, skips already translated (with same content hash).
  Future<int> translatePending(List<Entry> entries) async {
    final llm = LLMProviderManager().provider;
    if (!llm.isInitialized) {
      debugPrint('⚠️ LLM not initialized, skipping batch translation');
      return 0;
    }

    // Filter: untranslated or content changed
    final pending = entries.where((e) {
      if (e.id == null) return false;
      final existing = _translations[e.id];
      if (existing == null) return true; // never translated
      return existing.contentHash != e.content.hashCode.toString(); // content changed
    }).toList();

    // Sort oldest first
    pending.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Limit per session
    final batch = pending.take(_batchLimit).toList();

    if (batch.isEmpty) {
      debugPrint('✅ All entries already translated');
      return 0;
    }

    debugPrint('🌐 Translating ${batch.length} entries...');
    var translated = 0;

    for (final entry in batch) {
      final result = await translateEntry(entry);
      if (result != null) {
        translated++;
      }
    }

    await _saveToStorage();
    debugPrint('✅ Translated $translated/${batch.length} entries');
    return translated;
  }

  // ============================================================
  // 💾 STORAGE
  // ============================================================

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_storageKey);

      if (json != null) {
        final Map<String, dynamic> map =
            jsonDecode(json) as Map<String, dynamic>;
        _translations.clear();
        for (final entry in map.entries) {
          final id = int.tryParse(entry.key);
          if (id != null) {
            _translations[id] = EntryTranslation.fromJson(
              entry.value as Map<String, dynamic>,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error loading translations: $e');
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      for (final entry in _translations.entries) {
        map[entry.key.toString()] = entry.value.toJson();
      }
      await prefs.setString(_storageKey, jsonEncode(map));
    } catch (e) {
      debugPrint('⚠️ Error saving translations: $e');
    }
  }

  /// 🗑️ Clear all translations
  Future<void> clearAll() async {
    _translations.clear();
    await _saveToStorage();
  }
}

/// 📝 Entry Translation
class EntryTranslation {
  final int entryId;
  final String englishSummary;
  final String contentHash;
  final DateTime translatedAt;

  EntryTranslation({
    required this.entryId,
    required this.englishSummary,
    required this.contentHash,
    required this.translatedAt,
  });

  factory EntryTranslation.fromJson(Map<String, dynamic> json) =>
      EntryTranslation(
        entryId: json['entryId'] as int,
        englishSummary: json['englishSummary'] as String,
        contentHash: json['contentHash'] as String,
        translatedAt: DateTime.parse(json['translatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'englishSummary': englishSummary,
        'contentHash': contentHash,
        'translatedAt': translatedAt.toIso8601String(),
      };
}
