import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/entry.dart';
import 'database_helper.dart';
import 'rag_service.dart';

/// 🧠 Context Retriever - ดึงข้อมูลบริบทจากหลายแหล่ง
/// 
/// รวมข้อมูลจาก:
/// - SQLite: บันทึกล่าสุด/บันทึกตามเงื่อนไข
/// - Vector DB (RAG): ความชอบ/ไม่ชอบ/แนวโน้ม
/// - Triggers: GPS, Time patterns

class ContextRetriever {
  static final ContextRetriever _instance = ContextRetriever._internal();
  factory ContextRetriever() => _instance;
  ContextRetriever._internal();

  /// 📊 ดึง Context แบบเต็ม (สำหรับ Chat)
  /// 
  /// แก้ Performance: เรียก getAllEntries() ครั้งเดียว แล้วแชร์ข้อมูล
  Future<ContextData> retrieveFullContext({
    String? userQuery,
    DateTime? currentTime,
    String? currentLocation,
  }) async {
    final now = currentTime ?? DateTime.now();
    
    // ดึงข้อมูลทั้งหมดครั้งเดียว
    final allEntries = await DatabaseHelper.instance.getAllEntries();
    
    return ContextData(
      recentEntries: _extractRecentEntries(allEntries, limit: 10),
      todaySummary: _extractTodaySummary(allEntries, now),
      locationPattern: _extractLocationPattern(allEntries, currentLocation),
      timePattern: _extractTimePattern(allEntries, now),
      preferences: await _getPreferences(userQuery),
      relatedEntries: userQuery != null 
        ? await _getRelatedEntries(userQuery) 
        : [],
    );
  }

  /// 📝 ดึงบันทึกล่าสุด (จากข้อมูลที่มีแล้ว)
  List<Entry> _extractRecentEntries(List<Entry> entries, {int limit = 10}) {
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries.take(limit).toList();
  }

  /// 📅 สรุปวันนี้ (จากข้อมูลที่มีแล้ว)
  /// 
  /// แก้ Bug: ใช้ !isBefore(startOfDay) แทน isAfter() เพื่อรวมเที่ยงคืนพอดี
  TodaySummary? _extractTodaySummary(List<Entry> entries, DateTime now) {
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    // แก้ off-by-one: ใช้ !isBefore(startOfDay) แทน isAfter()
    final todayEntries = entries.where((e) => 
      !e.createdAt.isBefore(startOfDay) && e.createdAt.isBefore(endOfDay)
    ).toList();

    if (todayEntries.isEmpty) return null;

    // คำนวณสถิติ
    final moods = todayEntries.where((e) => e.mood != null).map((e) => e.mood!).toList();
    final avgMood = moods.isNotEmpty 
      ? moods.reduce((a, b) => a + b) / moods.length 
      : null;
    
    final locations = todayEntries
      .where((e) => e.locationName != null)
      .map((e) => e.locationName!)
      .toSet()
      .toList();

    return TodaySummary(
      entryCount: todayEntries.length,
      averageMood: avgMood,
      locations: locations,
      activities: todayEntries.map((e) => e.content).toList(),
    );
  }

  /// 📍 วิเคราะห์ pattern ตามสถานที่ (จากข้อมูลที่มีแล้ว)
  LocationPattern? _extractLocationPattern(List<Entry> entries, String? currentLocation) {
    if (currentLocation == null) return null;
    
    // หาบันทึกที่สถานที่นี้
    final locationEntries = entries
      .where((e) => e.locationName?.toLowerCase().contains(currentLocation.toLowerCase()) ?? false)
      .toList();
    
    if (locationEntries.isEmpty) return null;

    // วิเคราะห์ mood เฉลี่ยที่สถานที่นี้
    final moods = locationEntries.where((e) => e.mood != null).map((e) => e.mood!).toList();
    final avgMood = moods.isNotEmpty 
      ? moods.reduce((a, b) => a + b) / moods.length 
      : null;

    // หา common activities
    final allTags = locationEntries.expand((e) => e.tags).toList();
    final tagFrequency = <String, int>{};
    for (final tag in allTags) {
      tagFrequency[tag] = (tagFrequency[tag] ?? 0) + 1;
    }
    final commonTags = tagFrequency.entries
      .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return LocationPattern(
      location: currentLocation,
      visitCount: locationEntries.length,
      averageMood: avgMood,
      commonActivities: commonTags.take(3).map((e) => e.key).toList(),
    );
  }

