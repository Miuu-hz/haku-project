import 'dart:async';

import 'package:flutter/foundation.dart';

import '../unified_vector_service.dart';
import '../user_profile_service.dart';
import '../wiki_service.dart';
import 'health_doctor.dart' show HealthFact, HealthFactType;

/// 📝 Fact Worker - ตรวจจับและบันทึกข้อมูลจากการสนทนา
///
/// ทำงานแบบ Rule-based (0 LLM tokens)
///
/// ตรวจจับ:
/// - ชื่อ/ชื่อเล่น
/// - ความชอบ/ไม่ชอบ
/// - อาชีพ/งาน
/// - เป้าหมาย
/// - สถานที่โปรด
/// - ข้อมูลสุขภาพ

class FactWorker {
  static final FactWorker _instance = FactWorker._internal();
  factory FactWorker() => _instance;
  FactWorker._internal();

  final UserProfileService _userProfile = UserProfileService();
  final UnifiedVectorService _vectorService = UnifiedVectorService();

  // ============================================================
  // 🔍 DETECTION PATTERNS
  // ============================================================

  /// ชื่อ
  static final List<RegExp> _namePatterns = [
    RegExp(r'(?:ฉัน|ผม|หนู)ชื่อ\s*(.+?)(?:\s|นะ|ค่ะ|ครับ|จ้า|$)', caseSensitive: false),
    RegExp(r'ชื่อ(?:ของ)?(?:ฉัน|ผม|หนู)(?:คือ)?\s*(.+?)(?:\s|นะ|ค่ะ|ครับ|$)', caseSensitive: false),
    RegExp(r'เรียก(?:ฉัน|ผม|หนู)ว่า\s*(.+?)(?:\s|นะ|ค่ะ|ครับ|ได้|$)', caseSensitive: false),
  ];

  /// ชื่อเล่น
  static final List<RegExp> _nicknamePatterns = [
    RegExp(r'ชื่อเล่น(?:คือ|ว่า)?\s*(.+?)(?:\s|นะ|ค่ะ|ครับ|$)', caseSensitive: false),
    RegExp(r'เรียกสั้นๆ?\s*(?:ว่า)?\s*(.+?)(?:\s|ก็ได้|นะ|$)', caseSensitive: false),
  ];

  /// ความชอบ (ต้องมี subject + object ชัดเจน เพื่อกัน false positive)
  static final List<RegExp> _likePatterns = [
    RegExp(r'(?:ฉัน|ผม|หนู|เรา)ชอบ\s*(.+?)(?:มาก|สุด|ค่ะ|ครับ|นะ|$)', caseSensitive: false),
    RegExp(r'(?:ฉัน|ผม|หนู|เรา)รัก\s*(.+?)(?:มาก|ค่ะ|ครับ|$)', caseSensitive: false),
    RegExp(r'(?:ฉัน|ผม|หนู)ติดใจ\s*(.+?)(?:มาก|ค่ะ|ครับ|$)', caseSensitive: false),
    RegExp(r'(?:ร้าน|อาหาร|เมนู)\s*(.+?)\s*อร่อย(?:มาก)?', caseSensitive: false),
  ];

  /// ไม่ชอบ
  static final List<RegExp> _dislikePatterns = [
    RegExp(r'(?:ฉัน|ผม|หนู)?ไม่ชอบ\s*(.+?)(?:\s|เลย|$|ค่ะ|ครับ)', caseSensitive: false),
    RegExp(r'(?:ฉัน|ผม|หนู)?เกลียด\s*(.+?)(?:\s|มาก|$)', caseSensitive: false),
    RegExp(r'(?:ฉัน|ผม)?ไม่โอเค(?:กับ)?\s*(.+?)(?:\s|$)', caseSensitive: false),
    RegExp(r'(.+?)ไม่อร่อย', caseSensitive: false),
  ];

