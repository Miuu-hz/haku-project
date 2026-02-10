import 'package:flutter/foundation.dart';

import '../../models/correlation_models.dart';
import '../battery_aware_service.dart';
import '../correlation_service.dart';
import '../insight_notification_service.dart';

/// 🔮 Correlation Worker - ทำงานวิเคราะห์ correlation ผ่าน UnifiedTaskService
///
/// เรียกใช้เมื่อ:
/// - ชาร์จแบต (ChargingTrigger)
/// - ผู้ใช้กด "วิเคราะห์เลย"
/// - Background task ตามเวลา

class CorrelationWorker {
  static final CorrelationWorker _instance = CorrelationWorker._internal();
  factory CorrelationWorker() => _instance;
  CorrelationWorker._internal();

  final CorrelationService _correlationService = CorrelationService();
  final InsightNotificationService _notificationService = InsightNotificationService();
  final BatteryAwareService _battery = BatteryAwareService();

  /// กำลังทำงานอยู่หรือไม่
  bool get isWorking => _correlationService.isAnalyzing;

  // ============================================================
  // 🎯 MAIN WORK METHODS
  // ============================================================

  /// 🔮 วิเคราะห์ correlation (แบบเต็ม)
  /// 
  /// ใช้เมื่อชาร์จแบต หรือผู้ใช้กดวิเคราะห์เอง
  Future<CorrelationAnalysisResult?> runFullAnalysis({bool notifyNewInsights = true}) async {
    // ตรวจสอบแบตเตอรี่ (ต้องชาร์จ หรือ แบต > 30%)
    if (!_canRunHeavyAnalysis()) {
      debugPrint('🔋 Battery too low for correlation analysis');
      return null;
    }

    debugPrint('🔮 CorrelationWorker: Starting full analysis...');

    try {
      final result = await _correlationService.analyzeCorrelations(
        daysBack: 30,
        minSampleSize: 5,
        useGemmaSummary: true,
      );

      debugPrint('✅ CorrelationWorker: Found ${result.insights.length} insights');

      // แจ้งเตือน insights ใหม่
      if (notifyNewInsights && result.insights.isNotEmpty) {
        await _notificationService.checkAndNotifyNewInsights(result);
      }

      return result;

    } catch (e, stackTrace) {
      debugPrint('❌ CorrelationWorker error: $e');
      debugPrint('Stack: $stackTrace');
      return null;
    }
  }

  /// ⚡ วิเคราะห์แบบเร็ว (Quick Analysis)
  /// 
  /// ใช้สำหรับ preview หรือ background check
  Future<CorrelationAnalysisResult?> runQuickAnalysis({bool notifyNewInsights = false}) async {
    debugPrint('⚡ CorrelationWorker: Starting quick analysis...');

    try {
      final result = await _correlationService.quickAnalyze();
      debugPrint('✅ Quick analysis: ${result.insights.length} insights');

      // Quick analysis ไม่ notify ปกติ (ยกเว้น health insights สำคัญ)
      if (notifyNewInsights && result.insights.isNotEmpty) {
        await _notificationService.checkAndNotifyNewInsights(result);
      }

      return result;

    } catch (e) {
      debugPrint('⚠️ Quick analysis failed: $e');
      return null;
    }
  }

  /// 🔍 ค้นหา insights ที่เกี่ยวข้อง
  Future<List<CorrelationInsight>> findInsights(String query) async {
    return await _correlationService.findRelatedInsights(query);
  }

  /// 📊 ดึง insights ที่น่าสนใจสุด
  Future<List<CorrelationInsight>> getTopInsights({int limit = 5}) async {
    // ดึงจาก RAG ทั้งหมดแล้วเรียงตาม confidence
    final allInsights = await _correlationService.findRelatedInsights('');
    
    allInsights.sort((a, b) => 
        (b.confidence * b.correlation.abs()).compareTo(a.confidence * a.correlation.abs()));
    
    return allInsights.take(limit).toList();
  }

  /// 🏥 ดึง health-related insights
  Future<List<CorrelationInsight>> getHealthInsights() async {
    final allInsights = await _correlationService.findRelatedInsights('symptom health ปวด ไข้');
    
    return allInsights
        .where((i) => 
            i.entityAType == EntityType.symptoms || 
            i.entityBType == EntityType.symptoms)
        .toList();
  }

  /// 😊 ดึง mood-related insights
  Future<List<CorrelationInsight>> getMoodInsights() async {
    final allInsights = await _correlationService.findRelatedInsights('mood happy สุข เศร้า');
    
    return allInsights
        .where((i) => 
            i.entityAType == EntityType.mood || 
            i.entityBType == EntityType.mood)
        .toList();
  }

  // ============================================================
  // 🔋 BATTERY AWARENESS
  // ============================================================

  /// ตรวจสอบว่าควรรัน analysis หรือไม่
  bool _canRunHeavyAnalysis() {
    // ถ้ากำลังชาร์จ → รันได้
    if (_battery.isChargingOrFull) return true;
    
    // ถ้าแบต > 30% → รันได้
    if (_battery.batteryLevel > 30) return true;
    
    return false;
  }

  /// ตรวจสอบว่าควร deferred ไปทำตอนชาร์จหรือไม่
  bool shouldDeferAnalysis() {
    return !_battery.isChargingOrFull && _battery.batteryLevel < 50;
  }

  // ============================================================
  // 🧹 MAINTENANCE
  // ============================================================

  /// ล้าง insights เก่า
  Future<void> clearOldInsights() async {
    await _correlationService.clearAllInsights();
    debugPrint('🧹 Cleared all insights');
  }

  /// ดึงสถิติ
  Future<Map<String, dynamic>> getStats() async {
    return await _correlationService.getStats();
  }

  // ============================================================
  // 📱 WIDGET DATA
  // ============================================================

  /// สร้างข้อมูลสำหรับ Widget (แสดง insight เด่น)
  Future<Map<String, dynamic>?> getWidgetData() async {
    final insights = await getTopInsights(limit: 3);
    if (insights.isEmpty) return null;

    final topInsight = insights.first;
    
    return {
      'title': 'ความเชื่อมโยงที่พบ',
      'mainInsight': topInsight.description,
      'correlation': topInsight.correlation,
      'confidence': topInsight.confidence,
      'entityA': topInsight.entityAValue,
      'entityB': topInsight.entityBValue,
      'insightCount': insights.length,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
  }

  /// สร้าง notification message
  Future<String?> getNotificationMessage() async {
    final insights = await getTopInsights(limit: 1);
    if (insights.isEmpty) return null;

    final insight = insights.first;
    final recommendation = insight.getRecommendation();
    
    if (recommendation != null) {
      return '💡 $recommendation';
    }

    return '🔮 ค้นพบ: ${insight.description.substring(0, insight.description.length > 100 ? 100 : insight.description.length)}...';
  }
}