  /// ⏰ วิเคราะห์ pattern ตามเวลา (จากข้อมูลที่มีแล้ว)
  /// 
  /// แก้ Bug: รองรับการห่อรอบเที่ยงคืน (wrap around midnight)
  TimePattern _extractTimePattern(List<Entry> entries, DateTime now) {
    final hour = now.hour;
    
    // หาบันทึกช่วงเวลาเดียวกัน (±2 ชั่วโมง) - รองรับห่อรอบเที่ยงคืน
    final similarTimeEntries = entries.where((e) {
      final entryHour = e.createdAt.hour;
      // แก้ wrap-around: คำนวณระยะห่างแบบ circular (0-23)
      int diff = (entryHour - hour).abs();
      if (diff > 12) diff = 24 - diff; // ห่างเกิน 12 ชั่วโมง ให้นับจากอีกทาง
      return diff <= 2;
    }).toList();

    // วิเคราะห์ว่าช่วงนี้มักทำอะไร
    final activities = similarTimeEntries.map((e) => e.content).toList();
    final moods = similarTimeEntries.where((e) => e.mood != null).map((e) => e.mood!).toList();
    
    return TimePattern(
      currentHour: hour,
      similarEntriesCount: similarTimeEntries.length,
      commonActivities: activities.take(5).toList(),
      averageMoodAtThisTime: moods.isNotEmpty 
        ? moods.reduce((a, b) => a + b) / moods.length 
        : null,
    );
  }

  /// 💝 ดึงความชอบ/ไม่ชอบ (ผ่าน RAG)
  Future<UserPreferences> _getPreferences(String? query) async {
    if (query == null) return UserPreferences.empty();

    try {
      if (!RAGService().isInitialized) {
        return UserPreferences.empty();
      }

      // ใช้ RAG หาข้อมูลที่เกี่ยวข้อง
      final ragResults = await RAGService().search(query, limit: 5);

      // วิเคราะห์ sentiment จากผลลัพธ์
      final positiveEntries = ragResults.where((r) => r.entry.mood != null && r.entry.mood! >= 4).toList();
      final negativeEntries = ragResults.where((r) => r.entry.mood != null && r.entry.mood! <= 2).toList();

      return UserPreferences(
        relatedEntries: ragResults.map((r) => r.entry).toList(),
        positiveContexts: positiveEntries.map((r) => r.entry.content).toList(),
        negativeContexts: negativeEntries.map((r) => r.entry.content).toList(),
      );
    } catch (e) {
      debugPrint('⚠️ _getPreferences error: $e');
      return UserPreferences.empty();
    }
  }

  /// 🔍 ดึงบันทึกที่เกี่ยวข้องกับคำถาม
  Future<List<Entry>> _getRelatedEntries(String query) async {
    try {
      if (!RAGService().isInitialized) {
        return [];
      }
      final results = await RAGService().search(query, limit: 5);
      return results.map((r) => r.entry).toList();
    } catch (e) {
      debugPrint('⚠️ _getRelatedEntries error: $e');
      return [];
    }
  }