  /// อาชีพ (subject pronoun บังคับ เพื่อกัน false positive)
  static final List<RegExp> _rolePatterns = [
    RegExp(r'(?:ฉัน|ผม|หนู)(?:ทำงาน|เป็น)\s*(.+?)(?:\s|อยู่|ค่ะ|ครับ|$)', caseSensitive: false),
    RegExp(r'อาชีพ(?:ของฉัน)?(?:คือ)?\s*(.+?)(?:\s|ค่ะ|ครับ|$)', caseSensitive: false),
    RegExp(r'(?:ฉัน|ผม|หนู)ทำ\s*(.+?)(?:อยู่)?(?:\s|ค่ะ|ครับ|$)', caseSensitive: false),
  ];

  /// เป้าหมาย
  static final List<RegExp> _goalPatterns = [
    RegExp(r'(?:อยาก|ตั้งใจ)(?:จะ)?\s*(.+?)(?:\s|ให้ได้|$|ค่ะ|ครับ)', caseSensitive: false),
    RegExp(r'เป้าหมาย(?:คือ)?\s*(.+?)(?:\s|$)', caseSensitive: false),
    RegExp(r'ฝัน(?:อยาก)?\s*(.+?)(?:\s|$)', caseSensitive: false),
  ];

  /// สถานที่
  static final List<RegExp> _placePatterns = [
    RegExp(r'ร้าน\s*(.+?)\s*(?:อร่อย|ดี|โอเค|ชอบ)', caseSensitive: false),
    RegExp(r'ไป\s*(?:ร้าน)?\s*(.+?)\s*(?:มา|แล้ว)', caseSensitive: false),
    RegExp(r'ที่\s*(.+?)\s*(?:ดี|สวย|ชอบ)', caseSensitive: false),
  ];

  // ============================================================
  // 🚀 MAIN PROCESSING
  // ============================================================

