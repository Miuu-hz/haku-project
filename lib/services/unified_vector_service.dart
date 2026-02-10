import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/correlation_models.dart';
import '../models/entry.dart';
import 'database_helper.dart';

/// 🔍 Unified Vector Service - รวม Vector Search ทุกประเภท
///
/// รองรับทั้ง:
/// - Entry (บันทึกประจำวัน)
/// - Facts (ข้อมูลที่เรียนรู้)
/// - Knowledge (ความรู้ทั่วไป)
///
/// ใช้ TF-IDF like embedding + Cosine Similarity

class UnifiedVectorService {
  static final UnifiedVectorService _instance = UnifiedVectorService._internal();
  factory UnifiedVectorService() => _instance;
  UnifiedVectorService._internal();

  static const String _storageKey = 'unified_vectors';
  static const String _entryVectorsTable = 'entry_vectors';

  // In-memory vectors (for facts/knowledge)
  final List<VectorItem> _items = [];
  bool _isInitialized = false;

  // SQLite database for entry vectors (hybrid search)
  Database? _entryDb;

  // Vector dimension
  static const int _vocabSize = 2000;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadFromStorage();
    await _initEntryDatabase();
    _isInitialized = true;
    debugPrint('✅ Unified Vector Service initialized: ${_items.length} facts, ${_entryDb != null ? 'SQLite ready' : 'no DB'}');
  }

  /// 🗄️ Initialize SQLite database for entry vectors
  Future<void> _initEntryDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      _entryDb = await openDatabase(
        join(dbPath, 'haku_entry_vectors.db'),
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $_entryVectorsTable (
              entry_id INTEGER PRIMARY KEY,
              embedding BLOB NOT NULL,
              content_hash TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_created_at ON $_entryVectorsTable(created_at)
          ''');
        },
      );
    } catch (e) {
      debugPrint('⚠️ Error initializing entry DB: $e');
    }
  }

  // ============================================================
  // 📥 STORAGE
  // ============================================================

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_storageKey);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _items.clear();
        _items.addAll(list.map((e) => VectorItem.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('⚠️ Error loading vectors: $e');
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only save non-Entry items (Entries are in SQLite)
      final toSave = _items.where((i) => i.type != VectorType.entry).toList();
      await prefs.setString(
        _storageKey,
        jsonEncode(toSave.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving vectors: $e');
    }
  }

  // ============================================================
  // ➕ ADD ITEMS
  // ============================================================

  /// ➕ Index Entry in memory (from diary)
  void indexEntryInMemory(Entry entry) {
    // Remove old if exists
    _items.removeWhere((i) => i.type == VectorType.entry && i.sourceId == entry.id?.toString());

    final text = '${entry.content} ${entry.tags.join(' ')} ${entry.locationName ?? ''}';
    final vector = _createEmbedding(text);

    _items.add(VectorItem(
      id: 'entry_${entry.id}',
      type: VectorType.entry,
      content: entry.content,
      vector: vector,
      sourceId: entry.id?.toString(),
      metadata: {
        'mood': entry.mood,
        'location': entry.locationName,
        'tags': entry.tags,
        'createdAt': entry.createdAt.toIso8601String(),
      },
      createdAt: entry.createdAt,
    ));
  }

  /// ➕ Index multiple entries in memory
  void indexEntriesInMemory(List<Entry> entries) {
    for (final entry in entries) {
      indexEntryInMemory(entry);
    }
    debugPrint('✅ Indexed ${entries.length} entries in memory');
  }

  /// ➕ Add Fact
  Future<String> addFact({
    required String category,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    await initialize();

    final id = 'fact_${DateTime.now().millisecondsSinceEpoch}';
    final vector = _createEmbedding(content);

    _items.add(VectorItem(
      id: id,
      type: VectorType.fact,
      content: content,
      vector: vector,
      metadata: {
        'category': category,
        ...?metadata,
      },
      createdAt: DateTime.now(),
    ));

    await _saveToStorage();
    debugPrint('📝 Added fact: $category - $content');
    return id;
  }

  /// ➕ Add or update Fact by key
  Future<void> upsertFact({
    required String category,
    required String key,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    await initialize();

    final existingIndex = _items.indexWhere((i) =>
        i.type == VectorType.fact &&
        i.metadata?['category'] == category &&
        i.metadata?['key'] == key);

    if (existingIndex >= 0) {
      // Update existing
      final existing = _items[existingIndex];
      _items[existingIndex] = VectorItem(
        id: existing.id,
        type: VectorType.fact,
        content: content,
        vector: _createEmbedding(content),
        metadata: {
          ...?existing.metadata,
          ...?metadata,
          'category': category,
          'key': key,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        createdAt: existing.createdAt,
      );
    } else {
      await addFact(
        category: category,
        content: content,
        metadata: {
          ...?metadata,
          'key': key,
        },
      );
    }

    await _saveToStorage();
  }

  /// ➕ Add Knowledge
  Future<String> addKnowledge({
    required String topic,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    await initialize();

    final id = 'knowledge_${DateTime.now().millisecondsSinceEpoch}';
    final vector = _createEmbedding(content);

    _items.add(VectorItem(
      id: id,
      type: VectorType.knowledge,
      content: content,
      vector: vector,
      metadata: {
        'topic': topic,
        ...?metadata,
      },
      createdAt: DateTime.now(),
    ));

    await _saveToStorage();
    debugPrint('📚 Added knowledge: $topic');
    return id;
  }

  /// ➕ Add Insight (Correlation)
  /// 
  /// เก็บ insights จากการวิเคราะห์ correlation
  Future<String> addInsight({
    required String content,
    required EntityType entityAType,
    required String entityAValue,
    required EntityType entityBType,
    required String entityBValue,
    required double correlation,
    required double confidence,
    required int sampleSize,
    Map<String, dynamic>? metadata,
  }) async {
    await initialize();

    final id = 'insight_${DateTime.now().millisecondsSinceEpoch}';
    final vector = _createEmbedding(content);

    _items.add(VectorItem(
      id: id,
      type: VectorType.insight,
      content: content,
      vector: vector,
      metadata: {
        'entityAType': entityAType.name,
        'entityAValue': entityAValue,
        'entityBType': entityBType.name,
        'entityBValue': entityBValue,
        'correlation': correlation,
        'confidence': confidence,
        'sampleSize': sampleSize,
        'discoveredAt': DateTime.now().toIso8601String(),
        ...?metadata,
      },
      createdAt: DateTime.now(),
    ));

    await _saveToStorage();
    debugPrint('🔮 Added insight: $entityAValue ↔ $entityBValue (${correlation.toStringAsFixed(2)})');
    return id;
  }

  /// 🔍 Search Insights only
  List<SearchResult> searchInsights(String query, {int limit = 10}) {
    return search(query, limit: limit, type: VectorType.insight);
  }

  /// 📊 Get all insights
  List<VectorItem> get insights => getByType(VectorType.insight);

  /// 🧹 Clear old insights (keep last N days)
  Future<int> clearOldInsights({int keepDays = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: keepDays));
    final toRemove = _items.where((i) =>
        i.type == VectorType.insight &&
        i.createdAt.isBefore(cutoff)).toList();

    for (final item in toRemove) {
      _items.removeWhere((i) => i.id == item.id);
    }

    if (toRemove.isNotEmpty) {
      await _saveToStorage();
      debugPrint('🧹 Cleared ${toRemove.length} old insights');
    }

    return toRemove.length;
  }

  // ============================================================
  // 🔍 SEARCH
  // ============================================================

  /// 🔍 Search all types
  List<SearchResult> search(
    String query, {
    int limit = 5,
    VectorType? type,
    String? category,
    double minScore = 0.1,
  }) {
    if (_items.isEmpty) return [];

    final queryVector = _createEmbedding(query);

    var items = _items;

    // Filter by type
    if (type != null) {
      items = items.where((i) => i.type == type).toList();
    }

    // Filter by category (for facts)
    if (category != null) {
      items = items.where((i) => i.metadata?['category'] == category).toList();
    }

    // Calculate similarity
    final results = items.map((i) {
      final similarity = _cosineSimilarity(queryVector, i.vector);
      return SearchResult(item: i, score: similarity);
    }).where((r) => r.score >= minScore).toList();

    // Sort by score
    results.sort((a, b) => b.score.compareTo(a.score));

    return results.take(limit).toList();
  }

  /// 🔍 Search Entries in memory only
  List<SearchResult> searchEntriesInMemory(String query, {int limit = 5}) {
    return search(query, limit: limit, type: VectorType.entry);
  }

  /// 🔍 Search Facts only
  List<SearchResult> searchFacts(String query, {int limit = 5, String? category}) {
    return search(query, limit: limit, type: VectorType.fact, category: category);
  }

  /// 🔍 Search for AI context
  String searchForContext(String query, {int limit = 3}) {
    final results = search(query, limit: limit);
    if (results.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('[Related]');

    for (final r in results) {
      final prefix = switch (r.item.type) {
        VectorType.entry => '📝',
        VectorType.fact => '💡',
        VectorType.knowledge => '📚',
        VectorType.insight => '🔮',
      };
      // Truncate content
      final content = r.item.content.length > 100
          ? '${r.item.content.substring(0, 100)}...'
          : r.item.content;
      buffer.writeln('$prefix $content');
    }

    return buffer.toString();
  }

  // ============================================================
  // 📝 ENTRY METHODS (SQLite-based for better performance)
  // ============================================================

  /// 📝 Index entry in SQLite (for RAG)
  Future<void> indexEntry(Entry entry) async {
    if (_entryDb == null) return;
    
    final text = '${entry.content} ${entry.tags.join(' ')} ${entry.locationName ?? ''}';
    final vector = _createEmbedding(text);
    final bytes = _vectorToBytes(vector);
    final contentHash = _hashContent(text);
    
    await _entryDb!.insert(
      _entryVectorsTable,
      {
        'entry_id': entry.id,
        'embedding': bytes,
        'content_hash': contentHash,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    // Also index in memory for unified search
    indexEntryInMemory(entry);
    debugPrint('✅ Indexed entry ${entry.id} in SQLite and memory');
  }

  /// 📝 Index multiple entries
  Future<void> indexEntries(List<Entry> entries) async {
    for (final entry in entries) {
      await indexEntry(entry);
    }
    debugPrint('✅ Indexed ${entries.length} entries');
  }

  /// 🔍 Search entries in SQLite with cosine similarity
  Future<List<SearchResultWithEntry>> searchEntriesInDatabase(String query, {int limit = 5}) async {
    if (_entryDb == null) {
      // Fallback to in-memory search
      final results = search(query, limit: limit, type: VectorType.entry);
      return results.map((r) {
        final entryId = int.tryParse(r.item.sourceId ?? '');
        return SearchResultWithEntry(
          entry: Entry(
            id: entryId,
            content: r.item.content,
            createdAt: r.item.createdAt,
          ),
          score: r.score,
        );
      }).toList();
    }
    
    final rows = await _entryDb!.query(_entryVectorsTable);
    if (rows.isEmpty) return [];
    
    final queryVector = _createEmbedding(query);
    final results = <_EntrySearchResult>[];
    
    for (final row in rows) {
      final entryId = row['entry_id'] as int;
      final bytes = row['embedding'] as List<int>;
      final vector = _bytesToVector(bytes);
      final similarity = _cosineSimilarity(queryVector, vector);
      results.add(_EntrySearchResult(entryId: entryId, score: similarity));
    }
    
    results.sort((a, b) => b.score.compareTo(a.score));
    
    final topResults = results.take(limit).toList();
    final entriesWithScore = <SearchResultWithEntry>[];
    
    for (final result in topResults) {
      final entry = await DatabaseHelper.instance.getEntryById(result.entryId);
      if (entry != null) {
        entriesWithScore.add(SearchResultWithEntry(entry: entry, score: result.score));
      }
    }
    
    return entriesWithScore;
  }

  /// 🧠 Build context for LLM (RAG)
  Future<String> buildContext(String query, {int topK = 3}) async {
    final results = await searchEntriesInDatabase(query, limit: topK);
    
    if (results.isEmpty) {
      return 'ไม่พบบันทึกที่เกี่ยวข้อง';
    }

    final buffer = StringBuffer();
    buffer.writeln('ข้อมูลบันทึกที่เกี่ยวข้อง:');
    buffer.writeln();

    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      buffer.writeln('[${i + 1}] ${result.entry.createdAt}: ${result.entry.content}');
      if (result.entry.locationName != null) {
        buffer.writeln('    ที่: ${result.entry.locationName}');
      }
      if (result.entry.mood != null) {
        buffer.writeln('    อารมณ์: ${result.entry.mood}/5');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// 🗑️ Remove entry from index
  Future<void> removeEntry(int entryId) async {
    if (_entryDb == null) return;
    await _entryDb!.delete(
      _entryVectorsTable,
      where: 'entry_id = ?',
      whereArgs: [entryId],
    );
    deleteEntry(entryId);
  }

  /// 🔄 Reindex all entries
  Future<void> reindexAllEntries() async {
    if (_entryDb == null) return;
    await _entryDb!.delete(_entryVectorsTable);
    final entries = await DatabaseHelper.instance.getAllEntries();
    await indexEntries(entries);
  }

  // ============================================================
  // 🔧 HELPERS
  // ============================================================

  List<int> _vectorToBytes(List<double> vector) {
    final buffer = ByteData(vector.length * 4);
    for (var i = 0; i < vector.length; i++) {
      buffer.setFloat32(i * 4, vector[i], Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  List<double> _bytesToVector(List<int> bytes) {
    final buffer = ByteData.sublistView(Uint8List.fromList(bytes));
    final vector = <double>[];
    for (var i = 0; i < bytes.length; i += 4) {
      vector.add(buffer.getFloat32(i, Endian.little));
    }
    return vector;
  }

  String _hashContent(String text) {
    var hash = 0;
    for (var i = 0; i < text.length; i++) {
      hash = ((hash << 5) - hash) + text.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.toString();
  }

  // ============================================================
  // 📋 GET ITEMS
  // ============================================================

  /// Get by type
  List<VectorItem> getByType(VectorType type) {
    return _items.where((i) => i.type == type).toList();
  }

  /// Get by category
  List<VectorItem> getByCategory(String category) {
    return _items.where((i) => i.metadata?['category'] == category).toList();
  }

  /// Get all facts
  List<VectorItem> get facts => getByType(VectorType.fact);

  /// Get all knowledge
  List<VectorItem> get knowledge => getByType(VectorType.knowledge);

  /// Total count
  int get count => _items.length;

  /// Count by type
  Map<VectorType, int> get countByType {
    final counts = <VectorType, int>{};
    for (final type in VectorType.values) {
      counts[type] = _items.where((i) => i.type == type).length;
    }
    return counts;
  }

  /// Get stats for debugging
  Map<String, dynamic> getStats() {
    return {
      'storedVectors': _items.length,
      'memoryMB': (_items.length * _vocabSize * 8) / 1024 / 1024,
    };
  }

  // ============================================================
  // 🗑️ DELETE
  // ============================================================

  /// Delete by ID
  Future<void> deleteById(String id) async {
    _items.removeWhere((i) => i.id == id);
    await _saveToStorage();
  }

  /// Delete Entry by Entry ID
  void deleteEntry(int entryId) {
    _items.removeWhere((i) => i.type == VectorType.entry && i.sourceId == entryId.toString());
  }

  /// Delete by category
  Future<void> deleteByCategory(String category) async {
    _items.removeWhere((i) => i.metadata?['category'] == category);
    await _saveToStorage();
  }

  /// Clear all
  Future<void> clearAll() async {
    _items.clear();
    await _saveToStorage();
  }

  /// Clear only facts and knowledge (keep entries in sync with SQLite)
  Future<void> clearFactsAndKnowledge() async {
    _items.removeWhere((i) => i.type != VectorType.entry);
    await _saveToStorage();
  }

  // ============================================================
  // 🧠 EMBEDDING
  // ============================================================

  List<double> _createEmbedding(String text) {
    final normalized = text.toLowerCase()
        .replaceAll(RegExp(r'[^\u0E00-\u0E7Fa-z0-9\s]'), ' ')
        .trim();

    final words = normalized.split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toList();

    final vector = List<double>.filled(_vocabSize, 0.0);

    // Term frequency with position boost
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final hash = _hashString(word) % _vocabSize;
      // Earlier words get slightly more weight
      final positionBoost = 1.0 + (0.1 * (words.length - i) / words.length);
      vector[hash] += positionBoost;
    }

    // Reduce weight of stop words
    final stopWords = _getStopWords();
    for (final word in words) {
      if (stopWords.contains(word)) {
        final hash = _hashString(word) % _vocabSize;
        vector[hash] *= 0.1;
      }
    }

    // L2 normalize
    final magnitude = sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    if (magnitude > 0) {
      for (var i = 0; i < vector.length; i++) {
        vector[i] /= magnitude;
      }
    }

    return vector;
  }

  int _hashString(String s) {
    var hash = 0;
    for (var i = 0; i < s.length; i++) {
      hash = ((hash << 5) - hash) + s.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.abs();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    var dotProduct = 0.0;
    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
    }
    return dotProduct;
  }

  Set<String> _getStopWords() => {
    // Thai
    'จะ', 'ใน', 'ที่', 'ของ', 'และ', 'เป็น', 'ได้', 'ก็', 'ให้',
    'ว่า', 'มี', 'แต่', 'หรือ', 'ถ้า', 'จาก', 'กับ', 'โดย', 'นี้',
    'แล้ว', 'ไป', 'มา', 'อยู่', 'คือ', 'เรา', 'ผม', 'ฉัน', 'คุณ',
    'ครับ', 'ค่ะ', 'นะ', 'จ้า', 'เลย', 'มาก', 'ดี', 'สุด',
    // English
    'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to',
    'is', 'are', 'was', 'were', 'be', 'been', 'have', 'has', 'had',
    'i', 'you', 'he', 'she', 'it', 'we', 'they', 'this', 'that',
  };
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// Vector item type
enum VectorType {
  entry,      // Diary entry
  fact,       // Learned fact (likes, dislikes, etc.)
  knowledge,  // General knowledge
  insight,    // 🔮 Correlation insights
}

/// Vector Item
class VectorItem {
  final String id;
  final VectorType type;
  final String content;
  final List<double> vector;
  final String? sourceId;         // For entries: Entry.id
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  VectorItem({
    required this.id,
    required this.type,
    required this.content,
    required this.vector,
    this.sourceId,
    this.metadata,
    required this.createdAt,
  });

  factory VectorItem.fromJson(Map<String, dynamic> json) => VectorItem(
    id: json['id'] as String,
    type: VectorType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => VectorType.fact,
    ),
    content: json['content'] as String,
    vector: (json['vector'] as List<dynamic>).cast<double>(),
    sourceId: json['sourceId'] as String?,
    metadata: json['metadata'] as Map<String, dynamic>?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'content': content,
    'vector': vector,
    'sourceId': sourceId,
    'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// Search Result
class SearchResult {
  final VectorItem item;
  final double score;

  SearchResult({required this.item, required this.score});

  /// Get as Entry (if type is entry)
  Entry? toEntry() {
    if (item.type != VectorType.entry) return null;

    final meta = item.metadata;
    return Entry(
      id: int.tryParse(item.sourceId ?? ''),
      content: item.content,
      createdAt: item.createdAt,
      mood: meta?['mood'] as int?,
      locationName: meta?['location'] as String?,
      tags: (meta?['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

/// Search Result with Entry (for RAG)
class SearchResultWithEntry {
  final Entry entry;
  final double score;

  SearchResultWithEntry({required this.entry, required this.score});
}

/// Internal helper for entry search
class _EntrySearchResult {
  final int entryId;
  final double score;

  _EntrySearchResult({required this.entryId, required this.score});
}
