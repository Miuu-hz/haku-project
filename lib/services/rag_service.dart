import 'package:flutter/foundation.dart';

import '../models/entry.dart';
import 'database_helper.dart';
import 'hybrid_vector_search.dart';
import 'workers/translator_worker.dart';

// Re-export SearchResult ให้ไฟล์อื่นใช้งานได้
export 'hybrid_vector_search.dart' show SearchResult;

/// 🔍 RAG Service - Retrieval-Augmented Generation
///
/// ทำให้ AI ค้นหาบันทึกเก่าได้จาก "ความหมาย" ไม่ใช่แค่ keyword
///
/// Architecture:
/// 1. แปลงบันทึกทั้งหมดเป็น Vector (Embedding)
/// 2. เก็บใน SQLite ธรรมดา (BLOB) - ไม่ต้อง vec0 extension
/// 3. คำนวณ Cosine Similarity ใน Dart (รองรับ Isolate)
/// 4. เอาบันทึกที่เจอไปให้ LLM ตอบ

class RAGService {
  static final RAGService _instance = RAGService._internal();
  factory RAGService() => _instance;
  RAGService._internal();

  bool _isInitialized = false;

  // Hybrid Vector Search: เก็บใน SQLite ธรรมดา คำนวณใน Dart
  HybridVectorSearch? _vectorSearch;
  final TranslatorWorker _translatorWorker = TranslatorWorker();

  /// สถานะการ initialize
  bool get isInitialized => _isInitialized;
  bool get isUsingVectorSearch => _isInitialized;

  /// 🚀 เริ่มต้น RAG (Hybrid Vector Search)
  ///
  /// ใช้ SQLite ธรรมดาเก็บ vectors (BLOB) แทน vec0 extension
  /// คำนวณ Cosine Similarity ใน Dart + รองรับ Isolate
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // ใช้ HybridVectorSearch แทน sqlite-vec
      final vs = HybridVectorSearch();
      await vs.initialize();
      _vectorSearch = vs;

      // ถ้ายังไม่มีข้อมูล ให้โหลดจาก database
      final count = await vs.count;
      if (count == 0) {
        debugPrint('🔄 Initializing vector index from existing entries...');
        final entries = await DatabaseHelper.instance.getAllEntries();
        if (entries.isNotEmpty) {
          await vs.indexEntries(entries);
        }
      }

      _isInitialized = true;
      debugPrint('✅ RAG Service initialized (HybridVectorSearch, $count entries)');
      return true;

    } catch (e) {
      debugPrint('❌ RAG Service initialization failed: $e');
      _vectorSearch = null;
      return false;
    }
  }

  /// ➕ เพิ่ม/อัพเดท entry ใน Vector DB
  Future<void> indexEntry(Entry entry) async {
    if (!_isInitialized || _vectorSearch == null) return;
    await _vectorSearch!.indexEntry(entry);
  }

  /// ➕ เพิ่มหลาย entries พร้อมกัน (Batch)
  Future<void> indexEntries(List<Entry> entries) async {
    if (!_isInitialized || _vectorSearch == null) return;
    await _vectorSearch!.indexEntries(entries);
  }

  /// 🔍 ค้นหาบันทึกที่ใกล้เคียงกับคำถาม
  Future<List<SearchResultWithEntry>> search(String query, {int limit = 5, bool useIsolate = false}) async {
    if (!_isInitialized || _vectorSearch == null) {
      return _fallbackKeywordSearch(query, limit);
    }

    try {
      // ใช้ HybridVectorSearch (รองรับ Isolate เมื่อข้อมูลเยอะ)
      final results = await _vectorSearch!.search(query, limit: limit, useIsolate: useIsolate);

      // ดึง Entry จาก database ตาม entry_id
      final entriesWithScore = <SearchResultWithEntry>[];
      for (final result in results) {
        final entry = await DatabaseHelper.instance.getEntryById(result.entryId);
        if (entry != null) {
          entriesWithScore.add(SearchResultWithEntry(entry: entry, score: result.score));
        }
      }

      return entriesWithScore;
    } catch (e) {
      debugPrint('❌ Vector search failed: $e');
      return _fallbackKeywordSearch(query, limit);
    }
  }

  /// 🔍 Fallback: Keyword Search
  Future<List<SearchResultWithEntry>> _fallbackKeywordSearch(String query, int limit) async {
    final entries = await DatabaseHelper.instance.searchEntries(query);
    return entries
        .take(limit)
        .map((e) => SearchResultWithEntry(entry: e, score: 0.5))
        .toList();
  }

  /// 🧠 สร้าง Context สำหรับ LLM (Top K entries)
  ///
  /// ใช้ English translation เมื่อมี → ประหยัด token ~83%
  Future<String> buildContext(String query, {int topK = 3}) async {
    final results = await search(query, limit: topK);

    if (results.isEmpty) {
      return 'No related entries found';
    }

    await _translatorWorker.initialize();

    final buffer = StringBuffer();
    buffer.writeln('Related entries:');
    buffer.writeln();

    for (var i = 0; i < results.length; i++) {
      final result = results[i];

      // Prefer English translation (saves tokens in 2048 context window)
      final translation =
          _translatorWorker.getTranslation(result.entry.id ?? 0);
      final content = translation?.englishSummary ?? result.entry.content;

      buffer.writeln('[${i + 1}] ${result.entry.createdAt}: $content');
      if (result.entry.locationName != null) {
        buffer.writeln('    at: ${result.entry.locationName}');
      }
      if (result.entry.mood != null) {
        buffer.writeln('    mood: ${result.entry.mood}/5');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// 🗑️ ลบ entry ออกจาก index
  Future<void> removeEntry(int entryId) async {
    if (!_isInitialized || _vectorSearch == null) return;
    await _vectorSearch!.removeEntry(entryId);
  }

  /// 🔄 Reindex ทั้งหมด
  Future<void> reindexAll() async {
    if (!_isInitialized || _vectorSearch == null) return;
    await _vectorSearch!.reindexAll();
  }

  /// 🧹 Dispose
  Future<void> dispose() async {
    final vs = _vectorSearch;
    if (vs != null && vs.isInitialized) {
      await vs.dispose();
    }
    _vectorSearch = null;
    _isInitialized = false;
  }
}

/// 🔍 Search Result พร้อม Entry (สำหรับ RAGService)
class SearchResultWithEntry {
  final Entry entry;
  final double score; // 0.0 - 1.0 (1.0 = ตรงกันมาก)

  SearchResultWithEntry({required this.entry, required this.score});
}
