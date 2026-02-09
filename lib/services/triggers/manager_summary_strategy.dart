import 'package:flutter/foundation.dart';

import '../lean_context_service.dart';
import '../unified_vector_service.dart';
import '../user_profile_service.dart';

/// 📊 Manager Summary Strategy - วิเคราะห์และจัดการ Daily Summary
///
/// ทำหน้าที่:
/// - อ่าน session summaries หลายวัน
/// - จับ patterns (สุขภาพ, พฤติกรรม)
/// - Dispatch งานไปยัง workers ที่เหมาะสม
/// - สร้าง insights และ recommendations
///
/// Workers:
/// - HealthDoctor: วิเคราะห์สุขภาพ
/// - CalendarWorker: คาดการณ์ตาราง
/// - FactWorker: บันทึกข้อมูลใหม่

class ManagerSummaryStrategy {
  final LeanContextService leanContext;
  final UnifiedVectorService vectorService;
  final UserProfileService userProfile;

  ManagerSummaryStrategy({
    required this.leanContext,
    required this.vectorService,
    required this.userProfile,
  });

  // ============================================================
  // 📊 MAIN ANALYSIS
  // ============================================================

  /// 📊 Run full analysis
  Future<ManagerSummaryResult> analyze() async {
    debugPrint('📊 ManagerSummaryStrategy: Starting analysis...');

    final insights = <Insight>[];
    final recommendations = <Recommendation>[];
    final workerTasks = <WorkerTask>[];

    // 1. Analyze health patterns
    final healthResult = await _analyzeHealth();
    insights.addAll(healthResult.insights);
    recommendations.addAll(healthResult.recommendations);
    workerTasks.addAll(healthResult.tasks);

    // 2. Analyze behavior patterns
    final behaviorResult = await _analyzeBehavior();
    insights.addAll(behaviorResult.insights);
    recommendations.addAll(behaviorResult.recommendations);

    // 3. Analyze preferences
    final prefResult = await _analyzePreferences();
    insights.addAll(prefResult.insights);
    workerTasks.addAll(prefResult.tasks);

    // 4. Generate summary
    final summary = _generateSummary(insights);

    debugPrint('✅ Analysis complete: ${insights.length} insights, ${recommendations.length} recommendations');

    return ManagerSummaryResult(
      summary: summary,
      insights: insights,
      recommendations: recommendations,
      workerTasks: workerTasks,
      analyzedAt: DateTime.now(),
    );
  }

  // ============================================================
  // 💊 HEALTH ANALYSIS
  // ============================================================

  Future<_AnalysisResult> _analyzeHealth() async {
    final insights = <Insight>[];
    final recommendations = <Recommendation>[];
    final tasks = <WorkerTask>[];

    // Get health facts from RAG
    final healthFacts = vectorService.getByCategory('health_log');

    // ตรวจจับ period pattern
    final periodFacts = healthFacts.where((f) =>
      f.metadata?['condition'] == 'period'
    ).toList();

    if (periodFacts.isNotEmpty) {
      final lastPeriod = periodFacts.last;
      final daysSince = DateTime.now().difference(lastPeriod.createdAt).inDays;

      insights.add(Insight(
        type: InsightType.health,
        title: 'Period Tracking',
        description: 'Last recorded: $daysSince days ago',
        severity: daysSince < 7 ? InsightSeverity.info : InsightSeverity.low,
        data: {'daysSince': daysSince},
      ));

      // ถ้าเพิ่งเริ่ม (1-3 วัน) → schedule health checks
      if (daysSince <= 3) {
        recommendations.add(Recommendation(
          type: RecommendationType.health,
          title: 'ติดตามอาการ',
          description: 'แนะนำให้ติดตามอาการทุกวันในช่วง 5 วันนี้',
          priority: RecommendationPriority.medium,
        ));

        tasks.add(WorkerTask(
          worker: WorkerType.reminder,
          action: 'schedule_daily_health_check',
          data: {
            'condition': 'period',
            'duration_days': 5,
            'message': 'วันนี้อาการเป็นไงบ้างคะ?',
          },
        ));
      }
    }

    // ตรวจจับ fatigue pattern
    final fatigueFacts = healthFacts.where((f) =>
      f.content.contains('เหนื่อย') || f.content.contains('tired')
    ).toList();

    if (fatigueFacts.length >= 3) {
      insights.add(Insight(
        type: InsightType.health,
        title: 'Fatigue Pattern',
        description: 'บันทึกความเหนื่อยล้า ${fatigueFacts.length} ครั้งในช่วงที่ผ่านมา',
        severity: InsightSeverity.medium,
      ));

      recommendations.add(Recommendation(
        type: RecommendationType.health,
        title: 'พักผ่อน',
        description: 'ลองหากิจกรรมผ่อนคลายดูนะคะ',
        priority: RecommendationPriority.medium,
      ));
    }

    return _AnalysisResult(
      insights: insights,
      recommendations: recommendations,
      tasks: tasks,
    );
  }

  // ============================================================
  // 📈 BEHAVIOR ANALYSIS
  // ============================================================

