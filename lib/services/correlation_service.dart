import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/correlation_models.dart';
import '../models/entry.dart';
import 'database_helper.dart';
import 'entity_extractor.dart';
import 'mediapipe_llm_service.dart';
import 'unified_vector_service.dart';

/// 🔮 Correlation Service - หาความเชื่อมโยงที่ซ่อนอยู่
/// 
/// วิเคราะห์ entities จาก entries แล้วหา correlation
/// เก็บผลเป็น CorrelationInsight ใน RAG (VectorType.insight)

class CorrelationService {
  static final CorrelationService _instance = CorrelationService._internal();
  factory CorrelationService() => _instance;
  CorrelationService._internal();

  final EntityExtractor _extractor = EntityExtractor();
  final MediaPipeLLMService _llm = MediaPipeLLMService();
  final UnifiedVectorService _vectorService = UnifiedVectorService();

  bool _isAnalyzing = false;

  /// กำลังวิเคราะห์อยู่หรือไม่
  bool get isAnalyzing => _isAnalyzing;

  // ============================================================
  // 🔍 MAIN ANALYSIS METHODS
  // ============================================================

  /// 🔮 วิเคราะห์ความเชื่อมโยงทั้งหมด
  /// 
  /// @param daysBack จำนวนวันย้อนหลังที่จะวิเคราะห์ (default: 30)
  /// @param minSampleSize จำนวนตัวอย่างขั้นต่ำ (default: 5)
  /// @param useGemmaSummary ใช้ Gemma สรุปผลหรือไม่
  Future<CorrelationAnalysisResult> analyzeCorrelations({
    int daysBack = 30,
    int minSampleSize = 5,
    bool useGemmaSummary = true,
  }) async {
    if (_isAnalyzing) {
      throw StateError('Analysis already in progress');
    }

    _isAnalyzing = true;
    debugPrint('🔮 Starting correlation analysis for last $daysBack days...');

    try {
      // 1. ดึง entries ย้อนหลัง
      final entries = await _fetchEntries(daysBack);
      if (entries.isEmpty) {
        return CorrelationAnalysisResult(
          insights: [],
          totalDaysAnalyzed: 0,
          totalEntitiesFound: 0,
          analyzedAt: DateTime.now(),
        );
      }

      // 2. สกัด entities ทั้งหมด
      final snapshots = await _extractor.extractFromEntries(entries);
      debugPrint('📊 Extracted ${snapshots.length} daily snapshots');

      // 3. คำนวณ correlation ทั้งหมด
      final insights = await _calculateAllCorrelations(
        snapshots,
        minSampleSize: minSampleSize,
      );

      // 4. เก็บ insights ลง RAG
      await _storeInsights(insights);

      // 5. ใช้ Gemma สรุปผล (ถ้าต้องการ)
      String? gemmaSummary;
      if (useGemmaSummary && insights.isNotEmpty) {
        gemmaSummary = await _generateGemmaSummary(insights);
      }

      // 6. สร้างผลลัพธ์
      final result = CorrelationAnalysisResult(
        insights: insights,
        totalDaysAnalyzed: snapshots.length,
        totalEntitiesFound: snapshots.expand((s) => s.entities).length,
        analyzedAt: DateTime.now(),
        gemmaSummary: gemmaSummary,
      );

      debugPrint('✅ Analysis complete: ${insights.length} insights found');
      return result;

    } finally {
      _isAnalyzing = false;
    }
  }

  /// 🔄 วิเคราะห์แบบเร็ว (ใช้ข้อมูลที่มีอยู่แล้ว)
  Future<CorrelationAnalysisResult> quickAnalyze() async {
    return analyzeCorrelations(
      daysBack: 14,        // ดูแค่ 2 อาทิตย์
      minSampleSize: 3,    // ตัวอย่างน้อยกว่า
      useGemmaSummary: false,
    );
  }

  // ============================================================
  // 📊 DATA FETCHING & PREPARATION
  // ============================================================

