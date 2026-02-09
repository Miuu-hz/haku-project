import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 📦 Simple Vector Service - RAG สำหรับ Facts และ Knowledge
///
/// เก็บข้อมูลแบบ vector search ได้
/// ใช้สำหรับ:
/// - สถานที่โปรด
/// - ข้อมูลสุขภาพ
/// - ความรู้ที่เรียนรู้จากการสนทนา

class SimpleVectorService {
  static final SimpleVectorService _instance = SimpleVectorService._internal();
  factory SimpleVectorService() => _instance;
  SimpleVectorService._internal();

  static const String _entriesKey = 'vector_entries';

  final List<VectorEntry> _entries = [];
  bool _isInitialized = false;

  // Vector dimension (hash-based vocabulary)
  static const int _vocabSize = 1000;

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadFromStorage();
    _isInitialized = true;
    debugPrint('✅ Simple Vector Service initialized: ${_entries.length} entries');
  }

  /// 📥 Load from storage
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_entriesKey);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _entries.clear();
        _entries.addAll(list.map((e) => VectorEntry.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('⚠️ Error loading vector entries: $e');
    }
  }

  /// 💾 Save to storage
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _entriesKey,
        jsonEncode(_entries.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving vector entries: $e');
    }
  }

  // ============================================================
  // ➕ ADD ENTRIES
  // ============================================================

  /// ➕ Add entry
  Future<String> addEntry({
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    await initialize();

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final vector = _createEmbedding(content);

    final entry = VectorEntry(
      id: id,
      content: content,
      vector: vector,
      metadata: metadata ?? {},
      createdAt: DateTime.now(),
    );

    _entries.add(entry);
    await _saveToStorage();

    debugPrint('📦 Vector entry added: $content');
    return id;
  }

  /// ➕ Add or update entry by category
  Future<void> upsertByCategory({
    required String category,
    required String key,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    await initialize();

    // Check if exists
    final existingIndex = _entries.indexWhere((e) =>
        e.metadata['category'] == category &&
        e.metadata['key'] == key);

    if (existingIndex >= 0) {
      // Update existing
      final existing = _entries[existingIndex];
      _entries[existingIndex] = VectorEntry(
        id: existing.id,
        content: content,
        vector: _createEmbedding(content),
        metadata: {
          ...existing.metadata,
          ...?metadata,
          'category': category,
          'key': key,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        createdAt: existing.createdAt,
      );
    } else {
      // Add new
      await addEntry(
        content: content,
        metadata: {
          ...?metadata,
          'category': category,
          'key': key,
        },
      );
    }

    await _saveToStorage();
  }

  // ============================================================
  // 🔍 SEARCH
  // ============================================================

  /// 🔍 Search by query
  List<VectorSearchResult> search(String query, {int limit = 5, String? category}) {
    if (_entries.isEmpty) return [];

    final queryVector = _createEmbedding(query);

    var entries = _entries;
    if (category != null) {
      entries = _entries.where((e) => e.metadata['category'] == category).toList();
    }

    final results = entries.map((e) {
      final similarity = _cosineSimilarity(queryVector, e.vector);
      return VectorSearchResult(entry: e, score: similarity);
    }).toList();

    results.sort((a, b) => b.score.compareTo(a.score));

    return results.take(limit).toList();
  }

  /// 🔍 Get by category
  List<VectorEntry> getByCategory(String category) {
    return _entries.where((e) => e.metadata['category'] == category).toList();
  }

  /// 🔍 Get all entries
  List<VectorEntry> getAll() => List.unmodifiable(_entries);

  // ============================================================
  // 🧠 EMBEDDING
  // ============================================================

  /// 🧠 Create embedding (TF-IDF like)
  List<double> _createEmbedding(String text) {
    final normalized = text.toLowerCase()
        .replaceAll(RegExp(r'[^\u0E00-\u0E7Fa-z0-9\s]'), ' ')
        .trim();

    final words = normalized.split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toList();

    final vector = List<double>.filled(_vocabSize, 0.0);

    // Term frequency
    for (final word in words) {
      final hash = _hashString(word) % _vocabSize;
      vector[hash] += 1.0;
    }

    // Normalize (L2)
    final magnitude = sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    if (magnitude > 0) {
      for (var i = 0; i < vector.length; i++) {
        vector[i] /= magnitude;
      }
    }

    return vector;
  }

  /// Hash string
  int _hashString(String s) {
    var hash = 0;
    for (var i = 0; i < s.length; i++) {
      hash = ((hash << 5) - hash) + s.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.abs();
  }

  /// Cosine similarity
  double _cosineSimilarity(List<double> a, List<double> b) {
    var dotProduct = 0.0;
    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
    }
    return dotProduct;
  }

  // ============================================================
  // 🗑️ DELETE
  // ============================================================

  /// Delete by ID
  Future<void> deleteById(String id) async {
    _entries.removeWhere((e) => e.id == id);
    await _saveToStorage();
  }

  /// Delete by category
  Future<void> deleteByCategory(String category) async {
    _entries.removeWhere((e) => e.metadata['category'] == category);
    await _saveToStorage();
  }

  /// Clear all
  Future<void> clearAll() async {
    _entries.clear();
    await _saveToStorage();
  }

  /// Entry count
  int get count => _entries.length;
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// Vector Entry
class VectorEntry {
  final String id;
  final String content;
  final List<double> vector;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  VectorEntry({
    required this.id,
    required this.content,
    required this.vector,
    required this.metadata,
    required this.createdAt,
  });

  factory VectorEntry.fromJson(Map<String, dynamic> json) => VectorEntry(
    id: json['id'] as String,
    content: json['content'] as String,
    vector: (json['vector'] as List<dynamic>).cast<double>(),
    metadata: Map<String, dynamic>.from(json['metadata'] as Map),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'vector': vector,
    'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// Search result
class VectorSearchResult {
  final VectorEntry entry;
  final double score;

  VectorSearchResult({required this.entry, required this.score});
}
