import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/entry.dart';
import 'database_helper.dart';

/// 🔍 Hybrid Vector Search (Dart-based)
/// 
/// เก็บ vectors ใน SQLite ธรรมดา (BLOB) แทน vec0 extension
/// คำนวณ Cosine Similarity ใน Dart - ไม่ต้องแก้ Native Code
/// 
/// Pros:
/// - ✅ Persistent (ข้อมูลไม่หายตอนปิดแอพ)
/// - ✅ ไม่ต้อง compile sqlite-vec extension
/// - ✅ ใช้ Isolate ได้ (ไม่ block UI)
/// - ✅ รองรับหลายหมื่น records สบาย ๆ

class HybridVectorSearch {
  static const String _tableName = 'hybrid_vectors';
  static const int _vectorDim = 384; // ขนาดเดียวกับ e5-small
  
  Database? _db;
  bool _isInitialized = false;
  
  bool get isInitialized => _isInitialized;
  
  /// 🚀 Initialize database
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'haku_hybrid_vectors.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_tableName (
            entry_id INTEGER PRIMARY KEY,
            embedding BLOB NOT NULL,
            content_hash TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        
        // Index สำหรับ cleanup
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_created_at ON $_tableName(created_at)
        ''');
      },
    );
    
    _isInitialized = true;
    debugPrint('✅ HybridVectorSearch initialized');
  }
  
  /// 📝 Index single entry
  Future<void> indexEntry(Entry entry) async {
    if (!_isInitialized) return;
    
    final text = _extractText(entry);
    final vector = _createEmbedding(text);
    final bytes = _vectorToBytes(vector);
    final contentHash = _hashContent(text);
    
    await _db!.insert(
      _tableName,
      {
        'entry_id': entry.id,
        'embedding': bytes,
        'content_hash': contentHash,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  /// 📝 Index multiple entries (Batch)
  Future<void> indexEntries(List<Entry> entries) async {
    if (!_isInitialized || entries.isEmpty) return;
    
    final batch = _db!.batch();
    
    for (final entry in entries) {
      final text = _extractText(entry);
      final vector = _createEmbedding(text);
      final bytes = _vectorToBytes(vector);
      final contentHash = _hashContent(text);
      
      batch.insert(
        _tableName,
        {
          'entry_id': entry.id,
          'embedding': bytes,
          'content_hash': contentHash,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit(noResult: true);
    debugPrint('✅ Indexed ${entries.length} entries');
  }
  
  /// 🔍 Search with optional Isolate
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    bool useIsolate = false,
  }) async {
    if (!_isInitialized) return [];
    
    // โหลดทุก vectors จาก database
    final rows = await _db!.query(_tableName);
    if (rows.isEmpty) return [];
    
    final queryVector = _createEmbedding(query);
    
    if (useIsolate && rows.length > 1000) {
      // ใช้ Isolate เมื่อข้อมูลเยอะ
      return _searchWithIsolate(rows, queryVector, limit);
    } else {
      // คำนวณปกติสำหรับข้อมูลน้อย
      return _computeSimilarities(rows, queryVector, limit);
    }
  }
  
  /// 🔍 Search ด้วย Isolate (ไม่ block UI)
  Future<List<SearchResult>> _searchWithIsolate(
    List<Map<String, dynamic>> rows,
    List<double> queryVector,
    int limit,
  ) async {
    final receivePort = ReceivePort();
    
    await Isolate.spawn(
      _isolateSearch,
      _SearchIsolateMessage(
        rows: rows,
        queryVector: queryVector,
        limit: limit,
        sendPort: receivePort.sendPort,
      ),
    );
    
    return receivePort.first as List<SearchResult>;
  }
  
  /// 🧮 ฟังก์ชันคำนวณใน Isolate
  static void _isolateSearch(_SearchIsolateMessage message) {
    final results = _computeSimilarities(
      message.rows,
      message.queryVector,
      message.limit,
    );
    message.sendPort.send(results);
  }
  
  /// 🧮 คำนวณ Cosine Similarity
  static List<SearchResult> _computeSimilarities(
    List<Map<String, dynamic>> rows,
    List<double> queryVector,
    int limit,
  ) {
    final results = <SearchResult>[];

    for (final row in rows) {
      try {
        final entryId = row['entry_id'] as int;
        final bytes = row['embedding'];
        if (bytes == null || bytes is! Uint8List || bytes.length != _vectorDim * 4) {
          continue; // ข้าม row ที่ข้อมูลเสีย
        }
        final vector = _bytesToVector(bytes);
        if (vector.length != queryVector.length) {
          continue; // ข้าม vector ที่ขนาดไม่ตรง
        }

        final similarity = _cosineSimilarity(queryVector, vector);
        results.add(SearchResult(
          entryId: entryId,
          score: similarity,
        ));
      } catch (_) {
        continue; // ข้าม row ที่มีปัญหา
      }
    }

    // เรียงจากมากไปน้อย
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList();
  }
  
  /// 🗑️ Remove single entry
  Future<void> removeEntry(int entryId) async {
    if (!_isInitialized) return;
    
    await _db!.delete(
      _tableName,
      where: 'entry_id = ?',
      whereArgs: [entryId],
    );
  }
  
  /// 🧹 Clear all vectors
  Future<void> clear() async {
    if (!_isInitialized) return;
    
    await _db!.delete(_tableName);
  }
  
  /// 📊 Get indexed count
  Future<int> get count async {
    if (!_isInitialized) return 0;
    
    final result = await _db!.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
    return result.first['count'] as int? ?? 0;
  }
  
  /// 🔍 Check if entry is indexed
  Future<bool> isIndexed(int entryId) async {
    if (!_isInitialized) return false;
    
    final result = await _db!.query(
      _tableName,
      where: 'entry_id = ?',
      whereArgs: [entryId],
      limit: 1,
    );
    return result.isNotEmpty;
  }
  
  /// 📝 Full reindex from main database
  Future<void> reindexAll() async {
    if (!_isInitialized) return;
    
    await clear();
    final entries = await DatabaseHelper.instance.getAllEntries();
    await indexEntries(entries);
    debugPrint('✅ Reindexed ${entries.length} entries');
  }
  
  /// 🧹 Close database
  Future<void> dispose() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
      _isInitialized = false;
    }
  }
  
  // ============================================================================
  // Private Helper Methods
  // ============================================================================
  
  /// 📝 Extract text from entry
  String _extractText(Entry entry) =>
      '${entry.content} ${entry.tags.join(' ')} ${entry.locationName ?? ''}';
  
  /// 🧠 Create embedding (TF-IDF hash-based)
  List<double> _createEmbedding(String text) {
    final normalized = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    final tokens = normalized.split(RegExp(r'\s+'));

    final vector = List<double>.filled(_vectorDim, 0.0);

    // Term Frequency
    for (final token in tokens) {
      final hash = _hashString(token) % _vectorDim;
      vector[hash] += 1.0;
    }

    // ลดน้ำหนัก English stop words
    final stopWords = _getStopWords();
    for (final token in tokens) {
      if (stopWords.contains(token)) {
        final hash = _hashString(token) % _vectorDim;
        vector[hash] *= 0.1;
      }
    }

    // L2 Normalize
    final magnitude = sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    if (magnitude > 0) {
      for (var i = 0; i < vector.length; i++) {
        vector[i] /= magnitude;
      }
    }

    return vector;
  }
  
  /// 🔢 Hash string
  int _hashString(String s) {
    var hash = 0;
    for (var i = 0; i < s.length; i++) {
      hash = ((hash << 5) - hash) + s.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.abs();
  }
  
  /// 📦 Convert vector to bytes
  static Uint8List _vectorToBytes(List<double> vector) {
    final buffer = Float32List(vector.length);
    for (var i = 0; i < vector.length; i++) {
      buffer[i] = vector[i];
    }
    return buffer.buffer.asUint8List();
  }
  
  /// 📦 Convert bytes to vector
  static List<double> _bytesToVector(Uint8List bytes) {
    if (bytes.length % 4 != 0) {
      return List<double>.filled(_vectorDim, 0.0);
    }
    final buffer = Float32List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 4);
    return buffer.toList();
  }
  
  /// 🔐 Hash content for change detection
  String _hashContent(String content) => content.hashCode.toString();
  
  /// 📐 Cosine similarity
  static double _cosineSimilarity(List<double> a, List<double> b) {
    var dotProduct = 0.0;
    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
    }
    return dotProduct; // Vectors already normalized
  }
  
  /// 🚫 Stop words
  Set<String> _getStopWords() => {
    'จะ', 'ใน', 'ที่', 'ของ', 'และ', 'เป็น', 'ได้', 'ก็', 'ให้', 
    'ว่า', 'มี', 'แต่', 'หรือ', 'ถ้า', 'จาก', 'กับ', 'โดย', 'นี้', 'การ',
    'แล้ว', 'ไป', 'มา', 'อยู่', 'คือ', 'เรา', 'ผม', 'ฉัน', 'คุณ', 'เขา',
    'ซึ่ง', 'อีก', 'บาง', 'ทุก', 'ทั้ง', 'เมื่อ', 'ก่อน', 'หลัง', 'ตอน',
    'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
    'of', 'with', 'by', 'is', 'are', 'was', 'were', 'be', 'been', 'have',
    'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should',
    'i', 'you', 'he', 'she', 'it', 'we', 'they', 'this', 'that', 'these',
    'those', 'my', 'your', 'his', 'her', 'its', 'our', 'their',
  };
}

/// 🔍 Search Result
class SearchResult {
  final int entryId;
  final double score; // 0.0 - 1.0
  
  SearchResult({required this.entryId, required this.score});
  
  @override
  String toString() => 'SearchResult(entryId: $entryId, score: ${score.toStringAsFixed(3)})';
}

/// 📨 Message สำหรับ Isolate
class _SearchIsolateMessage {
  final List<Map<String, dynamic>> rows;
  final List<double> queryVector;
  final int limit;
  final SendPort sendPort;
  
  _SearchIsolateMessage({
    required this.rows,
    required this.queryVector,
    required this.limit,
    required this.sendPort,
  });
}