  Future<_AnalysisResult> _analyzeBehavior() async {
    final insights = <Insight>[];
    final recommendations = <Recommendation>[];

    // Get facts from RAG
    final allFacts = vectorService.facts;

    // ตรวจจับ favorite places
    final placeFacts = allFacts.where((f) =>
      f.metadata?['category'] == 'favorite_place'
    ).toList();

    if (placeFacts.isNotEmpty) {
      // Group by place name
      final placeCount = <String, int>{};
      for (final fact in placeFacts) {
        final name = fact.content;
        placeCount[name] = (placeCount[name] ?? 0) + 1;
      }

      // Find most visited
      final sortedPlaces = placeCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (sortedPlaces.isNotEmpty) {
        final topPlace = sortedPlaces.first;
        insights.add(Insight(
          type: InsightType.behavior,
          title: 'Favorite Place',
          description: 'ไปร้าน${topPlace.key}บ่อยสุด (${topPlace.value} ครั้ง)',
          severity: InsightSeverity.info,
          data: {'places': placeCount},
        ));
      }
    }

    // ตรวจจับ goals progress
    final goals = userProfile.profile.goals;
    final completedGoals = userProfile.profile.completedGoals;

    if (goals.isNotEmpty || completedGoals.isNotEmpty) {
      insights.add(Insight(
        type: InsightType.behavior,
        title: 'Goals Progress',
        description: 'เป้าหมายที่กำลังทำ: ${goals.length}, สำเร็จแล้ว: ${completedGoals.length}',
        severity: InsightSeverity.info,
        data: {
          'active': goals,
          'completed': completedGoals,
        },
      ));
    }

    return _AnalysisResult(
      insights: insights,
      recommendations: recommendations,
      tasks: [],
    );
  }

  // ============================================================
  // ❤️ PREFERENCES ANALYSIS
  // ============================================================

  Future<_AnalysisResult> _analyzePreferences() async {
    final insights = <Insight>[];
    final tasks = <WorkerTask>[];

    final profile = userProfile.profile;

    // Summarize preferences
    if (profile.likes.isNotEmpty || profile.dislikes.isNotEmpty) {
      insights.add(Insight(
        type: InsightType.preference,
        title: 'Preferences',
        description: 'ชอบ: ${profile.likes.take(3).join(", ")} | '
            'ไม่ชอบ: ${profile.dislikes.take(3).join(", ")}',
        severity: InsightSeverity.info,
        data: {
          'likes': profile.likes,
          'dislikes': profile.dislikes,
        },
      ));
    }

    // Check if we should recommend something based on preferences
    if (profile.likes.isNotEmpty) {
      tasks.add(WorkerTask(
        worker: WorkerType.fact,
        action: 'update_profile_summary',
        data: {
          'likes': profile.likes,
          'dislikes': profile.dislikes,
        },
      ));
    }

    return _AnalysisResult(
      insights: insights,
      recommendations: [],
      tasks: tasks,
    );
  }

  // ============================================================
  // 📝 SUMMARY GENERATION
  // ============================================================

  String _generateSummary(List<Insight> insights) {
    if (insights.isEmpty) {
      return 'No significant patterns detected.';
    }

    final buffer = StringBuffer();

    // Group by type
    final byType = <InsightType, List<Insight>>{};
    for (final insight in insights) {
      byType.putIfAbsent(insight.type, () => []).add(insight);
    }

    // Generate summary for each type
    if (byType.containsKey(InsightType.health)) {
      buffer.write('Health: ');
      buffer.write(byType[InsightType.health]!.map((i) => i.title).join(', '));
      buffer.write('. ');
    }

    if (byType.containsKey(InsightType.behavior)) {
      buffer.write('Behavior: ');
      buffer.write(byType[InsightType.behavior]!.map((i) => i.title).join(', '));
      buffer.write('. ');
    }

    if (byType.containsKey(InsightType.preference)) {
      buffer.write('Preferences noted. ');
    }

    return buffer.toString().trim();
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

class _AnalysisResult {
  final List<Insight> insights;
  final List<Recommendation> recommendations;
  final List<WorkerTask> tasks;

  _AnalysisResult({
    required this.insights,
    required this.recommendations,
    required this.tasks,
  });
}

/// Manager summary result
class ManagerSummaryResult {
  final String summary;
  final List<Insight> insights;
  final List<Recommendation> recommendations;
  final List<WorkerTask> workerTasks;
  final DateTime analyzedAt;

  ManagerSummaryResult({
    required this.summary,
    required this.insights,
    required this.recommendations,
    required this.workerTasks,
    required this.analyzedAt,
  });

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'insights': insights.map((i) => i.toJson()).toList(),
    'recommendations': recommendations.map((r) => r.toJson()).toList(),
    'workerTasks': workerTasks.map((t) => t.toJson()).toList(),
    'analyzedAt': analyzedAt.toIso8601String(),
  };
}

/// Insight type
enum InsightType {
  health,
  behavior,
  preference,
  pattern,
}

/// Insight severity
enum InsightSeverity {
  info,
  low,
  medium,
  high,
}

/// Insight
class Insight {
  final InsightType type;
  final String title;
  final String description;
  final InsightSeverity severity;
  final Map<String, dynamic>? data;

  Insight({
    required this.type,
    required this.title,
    required this.description,
    required this.severity,
    this.data,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'title': title,
    'description': description,
    'severity': severity.name,
    'data': data,
  };
}

/// Recommendation type
enum RecommendationType {
  health,
  activity,
  goal,
  social,
}

/// Recommendation priority
enum RecommendationPriority {
  low,
  medium,
  high,
}

/// Recommendation
class Recommendation {
  final RecommendationType type;
  final String title;
  final String description;
  final RecommendationPriority priority;
  final Map<String, dynamic>? data;

  Recommendation({
    required this.type,
    required this.title,
    required this.description,
    required this.priority,
    this.data,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'title': title,
    'description': description,
    'priority': priority.name,
    'data': data,
  };
}

/// Worker type
enum WorkerType {
  fact,
  calendar,
  reminder,
  health,
}

/// Worker task
class WorkerTask {
  final WorkerType worker;
  final String action;
  final Map<String, dynamic>? data;

  WorkerTask({
    required this.worker,
    required this.action,
    this.data,
  });

  Map<String, dynamic> toJson() => {
    'worker': worker.name,
    'action': action,
    'data': data,
  };
}
