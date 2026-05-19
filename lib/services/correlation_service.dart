import '../models/entry.dart';
import 'database_helper.dart';

/// 🔍 Correlation Service — หา pattern ซ่อนในชีวิต (Feature 3.1)
///
/// Algorithm: Co-occurrence analysis + Lift scoring (ไม่ใช้ LLM)
/// Input : SQLite entries (content, mood, createdAt)
/// Output: CorrelationInsight list เรียงตาม confidence
///
/// ตัวอย่าง: "73% ของวันอารมณ์ไม่ดี มักเกิดขึ้นในวันที่มีประชุม/meeting"

class CorrelationService {
  static final CorrelationService _instance = CorrelationService._();
  factory CorrelationService() => _instance;
  CorrelationService._();

  // ─── Signal Dictionary (keyword groups → label) ────────────────
  static const Map<String, List<String>> _signals = {
    'กาแฟ/คาเฟอีน': ['กาแฟ', 'coffee', 'cafe', 'คาเฟอีน', 'caffeine', 'ชาเขียว'],
    'นอนดึก/ง่วง':  ['นอนดึก', 'ตีสี่', 'ตีห้า', 'ดึก', 'ง่วง', 'นอนไม่หลับ', 'sleepy'],
    'เครียด':        ['เครียด', 'stressed', 'กดดัน', 'pressure', 'วิตก', 'anxiety'],
    'ประชุม/สังคม': ['ประชุม', 'meeting', 'สังสรรค์', 'งานเลี้ยง', 'party', 'event'],
    'ปวดหัว':        ['ปวดหัว', 'headache', 'migraine', 'หัวปวด'],
    'ออกกำลังกาย':  ['ออกกำลังกาย', 'วิ่ง', 'gym', 'exercise', 'workout', 'yoga'],
    'อาหารไม่ดี':   ['ของทอด', 'junk', 'fast food', 'ฟาสต์ฟู้ด', 'กึ่งสำเร็จ'],
  };

  // ─── Public API ────────────────────────────────────────────────

  /// วิเคราะห์ correlation จาก entries ทั้งหมด
  /// คืน list เรียงตาม confidence สูงสุด 5 รายการ
  Future<List<CorrelationInsight>> analyze({int maxEntries = 300}) async {
    final entries = await DatabaseHelper.instance.getAllEntries(limit: maxEntries);
    if (entries.length < 7) return []; // ข้อมูลน้อยเกินไป

    final insights = <CorrelationInsight>[];

    // Outcome 1: อารมณ์ไม่ดี (mood ≤ 2)
    final lowMood = entries.where((e) => e.mood != null && e.mood! <= 2).toSet();
    insights.addAll(_findCorrelations(entries, lowMood, 'วันอารมณ์ไม่ดี'));

    // Outcome 2: รู้สึกเหนื่อย (keyword-based)
    final fatigue = entries
        .where((e) => _hasAny(e.content, ['เหนื่อย', 'เพลีย', 'tired', 'exhausted', 'หมดแรง']))
        .toSet();
    insights.addAll(_findCorrelations(entries, fatigue, 'วันที่รู้สึกเหนื่อย'));

    // Outcome 3: อารมณ์ดี (mood ≥ 4) — หา positive correlations
    final highMood = entries.where((e) => e.mood != null && e.mood! >= 4).toSet();
    insights.addAll(_findCorrelations(entries, highMood, 'วันอารมณ์ดี', positive: true));

    // Dedup + sort
    final seen = <String>{};
    final deduped = insights.where((i) => seen.add('${i.outcomeLabel}|${i.signalKey}')).toList();
    deduped.sort((a, b) => b.confidence.compareTo(a.confidence));
    return deduped.take(5).toList();
  }

  // ─── Internal ──────────────────────────────────────────────────

  List<CorrelationInsight> _findCorrelations(
    List<Entry> entries,
    Set<Entry> outcomeSet,
    String outcomeLabel, {
    bool positive = false,
  }) {
    if (outcomeSet.length < 3) return []; // outcome พบน้อยเกินไป

    final pOutcome = outcomeSet.length / entries.length;
    final results = <CorrelationInsight>[];

    for (final sig in _signals.entries) {
      final withSignal = entries.where((e) => _hasAny(e.content, sig.value)).toList();
      if (withSignal.length < 3) continue; // signal พบน้อยเกินไป

      final hits = withSignal.where((e) => outcomeSet.contains(e)).length;
      if (hits < 2) continue;

      final pGiven = hits / withSignal.length;
      final lift   = pGiven - pOutcome;
      if (lift < 0.20) continue; // ต้องสูงกว่า baseline อย่างน้อย +20pp

      results.add(CorrelationInsight(
        outcomeLabel: outcomeLabel,
        signalKey:    sig.key,
        confidence:   pGiven,
        lift:         lift,
        sampleSize:   withSignal.length,
        hitCount:     hits,
        isPositive:   positive,
        message: _message(outcomeLabel, sig.key, (pGiven * 100).round()),
      ));
    }
    return results;
  }

  bool _hasAny(String text, List<String> keywords) {
    final lower = text.toLowerCase();
    return keywords.any((k) => lower.contains(k.toLowerCase()));
  }

  String _message(String outcome, String signal, int pct) =>
      '$pct% ของ$outcome มักเกิดขึ้นในวันที่มี$signal';
}

// ─── Data Model ───────────────────────────────────────────────────

class CorrelationInsight {
  final String outcomeLabel; // e.g. "วันอารมณ์ไม่ดี"
  final String signalKey;   // e.g. "กาแฟ/คาเฟอีน"
  final double confidence;  // P(outcome | signal)   0.0–1.0
  final double lift;        // confidence – P(outcome overall)
  final int sampleSize;     // จำนวน entries ที่มี signal
  final int hitCount;       // จำนวนที่ outcome เกิดพร้อม signal
  final bool isPositive;    // true = positive correlation (ดี)
  final String message;     // ข้อความภาษาไทยสำหรับแสดงผล

  const CorrelationInsight({
    required this.outcomeLabel,
    required this.signalKey,
    required this.confidence,
    required this.lift,
    required this.sampleSize,
    required this.hitCount,
    required this.isPositive,
    required this.message,
  });
}
