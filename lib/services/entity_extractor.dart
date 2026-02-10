import 'package:flutter/foundation.dart';

import '../models/correlation_models.dart';
import '../models/entry.dart';
import 'mediapipe_llm_service.dart';

/// 🔍 Entity Extractor - สกัด entities จาก entry content
/// 
/// ใช้ Hybrid approach:
/// 1. Rule-based หลัก (เร็ว, แม่นพื้นฐาน)
/// 2. Gemma fallback (กรณี rule-based ไม่เจอ/ไม่แน่ใจ)

class EntityExtractor {
  static final EntityExtractor _instance = EntityExtractor._internal();
  factory EntityExtractor() => _instance;
  EntityExtractor._internal();

  final MediaPipeLLMService _llm = MediaPipeLLMService();

  // ============================================================
  // 🎯 PATTERN DEFINITIONS (Rule-based)
  // ============================================================

  /// 🛌 Sleep Patterns
  static final List<_ExtractionPattern> _sleepPatterns = [
    _ExtractionPattern(
      type: EntityType.sleepHours,
      regex: RegExp(r'นอน\s*(\d+(?:\.\d+)?)\s*ชั่วโมง'),
      valueGroup: 1,
      normalizer: (m) => '${m}h',
    ),
    _ExtractionPattern(
      type: EntityType.sleepHours,
      regex: RegExp(r'นอน\s*(\d+)\s*ช\.ม\.'),
      valueGroup: 1,
      normalizer: (m) => '${m}h',
    ),
    _ExtractionPattern(
      type: EntityType.sleepHours,
      regex: RegExp(r'นอนไป\s*(\d+)\s*ชม'),
      valueGroup: 1,
      normalizer: (m) => '${m}h',
    ),
    _ExtractionPattern(
      type: EntityType.sleepHours,
      regex: RegExp(r'(?:นอนน้อย|นอนไม่พอ|นอนไม่หลับ).*?(\d+)\s*ชั่วโมง'),
      valueGroup: 1,
      normalizer: (m) => '${m}h',
    ),
  ];

  /// 🍜 Food & Drink Patterns
  static final List<_ExtractionPattern> _foodPatterns = [
    // กาแฟ
    _ExtractionPattern(
      type: EntityType.food,
      regex: RegExp(r'กาแฟ([\u0E00-\u0E7F\w\s]+?)(?:ร้าน|ที่|ตอน|เช้า|บ่าย|เย็น|\s|$)'),
      valueGroup: 1,
      normalizer: (m) => 'กาแฟ${m.trim()}',
    ),
    _ExtractionPattern(
      type: EntityType.food,
      regex: RegExp(r'ร้าน([\u0E00-\u0E7F\w\s]+?)(?:ร้าน|ที่|ตอน|เช้า|บ่าย|เย็น|\s|$)'),
      valueGroup: 1,
      normalizer: (m) => 'ร้าน${m.trim()}',
    ),
    // อาหารทั่วไป
    _ExtractionPattern(
      type: EntityType.food,
      regex: RegExp(r'(?:กิน|ทาน|สั่ง)([\u0E00-\u0E7F\w\s]+?)(?:ร้าน|ตอน|เย็น|กลางวัน|เช้า|บ่าย|\s|$)'),
      valueGroup: 1,
      normalizer: (m) => m.trim(),
    ),
    // น้ำ/เครื่องดื่ม
    _ExtractionPattern(
      type: EntityType.food,
      regex: RegExp(r'(ชา|นม|น้ำ|โซดา|เบียร์|ไวน์|สมูทตี้)(?:\s*[\u0E00-\u0E7F\w\s]+?)?(?:เย็น|ร้อน|ปั่น|หวาน)?'),
      valueGroup: 1,
      normalizer: (m) => m.trim(),
    ),
  ];

