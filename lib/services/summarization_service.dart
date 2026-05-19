import 'dart:math';

import '../models/entry.dart';
import 'context_retriever.dart';
import 'llm_provider_manager.dart';
import 'prompt_builder.dart';

/// 📝 Summarization Service - สรุปบันทึกด้วย AI
/// 
/// รองรับ:
/// - สรุป Entry เดี่ยว (บันทึกยาว → สั้น)
/// - สรุปหลาย Entries (สรุปวัน/สัปดาห์)
/// - ดึง Key Insights (ประเด็นสำคัญ)

class SummarizationService {
  static final SummarizationService _instance = SummarizationService._internal();
  factory SummarizationService() => _instance;
  SummarizationService._internal();

  /// 📝 สรุป Entry เดี่ยว
  ///
  /// 🔋 Battery Optimized: ใช้ lazy loading - LLM จะโหลดเมื่อใช้งานจริง
  Future<String> summarizeEntry(Entry entry) async {
    if (!LLMProviderManager().provider.isInitialized) {
      return _fallbackSummarizeEntry(entry);
    }

    // ดึง context ที่เกี่ยวข้อง
    final contextData = await ContextRetriever().retrieveFullContext();
    final contextStr = ContextRetriever().buildContextString(contextData);

    final prompt = PromptBuilder.buildSummarizeEntryPrompt(
      entry.content,
      context: contextStr.isNotEmpty ? contextStr : null,
    );

    try {
      final response = await LLMProviderManager().provider.generate(prompt);
      return response.trim();
    } catch (e) {
      return _fallbackSummarizeEntry(entry);
    }
  }

  /// 📅 สรุปหลาย Entries (สรุปวัน/สัปดาห์)
  ///
  /// 🔋 Battery Optimized: ใช้ lazy loading
  Future<String> summarizeEntries(
    List<Entry> entries, {
    String? period,
  }) async {
    if (entries.isEmpty) {
      return 'ยังไม่มีบันทึกสำหรับ${period ?? 'ช่วงนี้'}ค่ะ';
    }

    if (!LLMProviderManager().provider.isInitialized) {
      return _fallbackSummarizeEntries(entries, period: period);
    }

    // รวมเนื้อหาทั้งหมด
    final content = entries.map((e) =>
      '- ${e.createdAt.hour}:${e.createdAt.minute.toString().padLeft(2, '0')}: ${e.content}'
    ).join('\n');

    // ดึง context ที่เกี่ยวข้อง
    final contextData = await ContextRetriever().retrieveFullContext();
    final contextStr = ContextRetriever().buildContextString(contextData);

    final prompt = PromptBuilder.buildDailySummaryPrompt(
      entriesContent: content,
      period: period,
      context: contextStr.isNotEmpty ? contextStr : null,
    );

    try {
      final response = await LLMProviderManager().provider.generate(prompt);
      return response.trim();
    } catch (e) {
      return _fallbackSummarizeEntries(entries, period: period);
    }
  }

  /// 🔍 ดึง Key Insights จาก Entry
  ///
  /// 🔋 Battery Optimized: ใช้ lazy loading
  Future<List<String>> extractInsights(Entry entry) async {
    if (!LLMProviderManager().provider.isInitialized) {
      return _fallbackExtractInsights(entry);
    }

    // ดึง context ที่เกี่ยวข้อง
    final contextData = await ContextRetriever().retrieveFullContext();
    final contextStr = ContextRetriever().buildContextString(contextData);

    final prompt = PromptBuilder.buildInsightsPrompt(
      entry.content,
      context: contextStr.isNotEmpty ? contextStr : null,
    );

    try {
      final response = await LLMProviderManager().provider.generate(prompt);

      // Parse รายการ
      final lines = response.split('\n')
        .where((String l) => l.trim().startsWith('-'))
        .map((String l) => l.trim().substring(1).trim())
        .where((String l) => l.isNotEmpty)
        .toList();

      return lines.isEmpty ? _fallbackExtractInsights(entry) : lines;
    } catch (e) {
      return _fallbackExtractInsights(entry);
    }
  }

