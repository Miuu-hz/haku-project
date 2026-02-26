import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🔥 Streak Service - ติดตาม streak การ Focus รายวัน
///
/// SharedPreferences keys:
///   'focus_streak_count'     → int  (จำนวนวันติดต่อ)
///   'focus_streak_last_date' → ISO string (วันที่ทำ session ล่าสุด)
///   'focus_total_sessions'   → int  (ยอดรวม session ทั้งหมด)

class StreakService {
  static final StreakService _instance = StreakService._internal();
  factory StreakService() => _instance;
  StreakService._internal();

  static const String _streakCountKey = 'focus_streak_count';
  static const String _lastDateKey = 'focus_streak_last_date';
  static const String _totalSessionsKey = 'focus_total_sessions';

  int _currentStreak = 0;
  int _totalSessions = 0;
  DateTime? _lastSessionDate;
  bool _isInitialized = false;

  int get currentStreak => _currentStreak;
  int get totalSessions => _totalSessions;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    _currentStreak = prefs.getInt(_streakCountKey) ?? 0;
    _totalSessions = prefs.getInt(_totalSessionsKey) ?? 0;

    final lastDateStr = prefs.getString(_lastDateKey);
    if (lastDateStr != null) {
      _lastSessionDate = DateTime.tryParse(lastDateStr);
    }

    await _checkAndResetIfMissedDay(prefs);
    _isInitialized = true;
    debugPrint('🔥 StreakService initialized: streak=$_currentStreak total=$_totalSessions');
  }

  /// รีเซ็ต streak ถ้าข้ามวันมา (ไม่ได้ทำเมื่อวาน)
  Future<void> _checkAndResetIfMissedDay(SharedPreferences prefs) async {
    if (_lastSessionDate == null) return;

    final today = _toDay(DateTime.now());
    final lastDay = _toDay(_lastSessionDate!);
    final diff = today.difference(lastDay).inDays;

    if (diff > 1) {
      _currentStreak = 0;
      await prefs.setInt(_streakCountKey, 0);
      debugPrint('🔥 Streak reset — missed ${diff - 1} day(s)');
    }
  }

  /// บันทึก session เสร็จ 1 ครั้ง — คืน streak ใหม่
  Future<int> recordSession() async {
    if (!_isInitialized) await initialize();

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = _toDay(now);

    // เพิ่ม streak เฉพาะถ้ายังไม่ได้บันทึกวันนี้
    if (_lastSessionDate == null || _toDay(_lastSessionDate!) != today) {
      _currentStreak++;
      await prefs.setInt(_streakCountKey, _currentStreak);
    }

    _totalSessions++;
    _lastSessionDate = now;
    await prefs.setInt(_totalSessionsKey, _totalSessions);
    await prefs.setString(_lastDateKey, now.toIso8601String());

    debugPrint('🔥 Streak: $_currentStreak days | Total: $_totalSessions sessions');
    return _currentStreak;
  }

  /// ตรวจว่า streak นี้ถึง milestone ไหม → คืน label หรือ null
  String? getMilestone(int streak) {
    if (streak == 7) return '7 วัน! 🔥';
    if (streak == 30) return '30 วัน! 🏆';
    if (streak == 100) return '100 วัน! 💎';
    return null;
  }

  DateTime _toDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
}