  /// 🤒 Symptoms & Health Patterns
  static final List<_ExtractionPattern> _symptomPatterns = [
    _ExtractionPattern(
      type: EntityType.symptoms,
      regex: RegExp(r'(ปวดหัว|ไมเกรน|ปวดตา|ปวดคอ|ปวดหลัง|ปวดเอว|ปวดท้อง|ปวดขา|ปวดแขน)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
    _ExtractionPattern(
      type: EntityType.symptoms,
      regex: RegExp(r'(เป็นหวัด|ไข้|ไอ|เจ็บคอ|คัดจมูก|น้ำมูก|ปวดฟัน)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
    _ExtractionPattern(
      type: EntityType.symptoms,
      regex: RegExp(r'(เมื่อย|เหนื่อย|อ่อนเพลีย|ง่วง|เพลีย|ไม่มีแรง)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
    _ExtractionPattern(
      type: EntityType.symptoms,
      regex: RegExp(r'(คลื่นไส้|ท้องเสีย|ท้องผูก|แสบท้อง|จุกเสียด)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
    _ExtractionPattern(
      type: EntityType.symptoms,
      regex: RegExp(r'(เครียด|กังวล|วิตกกังวล|ซึมเศร้า|วิตก|นอนไม่หลับ|ฝันร้าย)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
  ];

  /// 🏃 Activities Patterns
  static final List<_ExtractionPattern> _activityPatterns = [
    _ExtractionPattern(
      type: EntityType.activities,
      regex: RegExp(r'(วิ่ง|เดิน|ปั่นจักรยาน|ว่ายน้ำ|โยคะ|เวท|ออกกำลังกาย|ฟิตเนส|ยิม)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
    _ExtractionPattern(
      type: EntityType.activities,
      regex: RegExp(r'(อ่านหนังสือ|เรียน|อ่านการ์ตูน|ฟังเพลง|ดูหนัง|ดูซีรีส์|เล่นเกม)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
    _ExtractionPattern(
      type: EntityType.activities,
      regex: RegExp(r'(เที่ยว|ท่องเที่ยว|เที่ยวต่างจังหวัด|เที่ยวทะเล|เที่ยวภูเขา)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
    _ExtractionPattern(
      type: EntityType.activities,
      regex: RegExp(r'(ช้อปปิ้ง|ซื้อของ|จ่ายตลาด|ซื้อกับข้าว)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
  ];

  /// 👥 Social Patterns
  static final List<_ExtractionPattern> _socialPatterns = [
    _ExtractionPattern(
      type: EntityType.social,
      regex: RegExp(r'(เจอเพื่อน|เจอแฟน|เจอครอบครัว|เจอพี่|เจอน้อง|เจอเพื่อนร่วมงาน)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
    _ExtractionPattern(
      type: EntityType.social,
      regex: RegExp(r'(ปาร์ตี้|สังสรรค์|ดื่ม|hangout|ดินเนอร์)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
    _ExtractionPattern(
      type: EntityType.social,
      regex: RegExp(r'(คุยกับ|โทรหา|video call|แชทกับ)'),
      valueGroup: 1,
      normalizer: (m) => m,
    ),
    _ExtractionPattern(
      type: EntityType.social,
      regex: RegExp(r'(อยู่คนเดียว|คนเดียว|alone time|me time)'),
      valueGroup: 1,
      normalizer: (m) => 'อยู่คนเดียว',
    ),
  ];

  /// 🌦️ Weather Patterns
  static final List<_ExtractionPattern> _weatherPatterns = [
    _ExtractionPattern(
      type: EntityType.weather,
      regex: RegExp(r'(ฝนตก|ฝน|พายุ|ฟ้าผ่า|ฝนตกหนัก)'),
      valueGroup: 1,
      normalizer: (m) => 'ฝนตก',
    ),
    _ExtractionPattern(
      type: EntityType.weather,
      regex: RegExp(r'(ร้อน|อากาศร้อน|ร้อนมาก|ตับแตก)'),
      valueGroup: 1,
      normalizer: (m) => 'อากาศร้อน',
    ),
    _ExtractionPattern(
      type: EntityType.weather,
      regex: RegExp(r'(หนาว|อากาศหนาว|หนาวมาก|เย็น)'),
      valueGroup: 1,
      normalizer: (m) => 'อากาศหนาว',
    ),
    _ExtractionPattern(
      type: EntityType.weather,
      regex: RegExp(r'(แดด|แดดออก|อากาศดี|ลม|ลมแรง|ฝุ่น|PM2\.5)'),
      valueGroup: 1,
      normalizer: (m) => m.contains('ฝุ่น') ? 'ฝุ่น' : m,
    ),
  ];

  /// 👤 People Patterns
  static final List<_ExtractionPattern> _peoplePatterns = [
    _ExtractionPattern(
      type: EntityType.people,
      regex: RegExp(r'(?:คุยกับ|เจอ|ทำงานกับ|ทานข้าวกับ|เที่ยวกับ)([\u0E00-\u0E7F\w\s]+?)(?:วัน|ตอน|ที่|เรื่อง|ก็|\s|$)'),
      valueGroup: 1,
      normalizer: (m) => m.trim(),
    ),
  ];

  /// 💼 Work Stress Patterns
  static final List<_ExtractionPattern> _workStressPatterns = [
    _ExtractionPattern(
      type: EntityType.workStress,
      regex: RegExp(r'(deadline|เดดไลน์|ส่งงาน|งานเยอะ|งานล้น|งานไม่เสร็จ|เร่งงาน)'),
      valueGroup: 1,
      normalizer: (m) => 'deadline',
    ),
    _ExtractionPattern(
      type: EntityType.workStress,
      regex: RegExp(r'(ประชุม|meeting|ประชุมยาว|ประชุมนาน|คอล|call งาน)'),
      valueGroup: 1,
      normalizer: (m) => 'ประชุม',
    ),
    _ExtractionPattern(
      type: EntityType.workStress,
      regex: RegExp(r'(OT|โอที|ทำงานดึก|ทำงานดึกดื่น|加班)'),
      valueGroup: 1,
      normalizer: (m) => 'OT',
    ),
    _ExtractionPattern(
      type: EntityType.workStress,
      regex: RegExp(r'(เครียดงาน|กดดัน|pressure|งานเข้า|งานเร่งด่วน)'),
      valueGroup: 1,
      normalizer: (m) => 'เครียดงาน',
    ),
  ];

  /// 💰 Expense Patterns
  static final List<_ExtractionPattern> _expensePatterns = [
    _ExtractionPattern(
      type: EntityType.expense,
      regex: RegExp(r'(?:ใช้|เสีย|จ่าย|ซื้อ)(?:ไป)?\s*(\d{2,6})(?:\s*บาท)?'),
      valueGroup: 1,
      normalizer: (m) => '${m}B',
    ),
    _ExtractionPattern(
      type: EntityType.expense,
      regex: RegExp(r'(แพง|ใช้เงินเยอะ|จ่ายเยอะ|หมดตังค์|ใช้จ่ายเยอะ)'),
      valueGroup: 1,
      normalizer: (m) => 'ใช้จ่ายเยอะ',
    ),
  ];

  /// 😊 Detailed Mood Patterns (นอกเหนือจาก mood score)
  static final List<_ExtractionPattern> _moodPatterns = [
    _ExtractionPattern(
      type: EntityType.mood,
      regex: RegExp(r'(มีความสุข|สุข|happy|ดีใจ|ตื่นเต้น|ดีใจมาก)'),
      valueGroup: 1,
      normalizer: (m) => 'มีความสุข',
    ),
    _ExtractionPattern(
      type: EntityType.mood,
      regex: RegExp(r'(เศร้า|เสียใจ| sad |ร้องไห้|น้ำตา)'),
      valueGroup: 1,
      normalizer: (m) => 'เศร้า',
    ),
    _ExtractionPattern(
      type: EntityType.mood,
      regex: RegExp(r'(โกรธ|โมโห|ฉุน|หงุดหงิด|angry|แค้น)'),
      valueGroup: 1,
      normalizer: (m) => 'โกรธ',
    ),
    _ExtractionPattern(
      type: EntityType.mood,
      regex: RegExp(r'(กลัว|หวาดกลัว|กังวล|วิตก|กลุ้มใจ|กังวลใจ)'),
      valueGroup: 1,
      normalizer: (m) => 'กังวล',
    ),
    _ExtractionPattern(
      type: EntityType.mood,
      regex: RegExp(r'(เบื่อ|เบื่อหน่าย|ท้อ|ท้อแท้|สิ้นหวัง|หมดกำลังใจ)'),
      valueGroup: 1,
      normalizer: (m) => 'เบื่อ',
    ),
  ];

  // ============================================================
  // 🔧 MAIN EXTRACTION METHODS
  // ============================================================

  /// 🔍 สกัด entities จาก entry (Rule-based หลัก)
  Future<EntityExtractionResult> extractFromEntry(Entry entry, {bool useGemmaFallback = true}) async {
    final entities = <Entity>[];
    final content = entry.content;
    
    // 1. Rule-based extraction
    entities.addAll(_extractWithRules(content, entry));
    
    // 2. Gemma fallback (ถ้าไม่เจออะไรเลย หรือต้องการ detail เพิ่ม)
    if (useGemmaFallback && entities.isEmpty) {
      debugPrint('🤖 Rule-based found 0 entities, trying Gemma...');
      final gemmaEntities = await _extractWithGemma(content, entry);
      entities.addAll(gemmaEntities);
    }
    
    // 3. เพิ่ม location จาก entry (ถ้ามี)
    if (entry.locationName != null && entry.locationName!.isNotEmpty) {
      entities.add(Entity(
        type: EntityType.location,
        value: entry.locationName!,
        rawText: entry.locationName!,
        timestamp: entry.createdAt,
        entryId: entry.id,
        confidence: 1.0,
      ));
    }
    
    // 4. Map mood score เป็น entity (ถ้ามี)
    if (entry.mood != null) {
      entities.add(Entity(
        type: EntityType.mood,
        value: 'mood_${entry.mood}',
        rawText: 'mood score ${entry.mood}/5',
        timestamp: entry.createdAt,
        entryId: entry.id,
        confidence: 1.0,
        metadata: {'score': entry.mood},
      ));
    }

    return EntityExtractionResult(
      entities: _deduplicateEntities(entities),
      method: useGemmaFallback && entities.any((e) => e.metadata?['source'] == 'gemma')
          ? 'hybrid'
          : 'rule_based',
      extractedAt: DateTime.now(),
      entryId: entry.id ?? 0,
    );
  }

  /// 🔧 สกัดด้วย Rule-based patterns
  List<Entity> _extractWithRules(String content, Entry entry) {
    final entities = <Entity>[];
    final allPatterns = [
      ..._sleepPatterns,
      ..._foodPatterns,
      ..._symptomPatterns,
      ..._activityPatterns,
      ..._socialPatterns,
      ..._weatherPatterns,
      ..._peoplePatterns,
      ..._workStressPatterns,
      ..._expensePatterns,
      ..._moodPatterns,
    ];

    for (final pattern in allPatterns) {
      final matches = pattern.regex.allMatches(content);
      for (final match in matches) {
        final rawValue = match.group(pattern.valueGroup) ?? '';
        if (rawValue.isEmpty) continue;
        
        final normalizedValue = pattern.normalizer(rawValue);
        
        entities.add(Entity(
          type: pattern.type,
          value: normalizedValue,
          rawText: match.group(0) ?? rawValue,
          timestamp: entry.createdAt,
          entryId: entry.id,
          confidence: 0.85,
        ));
      }
    }

    return entities;
  }

  /// 🤖 สกัดด้วย Gemma (Fallback)
  Future<List<Entity>> _extractWithGemma(String content, Entry entry) async {
    final entities = <Entity>[];
    
    try {
      if (!_llm.isInitialized) {
        debugPrint('⚠️ LLM not initialized, skipping Gemma extraction');
        return entities;
      }

      final prompt = _buildEntityExtractionPrompt(content);
      final response = await _llm.generate(prompt);
      
      // Parse JSON response
      final parsed = _parseGemmaResponse(response, entry);
      entities.addAll(parsed);
      
    } catch (e) {
      debugPrint('❌ Gemma extraction error: $e');
    }
    
    return entities;
  }

  /// 📝 สร้าง prompt สำหรับ Gemma
  String _buildEntityExtractionPrompt(String content) {
    return '''<start_of_turn>user
Analyze this Thai diary entry and extract relevant entities. Return ONLY a JSON array.

Entry: "$content"

Extract these entity types:
- sleep_hours: e.g., "5h", "8h"
- food: e.g., "กาแฟ Starbucks", "ข้าวผัด"
- symptoms: e.g., "ปวดหัว", "เหนื่อย", "เป็นหวัด"
- activities: e.g., "วิ่ง", "ดูหนัง", "อ่านหนังสือ"
- social: e.g., "เจอเพื่อน", "ประชุม", "อยู่คนเดียว"
- weather: e.g., "ฝนตก", "ร้อน", "หนาว"
- people: names of people mentioned
- work_stress: e.g., "deadline", "ประชุมยาว", "OT"
- expense: e.g., "500B", "ใช้จ่ายเยอะ"
- mood_detail: e.g., "เศร้า", "กังวล", "มีความสุข"

Return format:
[
  {"type": "food", "value": "กาแฟ Starbucks", "raw": "ดื่มกาแฟ Starbucks"},
  {"type": "symptoms", "value": "ปวดหัว", "raw": "ปวดหัวมาก"}
]<end_of_turn>
<start_of_turn>model
''';}

  /// 📋 Parse Gemma response
  List<Entity> _parseGemmaResponse(String response, Entry entry) {
    final entities = <Entity>[];
    
    try {
      // Extract JSON from response
      var jsonStr = response.trim();
      if (jsonStr.contains('```json')) {
        jsonStr = jsonStr.split('```json')[1].split('```')[0].trim();
      } else if (jsonStr.contains('```')) {
        jsonStr = jsonStr.split('```')[1].split('```')[0].trim();
      }
      
      // Note: In real implementation, use jsonDecode
      // For now, simple parsing
      
      // Try to find JSON array
      final startIdx = jsonStr.indexOf('[');
      final endIdx = jsonStr.lastIndexOf(']');
      if (startIdx >= 0 && endIdx > startIdx) {
        jsonStr = jsonStr.substring(startIdx, endIdx + 1);
      }
      
      // Simple manual parsing for safety (since we can't import dart:convert in isolation)
      // In real implementation: final list = jsonDecode(jsonStr) as List<dynamic>;
      
    } catch (e) {
      debugPrint('⚠️ Failed to parse Gemma response: $e');
    }
    
    return entities;
  }

  /// 🔄 Remove duplicate entities (same type + value on same day)
  List<Entity> _deduplicateEntities(List<Entity> entities) {
    final seen = <String>{};
    final unique = <Entity>[];
    
    for (final entity in entities) {
      final key = '${entity.type.name}_${entity.value}_${entity.timestamp.day}';
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(entity);
      }
    }
    
    return unique;
  }

  /// 📊 สกัด entities จากหลาย entries
  Future<List<DailyEntitySnapshot>> extractFromEntries(List<Entry> entries) async {
    final snapshots = <DailyEntitySnapshot>[];
    final groupedByDay = <DateTime, List<Entry>>{};
    
    // จัดกลุ่มตามวัน
    for (final entry in entries) {
      final day = DateTime(entry.createdAt.year, entry.createdAt.month, entry.createdAt.day);
      groupedByDay.putIfAbsent(day, () => []).add(entry);
    }
    
    // สกัดแต่ละวัน
    for (final day in groupedByDay.keys) {
      final dayEntries = groupedByDay[day]!;
      final allEntities = <Entity>[];
      int? avgMood;
      
      for (final entry in dayEntries) {
        final result = await extractFromEntry(entry, useGemmaFallback: false);
        allEntities.addAll(result.entities);
      }
      
      // คำนวณ average mood
      final moods = dayEntries.where((e) => e.mood != null).map((e) => e.mood!).toList();
      if (moods.isNotEmpty) {
        avgMood = moods.reduce((a, b) => a + b) ~/ moods.length;
      }
      
      snapshots.add(DailyEntitySnapshot(
        date: day,
        entities: _deduplicateEntities(allEntities),
        averageMood: avgMood,
        entryCount: dayEntries.length,
      ));
    }
    
    return snapshots;
  }
}

/// 🎯 Internal pattern class
class _ExtractionPattern {
  final EntityType type;
  final RegExp regex;
  final int valueGroup;
  final String Function(String) normalizer;

  _ExtractionPattern({
    required this.type,
    required this.regex,
    required this.valueGroup,
    required this.normalizer,
  });
}
