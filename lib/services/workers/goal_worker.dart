import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../unified_vector_service.dart';
import '../user_profile_service.dart';

/// 🎯 Goal Worker - ตรวจจับและติดตามเป้าหมาย
///
/// ตรวจจับ:
/// - "อยากออกกำลัง 3 วัน/สัปดาห์"
/// - "ตั้งใจอ่านหนังสือ"
/// - "เป้าหมายลดน้ำหนัก 5 กก."
///
/// Output format: [Goal:ออกกำลัง,3d/w]

class GoalWorker {
  static final GoalWorker _instance = GoalWorker._internal();
  factory GoalWorker() => _instance;
  GoalWorker._internal();

  static const String _goalsKey = 'goals_data';

  final UnifiedVectorService _vectorService = UnifiedVectorService();
  final UserProfileService _userProfile = UserProfileService();
  final List<Goal> _goals = [];
  bool _isInitialized = false;

  // ============================================================
  // 🔍 DETECTION PATTERNS
  // ============================================================

  /// เป้าหมาย
  static final List<RegExp> _goalPatterns = [
    RegExp(r'(?:อยาก|ต้องการ|ตั้งใจ)(?:จะ)?\s*(.+?)(?:\s|$|ครับ|ค่ะ)', caseSensitive: false),
    RegExp(r'เป้าหมาย(?:คือ)?\s*(.+?)(?:\s|$|ครับ|ค่ะ)', caseSensitive: false),
    RegExp(r'ฝัน(?:อยาก)?\s*(.+?)(?:\s|$)', caseSensitive: false),
  ];