  /// 📥 ดึง entries ย้อนหลัง
  Future<List<Entry>> _fetchEntries(int daysBack) async {
    final allEntries = await DatabaseHelper.instance.getAllEntries();
    final cutoffDate = DateTime.now().subtract(Duration(days: daysBack));
    
    return allEntries
        .where((e) => e.createdAt.isAfter(cutoffDate))
        .toList();
  }

  // ============================================================
  // 🧮 CORRELATION CALCULATION
  // ============================================================

  /// 🧮 คำนวณ correlation ทั้งหมด
  Future<List<CorrelationInsight>> _calculateAllCorrelations(
    List<DailyEntitySnapshot> snapshots,
    {required int minSampleSize}
  ) async {
    final insights = <CorrelationInsight>[];
    
    // หา unique entities ทั้งหมด
    final allEntities = <String, EntityType>{};
    for (final snapshot in snapshots) {
      for (final entity in snapshot.entities) {
        allEntities[entity.uniqueKey] = entity.type;
      }
    }
    
    final entityList = allEntities.entries.toList();
    debugPrint('🔍 Found ${entityList.length} unique entities to analyze');

    // คำนวณ correlation ระหว่าง entity ทุกคู่
    for (var i = 0; i < entityList.length; i++) {
      for (var j = i + 1; j < entityList.length; j++) {
        final entityA = entityList[i];
        final entityB = entityList[j];
        
        // ข้ามถ้าเป็น type เดียวกัน (ยกเว้นบางกรณี)
        if (entityA.value == entityB.value) continue;
        
        final insight = await _calculatePairCorrelation(
          entityA.key,
          entityA.value,
          entityB.key,
          entityB.value,
          snapshots,
          minSampleSize: minSampleSize,
        );
        
        if (insight != null) {
          insights.add(insight);
        }
      }
    }

    // เรียงตามความสำคัญ
    insights.sort((a, b) => 
        (b.confidence * b.correlation.abs()).compareTo(a.confidence * a.correlation.abs()));

    return insights;
  }