  /// 🔍 Process message and extract facts
  Future<List<ExtractedFact>> processMessage(String message) async {
    final facts = <ExtractedFact>[];

    // 1. ตรวจจับชื่อ
    final name = _extractFirst(_namePatterns, message);
    if (name != null && _isValidName(name)) {
      facts.add(ExtractedFact(
        type: FactType.name,
        value: name,
        confidence: 0.9,
        source: message,
      ));
      await _userProfile.setBasicInfo(name: name);
      unawaited(WikiService().onNewFact(category: 'person', key: name, content: 'Name: $name'));
      debugPrint('📝 FactWorker: Detected name = $name');
    }

    // 2. ตรวจจับชื่อเล่น
    final nickname = _extractFirst(_nicknamePatterns, message);
    if (nickname != null && _isValidName(nickname)) {
      facts.add(ExtractedFact(
        type: FactType.nickname,
        value: nickname,
        confidence: 0.85,
        source: message,
      ));
      await _userProfile.setBasicInfo(nickname: nickname);
      unawaited(WikiService().onNewFact(category: 'person', key: nickname, content: 'Nickname: $nickname'));
      debugPrint('📝 FactWorker: Detected nickname = $nickname');
    }

    // 3. ตรวจจับความชอบ
    final likes = _extractAll(_likePatterns, message);
    for (final like in likes) {
      if (_isValidPreference(like)) {
        facts.add(ExtractedFact(
          type: FactType.like,
          value: like,
          confidence: 0.8,
          source: message,
        ));
        await _userProfile.addLike(like);
        unawaited(WikiService().onNewFact(category: 'preference', key: like, content: 'Likes: $like'));
        debugPrint('💚 FactWorker: Detected like = $like');
      }
    }

    // 4. ตรวจจับไม่ชอบ
    final dislikes = _extractAll(_dislikePatterns, message);
    for (final dislike in dislikes) {
      if (_isValidPreference(dislike)) {
        facts.add(ExtractedFact(
          type: FactType.dislike,
          value: dislike,
          confidence: 0.8,
          source: message,
        ));
        await _userProfile.addDislike(dislike);
        unawaited(WikiService().onNewFact(category: 'preference', key: dislike, content: 'Dislikes: $dislike'));
        debugPrint('💔 FactWorker: Detected dislike = $dislike');
      }
    }

    // 5. ตรวจจับอาชีพ
    final role = _extractFirst(_rolePatterns, message);
    if (role != null && _isValidRole(role)) {
      facts.add(ExtractedFact(
        type: FactType.role,
        value: role,
        confidence: 0.85,
        source: message,
      ));
      await _userProfile.setBasicInfo(role: role);
      unawaited(WikiService().onNewFact(category: 'person', key: 'self', content: 'Role: $role'));
      debugPrint('💼 FactWorker: Detected role = $role');
    }

    // 6. ตรวจจับเป้าหมาย
    final goals = _extractAll(_goalPatterns, message);
    for (final goal in goals) {
      if (_isValidGoal(goal)) {
        facts.add(ExtractedFact(
          type: FactType.goal,
          value: goal,
          confidence: 0.75,
          source: message,
        ));
        await _userProfile.addGoal(goal);
        unawaited(WikiService().onNewFact(category: 'goal', key: goal.substring(0, goal.length.clamp(0, 40)), content: 'Goal: $goal'));
        debugPrint('🎯 FactWorker: Detected goal = $goal');
      }
    }

    // 7. ตรวจจับสถานที่ → บันทึกลง RAG + Wiki
    final places = _extractPlaces(message);
    for (final place in places) {
      facts.add(ExtractedFact(
        type: FactType.place,
        value: place.name,
        confidence: 0.7,
        source: message,
        metadata: {'sentiment': place.sentiment},
      ));
      await _saveToRAG('favorite_place', place.name, {
        'sentiment': place.sentiment,
        'source': message,
        'date': DateTime.now().toIso8601String(),
      });
      unawaited(WikiService().onNewFact(category: 'place', key: place.name, content: '${place.name} (${place.sentiment})'));
      debugPrint('📍 FactWorker: Detected place = ${place.name} (${place.sentiment})');
    }

    // 8. ตรวจจับสุขภาพ → บันทึกลง RAG + Wiki
    final healthFacts = _extractHealth(message);
    for (final health in healthFacts) {
      facts.add(ExtractedFact(
        type: FactType.health,
        value: health.value,
        confidence: 0.85,
        source: message,
        metadata: {'type': health.type.name, 'date': health.date.toIso8601String()},
      ));
      await _saveToRAG('health_log', health.value, {
        'type': health.type.name,
        'date': health.date.toIso8601String(),
      });
      unawaited(WikiService().onNewFact(category: 'health', key: health.type.name, content: health.value));
      debugPrint('🏥 FactWorker: Detected health = ${health.value}');
    }

    return facts;
  }

  // ============================================================
  // 🔧 EXTRACTION HELPERS
  // ============================================================

