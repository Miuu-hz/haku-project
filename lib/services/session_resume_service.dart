// Session Resume Service
//
// สร้าง session resume context เมื่อเริ่ม session ใหม่
// ดึงข้อมูลจาก: top facts + recent episodic log + calendar events
// inject เป็น system instruction → Haku จำได้แม้ลบแชท

import 'package:flutter/foundation.dart';

import 'database_helper.dart';
import 'scheduler_service.dart';
import 'unified_vector_service.dart';

class SessionResumeService {
  static final SessionResumeService _instance = SessionResumeService._();
  SessionResumeService._();
  factory SessionResumeService() => _instance;

  final _db = DatabaseHelper.instance;
  final _vectors = UnifiedVectorService();

  /// สร้าง resume string สำหรับ inject ใน system instruction
  ///
  /// ตัวอย่าง output:
  /// [RESUME] ชอบกาแฟดำ. ทำงานเป็น developer. เป้าหมาย: ออกกำลังกายทุกวัน.
  /// [CALENDAR] วันนี้: ประชุม 14:00. พรุ่งนี้: หมอ 09:00.
  /// [RECENT] สัปดาห์นี้คุยเรื่อง project deadline + เครียดงาน.
  Future<String> buildResume() async {
    final parts = <String>[];

    try {
      // ── 1. Top facts (Semantic Memory) ─────────────────────────────
      final factPart = await _buildFactSummary();
      if (factPart.isNotEmpty) parts.add('[RESUME] $factPart');

      // ── 2. Calendar (today + tomorrow) ─────────────────────────────
      final calPart = await _buildCalendarSummary();
      if (calPart.isNotEmpty) parts.add('[CALENDAR] $calPart');

      // ── 3. Recent episodic log (last 3 significant exchanges) ──────
      final recentPart = await _buildRecentSummary();
      if (recentPart.isNotEmpty) parts.add('[RECENT] $recentPart');
    } catch (e) {
      debugPrint('⚠️ SessionResumeService.buildResume failed: $e');
    }

    return parts.join(' ');
  }

  // ── Private builders ───────────────────────────────────────────────

  Future<String> _buildFactSummary() async {
    try {
      await _vectors.initialize();
      final facts = List<VectorItem>.from(_vectors.facts);
      if (facts.isEmpty) return '';

      // เรียง: category สำคัญก่อน (name/job/goal) แล้วตามด้วยใหม่กว่า
      const priority = ['name', 'job', 'goal', 'preference', 'health'];
      facts.sort((VectorItem a, VectorItem b) {
        final aIdx = priority.indexOf((a.metadata?['category'] as String?) ?? '');
        final bIdx = priority.indexOf((b.metadata?['category'] as String?) ?? '');
        if (aIdx != bIdx) {
          return (aIdx < 0 ? 99 : aIdx).compareTo(bIdx < 0 ? 99 : bIdx);
        }
        return b.createdAt.compareTo(a.createdAt);
      });

      // เก็บแค่ 5 facts แรก ≈ 100-150 tokens
      final top = facts.take(5).map((VectorItem f) => f.content).join('. ');
      return top;
    } catch (e) {
      debugPrint('⚠️ _buildFactSummary: $e');
      return '';
    }
  }

  Future<String> _buildCalendarSummary() async {
    try {
      final scheduler = SchedulerService();
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final tomorrowEnd = todayStart.add(const Duration(days: 2));

      final events = await scheduler.getCalendarEvents(todayStart, tomorrowEnd);
      if (events.isEmpty) return '';

      final todayEnd = todayStart.add(const Duration(days: 1));
      final todayEvents = events.where((e) {
        final ms = e['dtstart'] as int?;
        if (ms == null) return false;
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        return dt.isBefore(todayEnd);
      }).toList();

      final tomorrowEvents = events.where((e) {
        final ms = e['dtstart'] as int?;
        if (ms == null) return false;
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        return dt.isAfter(todayEnd) || dt.isAtSameMomentAs(todayEnd);
      }).toList();

      final parts = <String>[];

      if (todayEvents.isNotEmpty) {
        final items = todayEvents.take(3).map((e) {
          final title = e['title'] as String? ?? 'นัด';
          final ms = e['dtstart'] as int?;
          if (ms == null) return title;
          final dt = DateTime.fromMillisecondsSinceEpoch(ms);
          return '$title ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
        }).join(', ');
        parts.add('วันนี้: $items');
      }

      if (tomorrowEvents.isNotEmpty) {
        final items = tomorrowEvents.take(2).map((e) {
          final title = e['title'] as String? ?? 'นัด';
          final ms = e['dtstart'] as int?;
          if (ms == null) return title;
          final dt = DateTime.fromMillisecondsSinceEpoch(ms);
          return '$title ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
        }).join(', ');
        parts.add('พรุ่งนี้: $items');
      }

      return parts.join('. ');
    } catch (e) {
      // Calendar permission อาจไม่ได้รับ → silent fail
      debugPrint('⚠️ _buildCalendarSummary: $e');
      return '';
    }
  }

  Future<String> _buildRecentSummary() async {
    try {
      final rows = await _db.getRecentChatLog(limit: 5);
      if (rows.isEmpty) return '';

      // กรอง intent ที่มีความหมาย (ข้าม pure chat)
      final significant = rows.where((r) {
        final intent = r['intent'] as String? ?? 'chat';
        return intent != 'chat';
      }).take(3).toList();

      if (significant.isEmpty) {
        // fallback: เอา 2 รายการล่าสุด
        final fallback = rows.take(2).toList();
        return fallback.map((r) => r['summary_en'] as String? ?? '').join('. ');
      }

      return significant.map((r) => r['summary_en'] as String? ?? '').join('. ');
    } catch (e) {
      debugPrint('⚠️ _buildRecentSummary: $e');
      return '';
    }
  }

  /// ตรวจว่า event ใกล้เกิดขึ้น (<2 ชม.) หรือไม่ — สำหรับ urgent flag
  Future<bool> hasUrgentEvent() async {
    try {
      final scheduler = SchedulerService();
      final now = DateTime.now();
      final soon = now.add(const Duration(hours: 2));
      final events = await scheduler.getCalendarEvents(now, soon);
      return events.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
