import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🧮 Vector Service - Simple Vec RAG
///
/// ใช้สำหรับ Semantic Search บน Topics
/// - แปลง Text เป็น Vector (TF-IDF style)
/// - คำนวณ Cosine Similarity
/// - ค้นหา Top-K ที่เกี่ยวข้องที่สุด
///
/// Note: นี่คือ Simple Implementation
/// สำหรับ Production ควรใช้ proper embedding model

class VectorService {
  static final VectorService _instance = VectorService._internal();
  factory VectorService() => _instance;
  VectorService._internal();

  static const String _vectorsKey = 'topic_vectors';
  static const String _vocabKey = 'vector_vocab';

  // Vocabulary (word -> index)
  Map<String, int> _vocabulary = {};
  int _vocabSize = 0;

  // Stored vectors (topicId -> vector)
  Map<String, List<double>> _vectors = {};

  bool _isInitialized = false;

  // Settings
  static const int maxVocabSize = 5000;
  static const int vectorDimension = 256; // Fixed dimension for consistency

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadVocabulary();
    await _loadVectors();

    _isInitialized = true;
    debugPrint('✅ Vector Service initialized');
    debugPrint('   - Vocabulary size: $_vocabSize');
    debugPrint('   - Stored vectors: ${_vectors.length}');
  }

  /// 📥 Load vocabulary
  Future<void> _loadVocabulary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_vocabKey);

      if (json != null) {
        _vocabulary = Map<String, int>.from(jsonDecode(json));
        _vocabSize = _vocabulary.length;
      }
    } catch (e) {
      debugPrint('⚠️ Error loading vocabulary: $e');
    }
  }

  /// 📥 Load vectors
  Future<void> _loadVectors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_vectorsKey);

      if (json != null) {
        final Map<String, dynamic> data = jsonDecode(json);
        _vectors = data.map((k, v) => MapEntry(k, List<double>.from(v)));
      }
    } catch (e) {
      debugPrint('⚠️ Error loading vectors: $e');
    }
  }

  /// 💾 Save data
  Future<void> _saveData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_vocabKey, jsonEncode(_vocabulary));
      await prefs.setString(_vectorsKey, jsonEncode(_vectors));
    } catch (e) {
      debugPrint('⚠️ Error saving vector data: $e');
    }
  }

  // ============================================================
  // 🔢 VECTORIZATION
  // ============================================================

  /// 🔢 Convert text to vector
  ///
  /// ใช้ TF-IDF style + hashing trick
  List<double> textToVector(String text) {
    final tokens = _tokenize(text);
    final vector = List<double>.filled(vectorDimension, 0);

    if (tokens.isEmpty) return vector;

    // Term frequency
    final tf = <String, int>{};
    for (final token in tokens) {
      tf[token] = (tf[token] ?? 0) + 1;
    }

    // Build vector using hash
    for (final entry in tf.entries) {
      final token = entry.key;
      final count = entry.value;

      // Get or create vocabulary index
      var idx = _vocabulary[token];
      if (idx == null) {
        if (_vocabSize < maxVocabSize) {
          idx = _vocabSize;
          _vocabulary[token] = idx;
          _vocabSize++;
        } else {
          // Use hash for OOV words
          idx = token.hashCode.abs() % vectorDimension;
        }
      }

      // Map to fixed dimension
      final vectorIdx = idx % vectorDimension;

      // TF-IDF style weighting
      final tfWeight = 1 + log(count);
      vector[vectorIdx] += tfWeight;
    }

    // Normalize
    return _normalize(vector);
  }

  /// 📝 Tokenize text
  List<String> _tokenize(String text) {
    // Thai word segmentation (simple)
    // For production, use proper Thai tokenizer like PyThaiNLP
    final stopWords = {
      'ครับ', 'ค่ะ', 'นะ', 'จ้า', 'ก็', 'แล้ว', 'ด้วย', 'ที่', 'ของ',
      'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'to', 'of',
    };

    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\u0E00-\u0E7Fa-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1 && !stopWords.contains(w))
        .toList();
  }

  /// 📐 Normalize vector (L2 norm)
  List<double> _normalize(List<double> vector) {
    var norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = sqrt(norm);

    if (norm == 0) return vector;

    return vector.map((v) => v / norm).toList();
  }

  // ============================================================
  // 🔍 SIMILARITY SEARCH
  // ============================================================

  /// 📊 Calculate cosine similarity
  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;

    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0) return 0;

    return dotProduct / denominator;
  }

  /// 🔍 Search similar topics
  ///
  /// Returns list of (topicId, score) sorted by score desc
  List<SearchResult> searchSimilar(String query, {int topK = 5}) {
    final queryVector = textToVector(query);
    final results = <SearchResult>[];

    for (final entry in _vectors.entries) {
      final score = cosineSimilarity(queryVector, entry.value);
      if (score > 0.1) {
        // Minimum threshold
        results.add(SearchResult(topicId: entry.key, score: score));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(topK).toList();
  }

  /// 🔍 Search with pre-computed vector
  List<SearchResult> searchWithVector(List<double> queryVector, {int topK = 5}) {
    final results = <SearchResult>[];

    for (final entry in _vectors.entries) {
      final score = cosineSimilarity(queryVector, entry.value);
      if (score > 0.1) {
        results.add(SearchResult(topicId: entry.key, score: score));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(topK).toList();
  }

  // ============================================================
  // 💾 STORAGE
  // ============================================================

  /// ➕ Store topic vector
  Future<void> storeTopicVector(String topicId, String content) async {
    final vector = textToVector(content);
    _vectors[topicId] = vector;
    await _saveData();
    debugPrint('📊 Stored vector for topic: $topicId');
  }

  /// ➕ Store pre-computed vector
  Future<void> storeVector(String topicId, List<double> vector) async {
    _vectors[topicId] = vector;
    await _saveData();
  }

  /// 🗑️ Remove topic vector
  Future<void> removeVector(String topicId) async {
    _vectors.remove(topicId);
    await _saveData();
  }

  /// 📊 Get stored vector
  List<double>? getVector(String topicId) {
    return _vectors[topicId];
  }

  /// 🔄 Update topic vector
  Future<void> updateTopicVector(String topicId, String newContent) async {
    await storeTopicVector(topicId, newContent);
  }

  // ============================================================
  // 🧹 MAINTENANCE
  // ============================================================

  /// 🔄 Rebuild vocabulary from stored vectors
  Future<void> rebuildVocabulary(List<String> allTexts) async {
    _vocabulary.clear();
    _vocabSize = 0;

    for (final text in allTexts) {
      final tokens = _tokenize(text);
      for (final token in tokens) {
        if (!_vocabulary.containsKey(token) && _vocabSize < maxVocabSize) {
          _vocabulary[token] = _vocabSize;
          _vocabSize++;
        }
      }
    }

    await _saveData();
    debugPrint('🔄 Rebuilt vocabulary: $_vocabSize words');
  }

  /// 🗑️ Clear all
  Future<void> clearAll() async {
    _vocabulary.clear();
    _vectors.clear();
    _vocabSize = 0;
    await _saveData();
  }

  /// 📊 Get stats
  Map<String, dynamic> getStats() {
    return {
      'vocabularySize': _vocabSize,
      'storedVectors': _vectors.length,
      'vectorDimension': vectorDimension,
    };
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// 🔍 Search Result
class SearchResult {
  final String topicId;
  final double score;

  SearchResult({
    required this.topicId,
    required this.score,
  });

  @override
  String toString() => 'SearchResult($topicId: ${score.toStringAsFixed(3)})';
}
