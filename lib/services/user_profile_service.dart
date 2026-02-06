import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🪪 User Profile Service - Identity Card
///
/// เก็บข้อมูลส่วนตัวที่ AI ต้องรู้ตลอดเวลา
/// ไม่ต้อง RAG เพราะ inject เข้า prompt เสมอ
///
/// Format: Lean Syntax เพื่อประหยัด Token
/// [Name:Arm|Job:Dev|Like:Coffee,Rock|Dislike:Spicy,Traffic]

class UserProfileService {
  static final UserProfileService _instance = UserProfileService._internal();
  factory UserProfileService() => _instance;
  UserProfileService._internal();

  static const String _profileKey = 'user_profile';
  static const String _factsKey = 'user_facts_queue';

  UserProfile _profile = UserProfile.empty();
  List<PendingFact> _pendingFacts = [];

  bool _isInitialized = false;

  // Getters
  UserProfile get profile => _profile;
  String get name => _profile.name;
  bool get hasProfile => _profile.name.isNotEmpty;

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadProfile();
    await _loadPendingFacts();

    _isInitialized = true;
    debugPrint('✅ User Profile Service initialized');
    debugPrint('   - Name: ${_profile.name.isEmpty ? "(not set)" : _profile.name}');
  }

  /// 📥 Load profile
  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_profileKey);

      if (json != null) {
        _profile = UserProfile.fromJson(jsonDecode(json));
      }
    } catch (e) {
      debugPrint('⚠️ Error loading profile: $e');
    }
  }

  /// 💾 Save profile
  Future<void> _saveProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileKey, jsonEncode(_profile.toJson()));
    } catch (e) {
      debugPrint('⚠️ Error saving profile: $e');
    }
  }

  /// 📥 Load pending facts
  Future<void> _loadPendingFacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_factsKey);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json);
        _pendingFacts = list.map((e) => PendingFact.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading facts: $e');
    }
  }

  /// 💾 Save pending facts
  Future<void> _savePendingFacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _factsKey,
        jsonEncode(_pendingFacts.map((f) => f.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving facts: $e');
    }
  }

  // ============================================================
  // 🪪 IDENTITY CARD (Lean Format)
  // ============================================================

  /// 🪪 Get Identity Card for Prompt (Lean Syntax)
  ///
  /// Output: [Name:Arm|Job:Dev|Like:Coffee,Rock|Dislike:Spicy]
  String getIdentityCard() {
    if (!hasProfile) return '';

    final parts = <String>[];

    if (_profile.name.isNotEmpty) {
      parts.add('Name:${_profile.name}');
    }
    if (_profile.nickname.isNotEmpty) {
      parts.add('Nick:${_profile.nickname}');
    }
    if (_profile.role.isNotEmpty) {
      parts.add('Job:${_profile.role}');
    }
    if (_profile.likes.isNotEmpty) {
      parts.add('Like:${_profile.likes.take(5).join(",")}');
    }
    if (_profile.dislikes.isNotEmpty) {
      parts.add('Dislike:${_profile.dislikes.take(5).join(",")}');
    }
    if (_profile.goals.isNotEmpty) {
      parts.add('Goal:${_profile.goals.take(3).join(",")}');
    }

    return '[${parts.join("|")}]';
  }

  /// 📊 Get Identity Card with Goals (for planning)
  String getIdentityCardFull() {
    final card = getIdentityCard();
    if (_profile.goals.isEmpty) return card;

    final goals = _profile.goals.map((g) => '• $g').join('\n');
    return '$card\n[Goals]\n$goals';
  }

  // ============================================================
  // ✏️ UPDATE PROFILE
  // ============================================================

  /// ✏️ Set basic info
  Future<void> setBasicInfo({
    String? name,
    String? nickname,
    String? role,
  }) async {
    _profile = _profile.copyWith(
      name: name,
      nickname: nickname,
      role: role,
    );
    await _saveProfile();
  }

  /// ➕ Add like
  Future<void> addLike(String item) async {
    if (_profile.likes.contains(item)) return;
    _profile = _profile.copyWith(
      likes: [..._profile.likes, item],
    );
    await _saveProfile();
    debugPrint('💚 Added like: $item');
  }

  /// ➕ Add dislike
  Future<void> addDislike(String item) async {
    if (_profile.dislikes.contains(item)) return;
    _profile = _profile.copyWith(
      dislikes: [..._profile.dislikes, item],
    );
    await _saveProfile();
    debugPrint('💔 Added dislike: $item');
  }

  /// ➕ Add goal
  Future<void> addGoal(String goal) async {
    if (_profile.goals.contains(goal)) return;
    _profile = _profile.copyWith(
      goals: [..._profile.goals, goal],
    );
    await _saveProfile();
    debugPrint('🎯 Added goal: $goal');
  }

  /// ➖ Remove like
  Future<void> removeLike(String item) async {
    _profile = _profile.copyWith(
      likes: _profile.likes.where((l) => l != item).toList(),
    );
    await _saveProfile();
  }

  /// ➖ Remove dislike
  Future<void> removeDislike(String item) async {
    _profile = _profile.copyWith(
      dislikes: _profile.dislikes.where((d) => d != item).toList(),
    );
    await _saveProfile();
  }

  /// ✅ Complete goal
  Future<void> completeGoal(String goal) async {
    _profile = _profile.copyWith(
      goals: _profile.goals.where((g) => g != goal).toList(),
      completedGoals: [..._profile.completedGoals, goal],
    );
    await _saveProfile();
    debugPrint('✅ Completed goal: $goal');
  }

  /// 🔄 Update full profile
  Future<void> updateProfile(UserProfile newProfile) async {
    _profile = newProfile;
    await _saveProfile();
  }

  // ============================================================
  // 🔍 AUTO-DETECT FACTS (Worker calls this)
  // ============================================================

  /// 📝 Queue fact for processing
  ///
  /// Worker จะเรียกเมื่อเจอ fact ใหม่จากการคุย
  void queueFact(PendingFact fact) {
    _pendingFacts.add(fact);
    _savePendingFacts();
    debugPrint('📝 Queued fact: ${fact.type} - ${fact.value}');
  }

  /// 🔄 Process pending facts (Worker calls this)
  Future<void> processPendingFacts() async {
    if (_pendingFacts.isEmpty) return;

    debugPrint('🔄 Processing ${_pendingFacts.length} pending facts...');

    for (final fact in _pendingFacts) {
      switch (fact.type) {
        case FactType.like:
          await addLike(fact.value);
          break;
        case FactType.dislike:
          await addDislike(fact.value);
          break;
        case FactType.goal:
          await addGoal(fact.value);
          break;
        case FactType.name:
          await setBasicInfo(name: fact.value);
          break;
        case FactType.nickname:
          await setBasicInfo(nickname: fact.value);
          break;
        case FactType.role:
          await setBasicInfo(role: fact.value);
          break;
      }
    }

    _pendingFacts.clear();
    await _savePendingFacts();
    debugPrint('✅ Processed all pending facts');
  }

  /// 🔍 Extract facts from text (simple keyword matching)
  ///
  /// Worker ใช้ LLM ในการ extract แต่นี่คือ fallback
  List<PendingFact> extractFactsSimple(String text) {
    final facts = <PendingFact>[];
    final lower = text.toLowerCase();

    // Detect likes
    final likePatterns = [
      RegExp(r'(?:ชอบ|รัก|ติดใจ)\s*(.+?)(?:\s|$|ครับ|ค่ะ|นะ)'),
    ];
    for (final pattern in likePatterns) {
      final match = pattern.firstMatch(lower);
      if (match != null) {
        facts.add(PendingFact(
          type: FactType.like,
          value: match.group(1)?.trim() ?? '',
          source: text,
        ));
      }
    }

    // Detect dislikes
    final dislikePatterns = [
      RegExp(r'(?:ไม่ชอบ|เกลียด|ไม่โอเค)\s*(.+?)(?:\s|$|ครับ|ค่ะ|นะ)'),
    ];
    for (final pattern in dislikePatterns) {
      final match = pattern.firstMatch(lower);
      if (match != null) {
        facts.add(PendingFact(
          type: FactType.dislike,
          value: match.group(1)?.trim() ?? '',
          source: text,
        ));
      }
    }

    // Detect name
    final namePatterns = [
      RegExp(r'(?:ชื่อ|เรียก(?:ว่า)?)\s*(.+?)(?:\s|$|ครับ|ค่ะ|นะ)'),
    ];
    for (final pattern in namePatterns) {
      final match = pattern.firstMatch(lower);
      if (match != null && _profile.name.isEmpty) {
        facts.add(PendingFact(
          type: FactType.name,
          value: match.group(1)?.trim() ?? '',
          source: text,
        ));
      }
    }

    return facts;
  }

  /// 🗑️ Clear profile
  Future<void> clearProfile() async {
    _profile = UserProfile.empty();
    _pendingFacts.clear();
    await _saveProfile();
    await _savePendingFacts();
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// 👤 User Profile
class UserProfile {
  final String name;
  final String nickname;
  final String role;
  final List<String> likes;
  final List<String> dislikes;
  final List<String> goals;
  final List<String> completedGoals;
  final Map<String, String> customFields;
  final DateTime updatedAt;

  UserProfile({
    required this.name,
    required this.nickname,
    required this.role,
    required this.likes,
    required this.dislikes,
    required this.goals,
    required this.completedGoals,
    required this.customFields,
    required this.updatedAt,
  });

  factory UserProfile.empty() => UserProfile(
        name: '',
        nickname: '',
        role: '',
        likes: [],
        dislikes: [],
        goals: [],
        completedGoals: [],
        customFields: {},
        updatedAt: DateTime.now(),
      );

  UserProfile copyWith({
    String? name,
    String? nickname,
    String? role,
    List<String>? likes,
    List<String>? dislikes,
    List<String>? goals,
    List<String>? completedGoals,
    Map<String, String>? customFields,
  }) {
    return UserProfile(
      name: name ?? this.name,
      nickname: nickname ?? this.nickname,
      role: role ?? this.role,
      likes: likes ?? this.likes,
      dislikes: dislikes ?? this.dislikes,
      goals: goals ?? this.goals,
      completedGoals: completedGoals ?? this.completedGoals,
      customFields: customFields ?? this.customFields,
      updatedAt: DateTime.now(),
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      role: json['role'] as String? ?? '',
      likes: List<String>.from(json['likes'] ?? []),
      dislikes: List<String>.from(json['dislikes'] ?? []),
      goals: List<String>.from(json['goals'] ?? []),
      completedGoals: List<String>.from(json['completedGoals'] ?? []),
      customFields: Map<String, String>.from(json['customFields'] ?? {}),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'nickname': nickname,
        'role': role,
        'likes': likes,
        'dislikes': dislikes,
        'goals': goals,
        'completedGoals': completedGoals,
        'customFields': customFields,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// 📝 Pending Fact (รอ Worker ประมวลผล)
class PendingFact {
  final FactType type;
  final String value;
  final String source;
  final DateTime createdAt;

  PendingFact({
    required this.type,
    required this.value,
    required this.source,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory PendingFact.fromJson(Map<String, dynamic> json) {
    return PendingFact(
      type: FactType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => FactType.like,
      ),
      value: json['value'] as String,
      source: json['source'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'value': value,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// 📋 Fact Type
enum FactType {
  like,
  dislike,
  goal,
  name,
  nickname,
  role,
}
