import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/entry.dart';

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

  // In-memory vectors
  final List<VectorItem> _items = [];
  bool _isInitialized = false;

  // Vector dimension
  static const int _vocabSize = 2000;

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadFromStorage();
    _isInitialized = true;
    debugPrint('✅ Unified Vector Service initialized: ${_items.length} items');
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

  /// ➕ Index Entry (from diary)
  void indexEntry(Entry entry) {
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

  /// ➕ Index multiple entries
  void indexEntries(List<Entry> entries) {
    for (final entry in entries) {
      indexEntry(entry);
    }
    debugPrint('✅ Indexed ${entries.length} entries');
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

  /// 🔍 Search Entries only
  List<SearchResult> searchEntries(String query, {int limit = 5}) {
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

  /// 🧠 Create embedding (TF-IDF hash-based)
  List<double> _createEmbedding(String text) {
    final normalized = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    final tokens = normalized.split(RegExp(r'\s+'));

    final vector = List<double>.filled(_vocabSize, 0.0);

    // Term frequency with position boost
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final hash = _hashString(token) % _vocabSize;
      final positionBoost = 1.0 + (0.1 * (tokens.length - i) / tokens.length);
      vector[hash] += positionBoost;
    }

    // Reduce weight of English stop words
    final stopWords = _getStopWords();
    for (final token in tokens) {
      if (stopWords.contains(token)) {
        final hash = _hashString(token) % _vocabSize;
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