  /// 📊 วิเคราะห์ Sentiment (ง่าย)
  SentimentAnalysis analyzeSentiment(Entry entry) {
    final text = entry.content;

    // คำบ่งบอกความรู้สึก — ใช้คำที่ยาวพอจะไม่ match substring ผิด
    // คำสั้นอย่าง "ดี" ถูกตัดออกเพราะ match "ไม่ดี", "ดึก" ฯลฯ
    final positiveWords = ['happy', 'มีความสุข', 'สนุก', 'ผ่อนคลาย', 'ภูมิใจ', 'สำเร็จ', 'ดีใจ', 'รักเลย', 'ชอบมาก', 'สดใส', 'ยินดี'];
    final negativeWords = ['เสียใจ', 'เศร้า', 'โกรธ', 'เหนื่อย', 'เบื่อ', 'กังวล', 'เครียด', 'ผิดหวัง', 'ปวดหัว', 'หดหู่', 'ท้อแท้'];
    // คำ negation ที่กลับความหมาย
    final negationWords = ['ไม่', 'ไม่ได้', 'ไม่ค่อย', 'ยัง'];

    int positiveCount = 0;
    int negativeCount = 0;

    for (final word in positiveWords) {
      if (_containsWord(text, word, negationWords)) {
        // มี negation นำหน้า → นับเป็นลบแทน
        negativeCount++;
      } else if (text.contains(word)) {
        positiveCount++;
      }
    }
    for (final word in negativeWords) {
      if (_containsWord(text, word, negationWords)) {
        // มี negation นำหน้า → นับเป็นบวกแทน (เช่น "ไม่เครียด")
        positiveCount++;
      } else if (text.contains(word)) {
        negativeCount++;
      }
    }

    // ใช้ mood ประกอบถ้ามี
    double score = 0.5; // neutral

    if (entry.mood != null) {
      score = entry.mood! / 5.0;
    } else {
      // คำนวณจากคำ — ใช้ full range 0.0-1.0
      final total = positiveCount + negativeCount;
      if (total > 0) {
        score = positiveCount / total;
      }
    }

    String label;
    String emoji;

    if (score >= 0.65) {
      label = 'บวก';
      emoji = '😊';
    } else if (score >= 0.35) {
      label = 'ปานกลาง';
      emoji = '😐';
    } else {
      label = 'ลบ';
      emoji = '😔';
    }

    return SentimentAnalysis(
      score: score,
      label: label,
      emoji: emoji,
      keywords: _extractKeywords(entry.content),
    );
  }

  /// ตรวจสอบว่าคำมี negation นำหน้าหรือไม่
  bool _containsWord(String text, String word, List<String> negations) {
    for (final neg in negations) {
      if (text.contains('$neg$word') || text.contains('$neg $word')) {
        return true;
      }
    }
    return false;
  }

  // ============================================================================
  // Fallback Methods (ไม่มี LLM)
  // ============================================================================

  String _fallbackSummarizeEntry(Entry entry) {
    final content = entry.content;
    if (content.length < 100) {
      return content;
    }
    
    // ตัดเอา 2-3 ประโยคแรก
    final sentences = content.split(RegExp(r'[.!?。！？\n]'))
      .where((s) => s.trim().isNotEmpty)
      .take(2)
      .join('... ');
    
    return sentences.isNotEmpty ? '$sentences...' : '${content.substring(0, min(100, content.length))}...';
  }

  String _fallbackSummarizeEntries(List<Entry> entries, {String? period}) {
    final count = entries.length;
    final moods = entries.where((e) => e.mood != null).map((e) => e.mood!).toList();
    final avgMood = moods.isNotEmpty 
      ? moods.reduce((a, b) => a + b) / moods.length 
      : null;
    
    String moodText = '';
    if (avgMood != null) {
      if (avgMood >= 4) {
        moodText = ' ดูเหมือนจะเป็นวันที่ดีนะคะ 😊';
      } else if (avgMood <= 2) {
        moodText = ' ดูเหมือนวันนี้จะเหนื่อยหน่อยนะคะ 💪';
      } else {
        moodText = ' วันนี้ก็ผ่านไปได้ด้วยดีค่ะ 😌';
      }
    }
    
    return '${period ?? 'วันนี้'}คุณมี $count บันทึก$moodText';
  }

  List<String> _fallbackExtractInsights(Entry entry) {
    final insights = <String>[];
    
    // ดึงจาก tags
    if (entry.tags.isNotEmpty) {
      insights.add('แท็ก: ${entry.tags.take(3).join(', ')}');
    }
    
    // ดึงจาก location
    if (entry.locationName != null) {
      insights.add('สถานที่: ${entry.locationName}');
    }
    
    // ดึงจาก mood
    if (entry.mood != null) {
      final moodInfo = Entry.getMoodInfo(entry.mood);
      insights.add('อารมณ์: ${moodInfo['label']} ${moodInfo['emoji']}');
    }
    
    // ถ้ายังไม่มี เอาคำแรก ๆ
    if (insights.isEmpty) {
      final words = entry.content.split(' ').take(5).join(' ');
      insights.add('เริ่มต้นด้วย: "$words..."');
    }
    
    return insights;
  }

  List<String> _extractKeywords(String text) {
    final stopWords = {'จะ', 'ใน', 'ที่', 'ของ', 'และ', 'เป็น', 'ได้', 'ก็', 'ให้', 'ว่า', 'มี', 'the', 'a', 'is', 'and', 'แล้ว', 'ไป', 'มา', 'อยู่', 'กับ', 'จาก', 'ไม่'};

    final words = text.toLowerCase()
      .replaceAll(RegExp(r'[^\u0E00-\u0E7Fa-z0-9\s]'), '')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2 && !stopWords.contains(w))
      .toList();

    // นับความถี่แล้วเรียงจากมากไปน้อย
    final frequency = <String, int>{};
    for (final w in words) {
      frequency[w] = (frequency[w] ?? 0) + 1;
    }

    final sorted = frequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(5).map((e) => e.key).toList();
  }
}

/// 📊 ผลวิเคราะห์ Sentiment
class SentimentAnalysis {
  final double score; // 0.0 - 1.0
  final String label;
  final String emoji;
  final List<String> keywords;

  SentimentAnalysis({
    required this.score,
    required this.label,
    required this.emoji,
    required this.keywords,
  });
}