  /// ความถี่/ปริมาณ
  static final RegExp _frequencyPattern = RegExp(
    r'(\d+)\s*(วัน|ครั้ง|ชม\.|ชั่วโมง|กก\.|กิโล|kg|km|กม\.?)\s*(?:ต่อ|/)\s*(วัน|สัปดาห์|เดือน|week|day|month)',
    caseSensitive: false,
  );

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadGoals();
    _isInitialized = true;
    debugPrint('✅ GoalWorker initialized: ${_goals.length} goals');
  }

  Future<void> _loadGoals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_goalsKey);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _goals.clear();
        _goals.addAll(
          list.map((e) => Goal.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error loading goals: $e');
    }
  }

  Future<void> _saveGoals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _goalsKey,
        jsonEncode(_goals.map((g) => g.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving goals: $e');
    }
  }

  // ============================================================
  // 🔍 DETECTION
  // ============================================================

  /// ตรวจจับ goals จากข้อความ
  Future<List<Goal>> detectGoals(String message) async {
    final goals = <Goal>[];

    for (final pattern in _goalPatterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        final goal = _parseGoal(match.group(1) ?? '', message);
        if (goal != null) {
          goals.add(goal);
          await addGoal(goal);
        }
      }
    }

    return goals;
  }

  Goal? _parseGoal(String content, String originalMessage) {
    content = content.replaceAll(RegExp(r'[ครับค่ะนะ]+$'), '').trim();
    if (content.isEmpty || content.length < 3) return null;

    // Parse target (frequency/amount)
    GoalTarget? target;
    final freqMatch = _frequencyPattern.firstMatch(originalMessage);
    if (freqMatch != null) {
      final amount = int.tryParse(freqMatch.group(1) ?? '0') ?? 0;
      final unit = freqMatch.group(2) ?? '';
      final period = freqMatch.group(3) ?? '';

      target = GoalTarget(
        amount: amount,
        unit: _normalizeUnit(unit),
        period: _normalizePeriod(period),
      );
    }

    // Determine category
    final category = _detectCategory(content);

    return Goal(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: content,
      category: category,
      target: target,
      progress: 0,
      status: GoalStatus.active,
      createdAt: DateTime.now(),
    );
  }

  String _normalizeUnit(String unit) {
    final normalized = unit.toLowerCase();
    if (normalized.contains('วัน') || normalized.contains('day')) return 'days';
    if (normalized.contains('ครั้ง')) return 'times';
    if (normalized.contains('ชม') || normalized.contains('ชั่วโมง')) return 'hours';
    if (normalized.contains('กก') || normalized.contains('kg')) return 'kg';
    if (normalized.contains('กม') || normalized.contains('km')) return 'km';
    return unit;
  }

  String _normalizePeriod(String period) {
    final normalized = period.toLowerCase();
    if (normalized.contains('วัน') || normalized.contains('day')) return 'day';
    if (normalized.contains('สัปดาห์') || normalized.contains('week')) return 'week';
    if (normalized.contains('เดือน') || normalized.contains('month')) return 'month';
    return period;
  }

  GoalCategory _detectCategory(String content) {
    final lower = content.toLowerCase();

    if (lower.contains('ออกกำลัง') || lower.contains('วิ่ง') || lower.contains('exercise')) {
      return GoalCategory.fitness;
    }
    if (lower.contains('อ่าน') || lower.contains('เรียน') || lower.contains('learn')) {
      return GoalCategory.learning;
    }
    if (lower.contains('ลดน้ำหนัก') || lower.contains('สุขภาพ') || lower.contains('กิน')) {
      return GoalCategory.health;
    }
    if (lower.contains('เงิน') || lower.contains('ออม') || lower.contains('save')) {
      return GoalCategory.finance;
    }
    if (lower.contains('งาน') || lower.contains('โปรเจค') || lower.contains('work')) {
      return GoalCategory.career;
    }

    return GoalCategory.personal;
  }

  // ============================================================
  // 📝 GOAL MANAGEMENT
  // ============================================================

  /// เพิ่ม goal
  Future<void> addGoal(Goal goal) async {
    _goals.add(goal);
    await _saveGoals();

    // Also save to UserProfile
    await _userProfile.addGoal(goal.title);

    // Save to RAG for long-term analysis
    final targetStr = goal.target != null
        ? '${goal.target!.amount} ${goal.target!.unit}/${goal.target!.period}'
        : 'no target';
    await _vectorService.addFact(
      category: 'goal',
      content: '${goal.category.name}: ${goal.title} ($targetStr)',
      metadata: goal.toJson(),
    );

    debugPrint('🎯 GoalWorker: Added - ${goal.title}');
  }

  /// อัพเดต progress
  Future<void> updateProgress(String id, int progress) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index >= 0) {
      _goals[index] = _goals[index].copyWith(progress: progress);

      // Check if completed
      if (_goals[index].target != null && progress >= _goals[index].target!.amount) {
        _goals[index] = _goals[index].copyWith(status: GoalStatus.completed);
      }

      await _saveGoals();
    }
  }

  /// Log progress (increment)
  Future<void> logProgress(String id, {int amount = 1}) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index >= 0) {
      final newProgress = _goals[index].progress + amount;
      await updateProgress(id, newProgress);
      debugPrint('🎯 GoalWorker: Progress logged for ${_goals[index].title}: $newProgress');
    }
  }

  /// Complete goal
  Future<void> completeGoal(String id) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index >= 0) {
      _goals[index] = _goals[index].copyWith(
        status: GoalStatus.completed,
        completedAt: DateTime.now(),
      );
      await _saveGoals();

      // Update UserProfile
      await _userProfile.completeGoal(_goals[index].title);

      // Log completion to RAG for long-term analysis
      await _vectorService.addFact(
        category: 'goal_completed',
        content: 'Completed goal: ${_goals[index].title}',
        metadata: _goals[index].toJson(),
      );

      debugPrint('✅ GoalWorker: Completed - ${_goals[index].title}');
    }
  }

  /// Pause goal
  Future<void> pauseGoal(String id) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index >= 0) {
      _goals[index] = _goals[index].copyWith(status: GoalStatus.paused);
      await _saveGoals();
    }
  }

  /// Resume goal
  Future<void> resumeGoal(String id) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index >= 0) {
      _goals[index] = _goals[index].copyWith(status: GoalStatus.active);
      await _saveGoals();
    }
  }

  /// Delete goal
  Future<void> deleteGoal(String id) async {
    _goals.removeWhere((g) => g.id == id);
    await _saveGoals();
  }

  // ============================================================
  // 📋 GETTERS
  // ============================================================

  /// Get active goals
  List<Goal> get activeGoals {
    return _goals.where((g) => g.status == GoalStatus.active).toList();
  }

  /// Get completed goals
  List<Goal> get completedGoals {
    return _goals.where((g) => g.status == GoalStatus.completed).toList();
  }

  /// Get all goals
  List<Goal> get allGoals => List.unmodifiable(_goals);

  /// Get goals by category
  List<Goal> getGoalsByCategory(GoalCategory category) {
    return _goals.where((g) => g.category == category).toList();
  }

  // ============================================================
  // 📦 LEAN FORMAT
  // ============================================================

  /// Get lean format for context
  String getLeanFormat() {
    final active = activeGoals;
    if (active.isEmpty) return '';

    final parts = active.take(3).map((g) {
      if (g.target != null) {
        return '${g.title},${g.progress}/${g.target!.amount}${g.target!.unit}/${g.target!.period}';
      }
      return g.title;
    }).toList();

    return '[Goal:${parts.join(";")}]';
  }

  /// Get progress summary
  String getProgressSummary() {
    final active = activeGoals;
    final completed = completedGoals;

    return 'Goals: ${active.length} active, ${completed.length} completed';
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

enum GoalCategory {
  fitness,
  health,
  learning,
  finance,
  career,
  personal,
}

extension GoalCategoryExtension on GoalCategory {
  String get displayName {
    switch (this) {
      case GoalCategory.fitness: return 'ออกกำลังกาย';
      case GoalCategory.health: return 'สุขภาพ';
      case GoalCategory.learning: return 'การเรียนรู้';
      case GoalCategory.finance: return 'การเงิน';
      case GoalCategory.career: return 'การงาน';
      case GoalCategory.personal: return 'ส่วนตัว';
    }
  }

  String get emoji {
    switch (this) {
      case GoalCategory.fitness: return '🏃';
      case GoalCategory.health: return '💪';
      case GoalCategory.learning: return '📚';
      case GoalCategory.finance: return '💰';
      case GoalCategory.career: return '💼';
      case GoalCategory.personal: return '⭐';
    }
  }
}

enum GoalStatus {
  active,
  paused,
  completed,
  abandoned,
}

class GoalTarget {
  final int amount;
  final String unit;
  final String period;

  GoalTarget({
    required this.amount,
    required this.unit,
    required this.period,
  });

  factory GoalTarget.fromJson(Map<String, dynamic> json) => GoalTarget(
    amount: json['amount'] as int,
    unit: json['unit'] as String,
    period: json['period'] as String,
  );

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'unit': unit,
    'period': period,
  };

  @override
  String toString() => '$amount $unit/$period';
}

