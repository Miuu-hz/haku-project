import 'dart:math';
import '../models/entry.dart';

/// 🔍 Simple In-Memory Vector Search (Brute Force)
/// 
/// ใช้แทน sqlite-vec เมื่อ extension ไม่พร้อม
/// เหมาะกับ entry < 1000 รายการ
/// 
/// Algorithm:
/// 1. สร้าง embedding แบบง่ายจากข้อความ (TF-IDF like)
/// 2. เก็บ vectors ใน memory
/// 3. คำนวณ Cosine Similarity ทุกครั้งที่ search (O(n))

class SimpleVectorSearch {
  final List<_VectorEntry> _vectors = [];
  bool _isInitialized = false;
  
  bool get isInitialized => _isInitialized;
  
  /// 🚀 โหลด entries ทั้งหมดเป็น vectors
  void initialize(List<Entry> entries) {
    _vectors.clear();
    
    for (final entry in entries) {
      final text = '${entry.content} ${entry.tags.join(' ')} ${entry.locationName ?? ''}';
      final vector = _createEmbedding(text);
      _vectors.add(_VectorEntry(entry: entry, vector: vector));
    }
    
    _isInitialized = true;
    print('✅ SimpleVectorSearch: ${entries.length} entries indexed');
  }
  
  /// ➕ เพิ่ม/อัพเดท entry
  void indexEntry(Entry entry) {
    // ลบอันเก่าถ้ามี
    _vectors.removeWhere((v) => v.entry.id == entry.id);
    
    // เพิ่มอันใหม่
    final text = '${entry.content} ${entry.tags.join(' ')} ${entry.locationName ?? ''}';
    final vector = _createEmbedding(text);
    _vectors.add(_VectorEntry(entry: entry, vector: vector));
  }
  
  /// 🔍 ค้นหา Top-K ที่ใกล้เคียงที่สุด
  List<SearchResult> search(String query, {int limit = 5}) {
    if (!_isInitialized || _vectors.isEmpty) {
      return [];
    }
    
    final queryVector = _createEmbedding(query);
    
    // คำนวณ similarity กับทุก entry (Brute Force)
    final results = _vectors.map((v) {
      final similarity = _cosineSimilarity(queryVector, v.vector);
      return SearchResult(entry: v.entry, score: similarity);
    }).toList();
    
    // เรียงจากมากไปน้อย
    results.sort((a, b) => b.score.compareTo(a.score));
    
    return results.take(limit).toList();
  }
  
  /// 🧠 สร้าง embedding แบบง่าย (Bag of Words + TF-IDF like)
  /// 
  /// ข้อจำกัด: ไม่เข้าใจความหมายลึก ๆ แต่จับ keyword ได้ดี
  List<double> _createEmbedding(String text) {
    final normalized = text.toLowerCase()
        .replaceAll(RegExp(r'[^\u0E00-\u0E7Fa-z0-9\s]'), ' ') // เก็บแค่ไทย+อังกฤษ+ตัวเลข
        .trim();
    
    final words = normalized.split(RegExp(r'\s+'))
        .where((w) => w.length > 1) // กรองคำสั้น ๆ
        .toList();
    
    // Vocabulary size: 5000 (hash-based)
    const vocabSize = 5000;
    final vector = List<double>.filled(vocabSize, 0.0);
    
    // TF (Term Frequency)
    for (final word in words) {
      final hash = _hashString(word) % vocabSize;
      vector[hash] += 1.0;
    }
    
    // TF-IDF like: ลด weight ของคำที่เกิดบ่อย (common words)
    final stopWords = _getStopWords();
    for (final word in words) {
      if (stopWords.contains(word)) {
        final hash = _hashString(word) % vocabSize;
        vector[hash] *= 0.1; // ลดน้ำหนักคำทั่วไป
      }
    }
    
    // Normalize (L2 norm)
    final magnitude = sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    if (magnitude > 0) {
      for (var i = 0; i < vector.length; i++) {
        vector[i] /= magnitude;
      }
    }
    
    return vector;
  }
  
  /// 🔢 Hash function สำหรับ string
  int _hashString(String s) {
    var hash = 0;
    for (var i = 0; i < s.length; i++) {
      hash = ((hash << 5) - hash) + s.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF; // Convert to 32-bit int
    }
    return hash.abs();
  }
  
  /// 📐 Cosine Similarity: ค่าใกล้ 1 = คล้ายกันมาก
  double _cosineSimilarity(List<double> a, List<double> b) {
    var dotProduct = 0.0;
    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
    }
    // Vectors ถูก normalize แล้ว ไม่ต้องหาร magnitude
    return dotProduct;
  }
  
  /// 🗑️ ลบ entry
  void removeEntry(int entryId) {
    _vectors.removeWhere((v) => v.entry.id == entryId);
  }
  
  /// 🧹 เคลียร์ทั้งหมด
  void clear() {
    _vectors.clear();
    _isInitialized = false;
  }
  
  /// 📊 จำนวน entries
  int get count => _vectors.length;
}

/// 📝 Data class สำหรับเก็บ vector
class _VectorEntry {
  final Entry entry;
  final List<double> vector;
  
  _VectorEntry({required this.entry, required this.vector});
}

/// 🔍 Search Result (ใช้ร่วมกับ RAGService)
class SearchResult {
  final Entry entry;
  final double score; // 0.0 - 1.0 (1.0 = ตรงกันมาก)
  
  SearchResult({required this.entry, required this.score});
}

/// 🚫 Stop words (ภาษาไทย + อังกฤษ)
Set<String> _getStopWords() => {
    // ไทย
    'จะ', 'ใน', 'ที่', 'ของ', 'และ', 'เป็น', 'ได้', 'ก็', 'ให้', 
    'ว่า', 'มี', 'แต่', 'หรือ', 'ถ้า', 'จาก', 'กับ', 'โดย', 'นี้', 'การ',
    'แล้ว', 'ไป', 'มา', 'อยู่', 'คือ', 'เรา', 'ผม', 'ฉัน', 'คุณ', 'เขา',
    'ซึ่ง', 'อีก', 'บาง', 'ทุก', 'ทั้ง', 'เมื่อ', 'ก่อน', 'หลัง', 'ตอน',
    // อังกฤษ
    'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
    'of', 'with', 'by', 'is', 'are', 'was', 'were', 'be', 'been', 'have',
    'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should',
    'i', 'you', 'he', 'she', 'it', 'we', 'they', 'this', 'that', 'these',
    'those', 'my', 'your', 'his', 'her', 'its', 'our', 'their',
  };
