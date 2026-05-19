// 🏷️ Tag Context Service
//
// สองหน้าที่:
// 1. buildContext()       — ก่อน Face LLM: ดึง related past entries มาเป็น context
// 2. saveTagsToRecent()   — หลัง logExchange: บันทึก AI-extracted tags+location ลง SQLite

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'database_helper.dart';
import 'secret_chat_service.dart';

class TagContextService {
  static final TagContextService _instance = TagContextService._();
  TagContextService._();
  factory TagContextService() => _instance;

  final _db = DatabaseHelper.instance;

  // ── ก่อน Face LLM ─────────────────────────────────────────────────────────

  /// 🏷️ ดึง context จาก past entries ที่เกี่ยวข้องกับ userMessage
  ///
  /// ใช้ summaryEn (จาก PreClassify) หรือ userMessage เป็น keyword source
  /// ค้นหาจาก 2 แหล่ง: SecretChat log (recent) + SQLite entries (journal)
  /// คืน null ถ้าไม่พบอะไรเลย (ไม่เพิ่ม noise ให้ context)
  Future<String?> buildContext({
    required String userMessage,
    String? summaryEn,
    String? location,
  }) async {
    try {
      // สกัด keywords จาก summaryEn (มีความหมายกว่า userMessage ไทย)
      final queryText =
          (summaryEn?.isNotEmpty == true) ? summaryEn! : userMessage;
      final keywords = _extractKeywords(queryText);

      if (keywords.isEmpty && (location == null || location.isEmpty)) {
        return null;
      }

      // ค้นหาจาก 2 แหล่งพร้อมกัน
      final results = await Future.wait([
        _buildFromChatLog(keywords, location),
        _buildFromSQLite(keywords, location),
      ]);

      final parts = results.whereType<String>().toList();
      if (parts.isEmpty) return null;

      return 'Past related:\n${parts.join('\n')}';
    } catch (e) {
      debugPrint('⚠️ TagContextService.buildContext failed: $e');
      return null;
    }
  }

  // ── หลัง logExchange ───────────────────────────────────────────────────────

  /// 🏷️ บันทึก AI-extracted tags + location ลง SQLite entry ล่าสุด
  ///
  /// ตรวจสอบว่า entry นั้นสร้างภายใน 60 วินาทีที่ผ่านมา
  /// ก่อน merge เพื่อป้องกันการ tag entry ผิดตัว
  Future<void> saveTagsToRecentEntry(EnglishLogEntry logEntry) async {
    if (logEntry.tags.isEmpty && logEntry.location == null) return;
    try {
      final recent = await _db.getAllEntries(limit: 1);
      if (recent.isEmpty) return;

      final entry = recent.first;
      final age = DateTime.now().difference(entry.createdAt);
      // ถ้า entry เก่ากว่า 60 วิ — ไม่ใช่ entry ที่เพิ่งสร้างจาก chat นี้
      if (age.inSeconds > 60) return;

      await _db.mergeEntryTagsAndLocation(
        entry.id!,
        logEntry.tags,
        logEntry.location,
      );
      debugPrint(
          '🏷️ Auto-tagged entry #${entry.id}: ${logEntry.tags} @ ${logEntry.location}');
    } catch (e) {
      debugPrint('⚠️ TagContextService.saveTagsToRecentEntry failed: $e');
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<String?> _buildFromChatLog(
      List<String> keywords, String? location) async {
    // ลอง FTS5 ก่อน — เร็วและ ranked
    if (keywords.isNotEmpty) {
      final query = keywords.take(3).join(' OR ');
      final rows = await _db.searchChatFTS(query, limit: 3);
      if (rows.isNotEmpty) {
        return rows.map((r) {
          final ts = DateTime.tryParse(r['timestamp'] as String? ?? '');
          final d = ts ?? DateTime.now();
          final loc = r['location'] as String?;
          final mood = r['mood'] as int?;
          final locStr = (loc != null && loc.isNotEmpty) ? ' @$loc' : '';
          final moodStr = mood != null ? ' mood:$mood' : '';
          return '[${d.day}/${d.month}]$locStr$moodStr ${r['summary_en']}';
        }).join('\n');
      }
    }

    // fallback: in-memory linear scan (ก่อนที่ SQLite จะ populate)
    final log = SecretChatService().getRecentLog(limit: 40);
    final related = log.where((e) {
      final text = '${e.summaryEn} ${e.tags.join(' ')}'.toLowerCase();
      final tagMatch = keywords.any((k) => text.contains(k.toLowerCase()));
      final locMatch = location != null &&
          location.isNotEmpty &&
          e.location != null &&
          e.location!.toLowerCase().contains(location.toLowerCase());
      return tagMatch || locMatch;
    }).take(3).toList();

    if (related.isEmpty) return null;

    return related.map((e) {
      final d = e.timestamp;
      final locStr = e.location != null ? ' @${e.location}' : '';
      final moodStr = e.mood != null ? ' mood:${e.mood}' : '';
      return '[${d.day}/${d.month}]$locStr$moodStr ${e.summaryEn}';
    }).join('\n');
  }

  Future<String?> _buildFromSQLite(
      List<String> keywords, String? location) async {
    final entries = await _db.findRelatedEntries(
      tags: keywords,
      location: location,
      limit: 3,
    );
    if (entries.isEmpty) return null;

    final fmt = DateFormat('d/M');
    return entries.map((e) {
      final dateStr = fmt.format(e.createdAt);
      final locStr =
          e.locationName != null ? ' @${e.locationName}' : '';
      final tagStr =
          e.tags.isNotEmpty ? ' [${e.tags.take(3).join(',')}]' : '';
      final preview =
          e.content.substring(0, e.content.length.clamp(0, 60)).trim();
      return '[$dateStr]$locStr$tagStr $preview';
    }).join('\n');
  }

  /// สกัด keywords ที่มีความหมาย (ตัด stopwords ออก)
  List<String> _extractKeywords(String text) {
    const stop = {
      'the', 'a', 'an', 'is', 'at', 'to', 'for', 'with', 'and', 'or',
      'in', 'of', 'i', 'my', 'me', 'was', 'went', 'had', 'have', 'user',
      'about', 'that', 'this', 'wants', 'will', 'has', 'be', 'are', 'it',
    };
    return text
        .toLowerCase()
        .split(RegExp(r'[\s,\.\!\?\-\+]+'))
        .where((w) => w.length > 2 && !stop.contains(w))
        .toSet()
        .take(4)
        .toList();
  }
}