class Goal {
  final String id;
  final String title;
  final GoalCategory category;
  final GoalTarget? target;
  final int progress;
  final GoalStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;

  Goal({
    required this.id,
    required this.title,
    required this.category,
    this.target,
    required this.progress,
    required this.status,
    required this.createdAt,
    this.completedAt,
  });

  Goal copyWith({
    String? title,
    GoalCategory? category,
    GoalTarget? target,
    int? progress,
    GoalStatus? status,
    DateTime? completedAt,
  }) => Goal(
    id: id,
    title: title ?? this.title,
    category: category ?? this.category,
    target: target ?? this.target,
    progress: progress ?? this.progress,
    status: status ?? this.status,
    createdAt: createdAt,
    completedAt: completedAt ?? this.completedAt,
  );

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: json['id'] as String,
    title: json['title'] as String,
    category: GoalCategory.values.firstWhere(
      (c) => c.name == json['category'],
      orElse: () => GoalCategory.personal,
    ),
    target: json['target'] != null
        ? GoalTarget.fromJson(json['target'] as Map<String, dynamic>)
        : null,
    progress: json['progress'] as int? ?? 0,
    status: GoalStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => GoalStatus.active,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    completedAt: json['completedAt'] != null
        ? DateTime.parse(json['completedAt'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category.name,
    'target': target?.toJson(),
    'progress': progress,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  String toDisplayString() {
    final buffer = StringBuffer('${category.emoji} $title');
    if (target != null) {
      buffer.write(' ($progress/${target!.amount} ${target!.unit})');
    }
    return buffer.toString();
  }

  double get progressPercent {
    if (target == null) return 0;
    return (progress / target!.amount).clamp(0, 1);
  }
}
