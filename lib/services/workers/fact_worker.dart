import 'package:flutter/foundation.dart';

import '../simple_vector_service.dart';
import '../user_profile_service.dart';

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
  final SimpleVectorService _vectorService = SimpleVectorService();

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

  /// ความชอบ
  static final List<RegExp> _likePatterns = [
    RegExp(r'(?:ฉัน|ผม|หนู|เรา)?ชอบ\s*(.+?)(?:มาก|สุด|$|ค่ะ|ครับ|นะ)', caseSensitive: false),
    RegExp(r'(?:ฉัน|ผม|หนู|เรา)?รัก\s*(.+?)(?:มาก|$|ค่ะ|ครับ)', caseSensitive: false),
    RegExp(r'(?:ฉัน|ผม|หนู)?ติดใจ\s*(.+?)(?:มาก|$|ค่ะ|ครับ)', caseSensitive: false),
    RegExp(r'(.+?)อร่อย(?:มาก)?(?:เลย)?', caseSensitive: false),
    RegExp(r'(.+?)ดี(?:มาก)?(?:เลย)?(?:จัง)?', caseSensitive: false),
  ];

  /// ไม่ชอบ
  static final List<RegExp> _dislikePatterns = [
    RegExp(r'(?:ฉัน|ผม|หนู)?ไม่ชอบ\s*(.+?)(?:\s|เลย|$|ค่ะ|ครับ)', caseSensitive: false),
    RegExp(r'(?:ฉัน|ผม|หนู)?เกลียด\s*(.+?)(?:\s|มาก|$)', caseSensitive: false),
    RegExp(r'(?:ฉัน|ผม)?ไม่โอเค(?:กับ)?\s*(.+?)(?:\s|$)', caseSensitive: false),
    RegExp(r'(.+?)ไม่อร่อย', caseSensitive: false),
  ];

  /// อาชีพ
  static final List<RegExp> _rolePatterns = [
    RegExp(r'(?:ฉัน|ผม|หนู)?(?:ทำงาน|เป็น)\s*(.+?)(?:\s|อยู่|ค่ะ|ครับ|$)', caseSensitive: false),
    RegExp(r'อาชีพ(?:ของฉัน)?(?:คือ)?\s*(.+?)(?:\s|ค่ะ|ครับ|$)', caseSensitive: false),
    RegExp(r'(?:ฉัน|ผม|หนู)?ทำ\s*(.+?)(?:อยู่)?(?:\s|ค่ะ|ครับ|$)', caseSensitive: false),
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

  /// สุขภาพ
  static final List<RegExp> _healthPatterns = [
    RegExp(r'เป็น(?:หวัด|ไข้|เมน|ประจำเดือน)', caseSensitive: false),
    RegExp(r'(?:ปวด|เจ็บ)\s*(.+?)(?:\s|มาก|$)', caseSensitive: false),
    RegExp(r'(?:ไม่สบาย|ป่วย)', caseSensitive: false),
    RegExp(r'แพ้\s*(.+?)(?:\s|$)', caseSensitive: false),
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
        debugPrint('🎯 FactWorker: Detected goal = $goal');
      }
    }

    // 7. ตรวจจับสถานที่ → บันทึกลง RAG
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
      debugPrint('📍 FactWorker: Detected place = ${place.name} (${place.sentiment})');
    }

    // 8. ตรวจจับสุขภาพ → บันทึกลง RAG
    final healthFacts = _extractHealth(message);
    for (final health in healthFacts) {
      facts.add(ExtractedFact(
        type: FactType.health,
        value: health.condition,
        confidence: 0.85,
        source: message,
        metadata: {'details': health.details},
      ));
      await _saveToRAG('health_log', health.condition, {
        'details': health.details,
        'date': DateTime.now().toIso8601String(),
      });
      debugPrint('🏥 FactWorker: Detected health = ${health.condition}');
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

    // เป็นเมน/ประจำเดือน
    if (text.contains('เป็นเมน') || text.contains('ประจำเดือน')) {
      health.add(HealthFact(condition: 'period', details: 'menstruation'));
    }

    // เป็นหวัด/ไข้
    if (text.contains('เป็นหวัด') || text.contains('เป็นไข้')) {
      health.add(HealthFact(condition: 'cold_flu', details: text.contains('ไข้') ? 'fever' : 'cold'));
    }

    // ปวด
    final painMatch = RegExp(r'ปวด\s*(\S+)').firstMatch(text);
    if (painMatch != null) {
      health.add(HealthFact(condition: 'pain', details: painMatch.group(1) ?? ''));
    }

    // แพ้
    final allergyMatch = RegExp(r'แพ้\s*(\S+)').firstMatch(text);
    if (allergyMatch != null) {
      health.add(HealthFact(condition: 'allergy', details: allergyMatch.group(1) ?? ''));
    }

    return health;
  }

  /// Clean extracted value
  String _cleanValue(String value) {
    return value
        .replaceAll(RegExp(r'[ครับค่ะนะจ้าจ๊ะเลย]+$'), '')
        .replaceAll(RegExp(r'^\s+|\s+$'), '')
        .trim();
  }

  // ============================================================
  // ✅ VALIDATION
  // ============================================================

  bool _isValidName(String name) {
    return name.length >= 2 &&
        name.length <= 30 &&
        !name.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
  }

  bool _isValidPreference(String pref) {
    return pref.length >= 2 &&
        pref.length <= 50 &&
        !pref.startsWith('ที่') &&
        !pref.startsWith('ว่า');
  }

  bool _isValidRole(String role) {
    return role.length >= 2 &&
        role.length <= 50 &&
        !role.startsWith('ที่');
  }

  bool _isValidGoal(String goal) {
    return goal.length >= 3 && goal.length <= 100;
  }

  // ============================================================
  // 💾 RAG STORAGE
  // ============================================================

  /// Save to RAG (Simple Vector)
  Future<void> _saveToRAG(
    String category,
    String content,
    Map<String, dynamic> metadata,
  ) async {
    try {
      await _vectorService.addEntry(
        content: content,
        metadata: {
          'category': category,
          ...metadata,
        },
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

/// Health fact
class HealthFact {
  final String condition;
  final String details;

  HealthFact({required this.condition, required this.details});
}