  /// 📝 สร้าง Context String สำหรับ Prompt
  String buildContextString(ContextData context) {
    final buffer = StringBuffer();
    
    // สรุปวันนี้
    if (context.todaySummary != null) {
      buffer.writeln('## วันนี้');
      buffer.writeln('- บันทึก: ${context.todaySummary!.entryCount} รายการ');
      if (context.todaySummary!.averageMood != null) {
        buffer.writeln('- อารมณ์เฉลี่ย: ${context.todaySummary!.averageMood!.toStringAsFixed(1)}/5');
      }
      if (context.todaySummary!.locations.isNotEmpty) {
        buffer.writeln('- สถานที่: ${context.todaySummary!.locations.join(', ')}');
      }
      buffer.writeln();
    }

    // Pattern ตามเวลา
    buffer.writeln('## ช่วงเวลานี้ (ประมาณ ${context.timePattern.currentHour}:00)');
    if (context.timePattern.averageMoodAtThisTime != null) {
      buffer.writeln('- อารมณ์เฉลี่ยช่วงนี้: ${context.timePattern.averageMoodAtThisTime!.toStringAsFixed(1)}/5');
    }
    if (context.timePattern.commonActivities.isNotEmpty) {
      buffer.writeln('- กิจกรรมที่มักทำ: ${context.timePattern.commonActivities.take(3).join(', ')}');
    }
    buffer.writeln();

    // Pattern ตามสถานที่
    if (context.locationPattern != null) {
      buffer.writeln('## สถานที่: ${context.locationPattern!.location}');
      buffer.writeln('- เคยมา ${context.locationPattern!.visitCount} ครั้ง');
      if (context.locationPattern!.averageMood != null) {
        buffer.writeln('- อารมณ์เฉลี่ยที่นี่: ${context.locationPattern!.averageMood!.toStringAsFixed(1)}/5');
      }
      if (context.locationPattern!.commonActivities.isNotEmpty) {
        buffer.writeln('- กิจกรรมที่มักทำ: ${context.locationPattern!.commonActivities.join(', ')}');
      }
      buffer.writeln();
    }

    // บันทึกที่เกี่ยวข้อง
    if (context.relatedEntries.isNotEmpty) {
      buffer.writeln('## บันทึกที่เกี่ยวข้อง');
      for (var i = 0; i < min(3, context.relatedEntries.length); i++) {
        final entry = context.relatedEntries[i];
        final content = entry.content.length > 100 
          ? '${entry.content.substring(0, 100)}...' 
          : entry.content;
        buffer.writeln('- ${entry.createdAt}: $content');
      }
      buffer.writeln();
    }

    // ความชอบ/ไม่ชอบ
    if (context.preferences.positiveContexts.isNotEmpty) {
      buffer.writeln('## สิ่งที่ชอบ/มีความสุข');
      for (final ctx in context.preferences.positiveContexts.take(3)) {
        final text = ctx.length > 80 ? '${ctx.substring(0, 80)}...' : ctx;
        buffer.writeln('- $text');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }
}

/// 📦 ข้อมูล Context ทั้งหมด
class ContextData {
  final List<Entry> recentEntries;
  final TodaySummary? todaySummary;
  final LocationPattern? locationPattern;
  final TimePattern timePattern;
  final UserPreferences preferences;
  final List<Entry> relatedEntries;

  ContextData({
    required this.recentEntries,
    this.todaySummary,
    this.locationPattern,
    required this.timePattern,
    required this.preferences,
    required this.relatedEntries,
  });
}

/// 📅 สรุปวันนี้
class TodaySummary {
  final int entryCount;
  final double? averageMood;
  final List<String> locations;
  final List<String> activities;

  TodaySummary({
    required this.entryCount,
    this.averageMood,
    required this.locations,
    required this.activities,
  });
}

/// 📍 Pattern ตามสถานที่
class LocationPattern {
  final String location;
  final int visitCount;
  final double? averageMood;
  final List<String> commonActivities;

  LocationPattern({
    required this.location,
    required this.visitCount,
    this.averageMood,
    required this.commonActivities,
  });
}

/// ⏰ Pattern ตามเวลา
class TimePattern {
  final int currentHour;
  final int similarEntriesCount;
  final List<String> commonActivities;
  final double? averageMoodAtThisTime;

  TimePattern({
    required this.currentHour,
    required this.similarEntriesCount,
    required this.commonActivities,
    this.averageMoodAtThisTime,
  });
}

/// 💝 ความชอบของผู้ใช้
class UserPreferences {
  final List<Entry> relatedEntries;
  final List<String> positiveContexts;
  final List<String> negativeContexts;

  UserPreferences({
    required this.relatedEntries,
    required this.positiveContexts,
    required this.negativeContexts,
  });

  factory UserPreferences.empty() => UserPreferences(
    relatedEntries: [],
    positiveContexts: [],
    negativeContexts: [],
  );
}