  /// 🎯 คำนวณ correlation ระหว่าง entity คู่หนึ่ง
  Future<CorrelationInsight?> _calculatePairCorrelation(
    String keyA,
    EntityType typeA,
    String keyB,
    EntityType typeB,
    List<DailyEntitySnapshot> snapshots,
    {required int minSampleSize}
  ) async {
    // นับวันที่มี A, มี B, มีทั้งคู่
    var countA = 0;
    var countB = 0;
    var countBoth = 0;
    var countNeither = 0;
    final occurrences = <DateTime>[];

    for (final snapshot in snapshots) {
      final hasA = snapshot.hasEntity(typeA, keyA.split(':')[1]);
      final hasB = snapshot.hasEntity(typeB, keyB.split(':')[1]);

      if (hasA) countA++;
      if (hasB) countB++;
      if (hasA && hasB) {
        countBoth++;
        occurrences.add(snapshot.date);
      }
      if (!hasA && !hasB) countNeither++;
    }

    final totalDays = snapshots.length;
    
    // ต้องมีข้อมูลพอ
    if (countA < minSampleSize || countB < minSampleSize) return null;

    // คำนวณ correlation coefficient (Phi coefficient สำหรับ binary data)
    final correlation = _calculatePhiCoefficient(
      countA, countB, countBoth, countNeither, totalDays
    );

    // คำนวณ confidence จากจำนวนตัวอย่าง
    final confidence = _calculateConfidence(countBoth, minSampleSize);

    // คำนวณ support (% ของวันที่มีทั้งคู่)
    final support = countBoth / totalDays;

    // ข้ามถ้า correlation ต่ำเกินไป
    if (correlation.abs() < 0.3) return null;

    // สร้าง description
    final description = _generateDescription(
      keyA.split(':')[1],
      typeA,
      keyB.split(':')[1],
      typeB,
      correlation,
      countBoth,
      totalDays,
    );

    return CorrelationInsight(
      id: '${keyA}_${keyB}_${DateTime.now().millisecondsSinceEpoch}',
      entityAType: typeA,
      entityAValue: keyA.split(':')[1],
      entityBType: typeB,
      entityBValue: keyB.split(':')[1],
      correlation: correlation,
      confidence: confidence,
      sampleSize: countBoth,
      support: support,
      description: description,
      occurrences: occurrences,
      discoveredAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
  }

  /// 🧮 คำนวณ Phi Coefficient (สำหรับ binary correlation)
  double _calculatePhiCoefficient(
    int countA,
    int countB,
    int countBoth,
    int countNeither,
    int total
  ) {
    final countAOnly = countA - countBoth;
    final countBOnly = countB - countBoth;
    
    // Contingency table:
    //          B+      B-
    // A+    countBoth  countAOnly
    // A-    countBOnly countNeither
    
    final a = countBoth.toDouble();
    final b = countAOnly.toDouble();
    final c = countBOnly.toDouble();
    final d = countNeither.toDouble();
    
    final denominator = sqrt((a + b) * (c + d) * (a + c) * (b + d));
    if (denominator == 0) return 0;
    
    return (a * d - b * c) / denominator;
  }

  /// 📊 คำนวณ confidence จาก sample size
  double _calculateConfidence(int sampleSize, int minRequired) {
    if (sampleSize < minRequired) return 0;
    
    // ใช้ logistic function ให้ confidence เพิ่มขึ้นตาม sample size
    // ที่ 5 samples = ~0.5, 10 samples = ~0.8, 20 samples = ~0.95
    final x = (sampleSize - minRequired) / minRequired;
    return 1 / (1 + exp(-2 * x));
  }

  /// 📝 สร้างคำอธิบาย
  String _generateDescription(
    String valueA,
    EntityType typeA,
    String valueB,
    EntityType typeB,
    double correlation,
    int countBoth,
    int totalDays,
  ) {
    final percentage = (countBoth / totalDays * 100).round();
    final strength = correlation.abs() > 0.7 
        ? 'สูงมาก' 
        : correlation.abs() > 0.5 
            ? 'สูง' 
            : 'ปานกลาง';
    
    if (correlation > 0) {
      return '${percentage}% ของวันที่มี "${valueA}" จะมี "${valueB}" ด้วย (ความสัมพันธ์$strength)';
    } else {
      return 'เมื่อมี "${valueA}" มักจะไม่มี "${valueB}" (ความสัมพันธ์เชิงลบ$strength)';
    }
  }

  // ============================================================
  // 💾 STORAGE (RAG Integration)
  // ============================================================

  /// 💾 เก็บ insights ลง Vector DB
  Future<void> _storeInsights(List<CorrelationInsight> insights) async {
    await _vectorService.initialize();
    
    for (final insight in insights) {
      // สร้าง content สำหรับ embedding
      final content = '''
Insight: ${insight.description}
${insight.entityAType.name}: ${insight.entityAValue}
${insight.entityBType.name}: ${insight.entityBValue}
Correlation: ${insight.correlation.toStringAsFixed(2)}
Confidence: ${(insight.confidence * 100).toStringAsFixed(0)}%
'''.trim();

      // เก็บเป็น Knowledge (แยกประเภท insight)
      await _vectorService.addKnowledge(
        topic: 'correlation',
        content: content,
        metadata: {
          'type': 'insight',
          'entityAType': insight.entityAType.name,
          'entityAValue': insight.entityAValue,
          'entityBType': insight.entityBType.name,
          'entityBValue': insight.entityBValue,
          'correlation': insight.correlation,
          'confidence': insight.confidence,
          'sampleSize': insight.sampleSize,
          'discoveredAt': insight.discoveredAt.toIso8601String(),
        },
      );
    }
    
    debugPrint('💾 Stored ${insights.length} insights to Vector DB');
  }

  /// 🔍 ค้นหา insights ที่เกี่ยวข้อง
  Future<List<CorrelationInsight>> findRelatedInsights(String query) async {
    await _vectorService.initialize();
    
    final results = _vectorService.search(
      query,
      type: VectorType.knowledge,
      category: 'correlation',
      limit: 10,
    );
    
    // แปลงกลับเป็น CorrelationInsight
    final insights = <CorrelationInsight>[];
    for (final result in results) {
      final meta = result.item.metadata;
      if (meta == null) continue;
      
      try {
        insights.add(CorrelationInsight(
          id: result.item.id,
          entityAType: EntityType.values.firstWhere(
            (e) => e.name == meta['entityAType'],
            orElse: () => EntityType.activities,
          ),
          entityAValue: meta['entityAValue'] as String,
          entityBType: EntityType.values.firstWhere(
            (e) => e.name == meta['entityBType'],
            orElse: () => EntityType.activities,
          ),
          entityBValue: meta['entityBValue'] as String,
          correlation: (meta['correlation'] as num).toDouble(),
          confidence: (meta['confidence'] as num).toDouble(),
          sampleSize: meta['sampleSize'] as int? ?? 0,
          support: 0,
          description: result.item.content,
          occurrences: [],
          discoveredAt: DateTime.parse(meta['discoveredAt'] as String),
          lastUpdated: DateTime.now(),
        ));
      } catch (e) {
        debugPrint('⚠️ Failed to parse insight: $e');
      }
    }
    
    return insights;
  }

  // ============================================================
  // 🤖 GEMMA SUMMARY
  // ============================================================

  /// 🤖 ใช้ Gemma สรุป insights
  Future<String?> _generateGemmaSummary(List<CorrelationInsight> insights) async {
    if (!_llm.isInitialized || insights.isEmpty) return null;

    try {
      // เลือกแค่ insights ที่น่าสนใจ
      final topInsights = insights
          .where((i) => i.confidence > 0.5 && i.correlation.abs() > 0.4)
          .take(5)
          .toList();

      if (topInsights.isEmpty) return null;

      // สร้าง prompt
      final prompt = _buildSummaryPrompt(topInsights);
      
      final response = await _llm.generate(prompt);
      return response.trim();

    } catch (e) {
      debugPrint('⚠️ Gemma summary error: $e');
      return null;
    }
  }

  /// 📝 สร้าง prompt สำหรับสรุป
  String _buildSummaryPrompt(List<CorrelationInsight> insights) {
    final buffer = StringBuffer();
    buffer.writeln('<start_of_turn>user');
    buffer.writeln('You are a friendly AI assistant analyzing life patterns.');
    buffer.writeln('Write a short, friendly summary in Thai about these correlations found:');
    buffer.writeln();

    for (var i = 0; i < insights.length; i++) {
      final ins = insights[i];
      buffer.writeln('${i + 1}. ${ins.description}');
      if (ins.correlation > 0.5) {
        buffer.writeln('   → Positive correlation: ${(ins.correlation * 100).toStringAsFixed(0)}%');
      } else if (ins.correlation < -0.5) {
        buffer.writeln('   → Negative correlation');
      }
    }

    buffer.writeln();
    buffer.writeln('Write 2-3 sentences in Thai, friendly tone, like talking to a friend.');
    buffer.writeln('Focus on the most surprising or useful pattern.');
    buffer.writeln('Include an emoji. Keep it under 200 characters.');
    buffer.writeln('<end_of_turn>');
    buffer.writeln('<start_of_turn>model');

    return buffer.toString();
  }

  // ============================================================
  // 🎯 UTILITY METHODS
  // ============================================================

  /// 🧹 ล้าง insights เก่าทั้งหมด
  Future<void> clearAllInsights() async {
    await _vectorService.initialize();
    await _vectorService.deleteByCategory('correlation');
    debugPrint('🧹 Cleared all correlation insights');
  }

  /// 📊 ดึงสถิติ insights
  Future<Map<String, dynamic>> getStats() async {
    await _vectorService.initialize();
    
    final allKnowledge = _vectorService.knowledge
        .where((k) => k.metadata?['category'] == 'correlation')
        .toList();

    return {
      'totalInsights': allKnowledge.length,
      'highConfidence': allKnowledge.where((k) => 
          (k.metadata?['confidence'] as double? ?? 0) > 0.7).length,
      'healthRelated': allKnowledge.where((k) {
        final typeA = k.metadata?['entityAType'] as String?;
        final typeB = k.metadata?['entityBType'] as String?;
        return typeA == 'symptoms' || typeB == 'symptoms';
      }).length,
    };
  }
}
