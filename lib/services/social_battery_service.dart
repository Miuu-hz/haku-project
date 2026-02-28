import '../models/entry.dart';
import 'database_helper.dart';

/// ⚡ Social Battery Service — พยากรณ์พลังงานสังคม (Feature 3.2)
///
/// Energy Cost Model (rule-based, ไม่ใช้ LLM):
///   Draining keywords  → ลด score
///   Recharging keywords → เพิ่ม score
///   mood 1-2           → ลดเพิ่ม, mood 4-5 → เพิ่มเพิ่ม
///
/// Output: level 0–100, trend, message, topDrains

class SocialBatteryService {
  static final SocialBatteryService _instance = SocialBatteryService._();
  factory SocialBatteryService() => _instance;
  SocialBatteryService._();

  // ─── Energy Cost Table ─────────────────────────────────────────
  static const Map<String, List<String>> _drainingKw = {
    'ประชุม/meeting': ['ประชุม', 'meeting', 'conference', 'บรีฟ', 'debrief'],
    'งานสังคม':      ['สังสรรค์', 'งานเลี้ยง', 'party', 'event', 'งานแต่ง', 'งานเลี้ยง'],
    'เครียด/กดดัน':  ['เครียด', 'stressed', 'กดดัน', 'pressure', 'วิตก'],
    'วุ่นวาย/เร่งด่วน': ['วุ่นวาย', 'ยุ่ง', 'เร่ง', 'deadline', 'ด่วน', 'rush'],
  };

  static const Map<String, List<String>> _rechargingKw = {
    'อยู่คนเดียว':   ['คนเดียว', 'alone', 'โซโล', 'เงียบ', 'ส่วนตัว'],
    'พัก/นอน':      ['นอน', 'พัก', 'rest', 'sleep', 'ผ่อนคลาย', 'relax'],
    'อ่านหนังสือ':   ['อ่านหนังสือ', 'อ่านหนัง', 'read', 'podcast'],
    'ออกกำลังกาย':  ['ออกกำลังกาย', 'วิ่ง', 'gym', 'exercise', 'workout', 'yoga'],
  };

  static const Map<String, int> _drainCost = {
    'ประชุม/meeting':     -10,
    'งานสังคม':          -14,
    'เครียด/กดดัน':      -10,
    'วุ่นวาย/เร่งด่วน': -8,
  };

  static const Map<String, int> _rechargeCost = {
    'อยู่คนเดียว':  12,
    'พัก/นอน':     10,
    'อ่านหนังสือ': 8,
    'ออกกำลังกาย': 8,
  };

  // ─── Public API ────────────────────────────────────────────────

  Future<SocialBatteryResult> analyze({int days = 14}) async {
    final since  = DateTime.now().subtract(Duration(days: days));
    final all    = await DatabaseHelper.instance.getAllEntries(limit: 300);
    final recent = all.where((e) => e.createdAt.isAfter(since)).toList();

    if (recent.isEmpty) {
      return const SocialBatteryResult(
        level: 60,
        trend: BatteryTrend.stable,
        message: 'ยังไม่มีข้อมูลเพียงพอ',
        topDrains: [],
      );
    }

    // คำนวณ total energy score
    int totalScore = 0;
    final drainCounts = <String, int>{};

    for (final entry in recent) {
      final text = entry.content.toLowerCase();
      int entryScore = 0;

      for (final d in _drainingKw.entries) {
        if (d.value.any((k) => text.contains(k))) {
          entryScore += _drainCost[d.key]!;
          drainCounts[d.key] = (drainCounts[d.key] ?? 0) + 1;
        }
      }
      for (final r in _rechargingKw.entries) {
        if (r.value.any((k) => text.contains(k))) {
          entryScore += _rechargeCost[r.key]!;
        }
      }

      // mood bonus/penalty
      if (entry.mood != null) {
        if (entry.mood! >= 4) entryScore += 3;
        if (entry.mood! <= 2) entryScore -= 4;
      }
      totalScore += entryScore;
    }

    // scale → 0–100 (baseline 60, ≈20 pts/day max)
    final raw   = 60 + (totalScore / (days * 0.8)).round();
    final level = raw.clamp(0, 100);

    // คำนวณ trend (7 วันล่าสุด vs 7 วันก่อนหน้า)
    final trend = _calcTrend(recent);

    // top drains
    final sortedDrains = drainCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topDrains = sortedDrains.take(2).map((e) => e.key).toList();

    return SocialBatteryResult(
      level:     level,
      trend:     trend,
      message:   _buildMessage(level, trend, topDrains),
      topDrains: topDrains,
    );
  }

  // ─── Internal ──────────────────────────────────────────────────

  BatteryTrend _calcTrend(List<Entry> recent) {
    final mid = DateTime.now().subtract(const Duration(days: 7));

    final recentHalf = recent.where((e) => e.createdAt.isAfter(mid))
        .where((e) => e.mood != null).toList();
    final olderHalf  = recent.where((e) => e.createdAt.isBefore(mid))
        .where((e) => e.mood != null).toList();

    if (recentHalf.isEmpty || olderHalf.isEmpty) return BatteryTrend.stable;

    final avgRecent = recentHalf.fold<double>(0, (s, e) => s + e.mood!) / recentHalf.length;
    final avgOlder  = olderHalf.fold<double>(0, (s, e) => s + e.mood!) / olderHalf.length;
    final diff = avgRecent - avgOlder;

    if (diff >  0.5) return BatteryTrend.recharging;
    if (diff < -0.5) return BatteryTrend.draining;
    return BatteryTrend.stable;
  }

  String _buildMessage(int level, BatteryTrend trend, List<String> drains) {
    if (level >= 75) return 'พลังงานสังคมเต็ม! พร้อมรับมือทุกอย่าง 💪';
    if (level >= 55) {
      if (trend == BatteryTrend.draining && drains.isNotEmpty) {
        return '${drains.first}ดูดพลังไปเยอะ ลองหาเวลาพักคนเดียวบ้างนะ';
      }
      return 'พลังงานสังคมอยู่ในระดับดี สม่ำเสมอ';
    }
    if (level >= 35) return 'พลังงานสังคมเริ่มลด ลองพักผ่อนอยู่บ้านสักวัน 🧘';
    return 'พลังงานสังคมต่ำมาก ควรพักอยู่คนเดียวสักช่วง 🏠';
  }
}

// ─── Data Models ──────────────────────────────────────────────────

enum BatteryTrend { draining, stable, recharging }

class SocialBatteryResult {
  final int level;           // 0–100
  final BatteryTrend trend;
  final String message;      // Thai explanation
  final List<String> topDrains;

  const SocialBatteryResult({
    required this.level,
    required this.trend,
    required this.message,
    required this.topDrains,
  });
}