  /// Extract first match
  String? _extractFirst(List<RegExp> patterns, String text) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount > 0) {
        final value = match.group(1)?.trim();
        if (value != null && value.isNotEmpty) {
          return _cleanValue(value);
        }
      }
    }
    return null;
  }

  /// Extract all matches
  List<String> _extractAll(List<RegExp> patterns, String text) {
    final results = <String>{};
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        if (match.groupCount > 0) {
          final value = match.group(1)?.trim();
          if (value != null && value.isNotEmpty) {
            results.add(_cleanValue(value));
          }
        }
      }
    }
    return results.toList();
  }

  /// Extract places with sentiment
  List<PlaceFact> _extractPlaces(String text) {
    final places = <PlaceFact>[];

    for (final pattern in _placePatterns) {
      for (final match in pattern.allMatches(text)) {
        if (match.groupCount > 0) {
          final name = match.group(1)?.trim();
          if (name != null && name.isNotEmpty && name.length > 2) {
            // Determine sentiment from context
            String sentiment = 'neutral';
            if (text.contains('อร่อย') || text.contains('ชอบ') || text.contains('ดี')) {
              sentiment = 'positive';
            } else if (text.contains('ไม่อร่อย') || text.contains('ไม่ดี')) {
              sentiment = 'negative';
            }

            places.add(PlaceFact(name: _cleanValue(name), sentiment: sentiment));
          }
        }
      }
    }

    return places;
  }

  /// Extract health info
  List<HealthFact> _extractHealth(String text) {
    final health = <HealthFact>[];
    final now = DateTime.now();

    // เป็นเมน/ประจำเดือน
    if (text.contains('เป็นเมน') || text.contains('ประจำเดือน')) {
      health.add(HealthFact(type: HealthFactType.period, value: 'menstruation', date: now));
    }

    // เป็นหวัด/ไข้
    if (text.contains('เป็นหวัด') || text.contains('เป็นไข้')) {
      health.add(HealthFact(
        type: HealthFactType.symptom,
        value: text.contains('ไข้') ? 'fever' : 'cold',
        date: now,
      ));
    }

    // ปวด
    final painMatch = RegExp(r'ปวด\s*(\S+)').firstMatch(text);
    if (painMatch != null) {
      health.add(HealthFact(
        type: HealthFactType.symptom,
        value: 'pain_${painMatch.group(1) ?? 'general'}',
        date: now,
      ));
    }

    // แพ้
    final allergyMatch = RegExp(r'แพ้\s*(\S+)').firstMatch(text);
    if (allergyMatch != null) {
      health.add(HealthFact(
        type: HealthFactType.allergy,
        value: allergyMatch.group(1) ?? '',
        date: now,
      ));
    }

    return health;
  }

  /// Clean extracted value (ใช้ whole-word เพื่อไม่ strip อักษรที่ไม่เกี่ยว)
  String _cleanValue(String value) => value
      .replaceAll(RegExp(r'(?:ครับ|ค่ะ|นะ|จ้า|จ๊ะ|เลย|ค่ะ)+$'), '')
      .replaceAll(RegExp(r'^\s+|\s+$'), '')
      .trim();

  // ============================================================
  // ✅ VALIDATION
  // ============================================================

  bool _isValidName(String name) => name.length >= 2 &&
      name.length <= 30 &&
      !name.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

  bool _isValidPreference(String pref) => pref.length >= 3 &&
      pref.length <= 50 &&
      !pref.startsWith('ที่') &&
      !pref.startsWith('ว่า') &&
      !pref.contains('อะไร') &&
      !pref.contains('อะไ') &&
      !pref.contains('ไหม') &&
      !pref.contains('หรือ');

  bool _isValidRole(String role) => role.length >= 2 &&
      role.length <= 50 &&
      !role.startsWith('ที่');

  bool _isValidGoal(String goal) {
    return goal.length >= 4 &&
        goal.length <= 100 &&
        !goal.contains('อะไร') &&
        !goal.contains('คุณ') &&
        !goal.contains('ไหม') &&
        !goal.contains('หรือ') &&
        !goal.contains('ได้บ้าง');
  }

  // ============================================================
  // 💾 RAG STORAGE
  // ============================================================

  /// Save to RAG (Unified Vector)
  Future<void> _saveToRAG(
    String category,
    String content,
    Map<String, dynamic> metadata,
  ) async {
    try {
      await _vectorService.addFact(
        category: category,
        content: content,
        metadata: metadata,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to save to RAG: $e');
    }
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// Fact type enum
enum FactType {
  name,
  nickname,
  like,
  dislike,
  role,
  goal,
  place,
  health,
}

/// Extracted fact
class ExtractedFact {
  final FactType type;
  final String value;
  final double confidence;
  final String source;
  final Map<String, dynamic>? metadata;
  final DateTime extractedAt;

  ExtractedFact({
    required this.type,
    required this.value,
    required this.confidence,
    required this.source,
    this.metadata,
  }) : extractedAt = DateTime.now();

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'value': value,
    'confidence': confidence,
    'source': source,
    'metadata': metadata,
    'extractedAt': extractedAt.toIso8601String(),
  };
}

/// Place fact with sentiment
class PlaceFact {
  final String name;
  final String sentiment; // positive, negative, neutral

  PlaceFact({required this.name, required this.sentiment});
}

// HealthFact is imported from health_doctor.dart
