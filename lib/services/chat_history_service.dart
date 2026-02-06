import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battery_aware_service.dart';
import 'llm_service.dart';

/// 💬 Chat History Service - เก็บประวัติแชทและสรุปอัตโนมัติ
///
/// Features:
/// - เก็บ raw chat history ไว้ให้ AI อ่าน context
/// - สรุปอัตโนมัติหลัง 24 ชม. ตอนชาร์จ (Defer to Charging)
/// - รักษา context ล่าสุดไว้เสมอ

class ChatHistoryService {
  static final ChatHistoryService _instance = ChatHistoryService._internal();
  factory ChatHistoryService() => _instance;
  ChatHistoryService._internal();

  final BatteryAwareService _batteryService = BatteryAwareService();
  final LLMService _llmService = LLMService();

  static const String _rawHistoryKey = 'chat_raw_history';
  static const String _summaryKey = 'chat_summaries';
  static const String _lastSummarizedKey = 'chat_last_summarized';

  // ประวัติแชท
  List<ChatEntry> _rawHistory = [];
  List<ChatSummary> _summaries = [];
  DateTime? _lastSummarized;

  bool _isInitialized = false;
  bool _isSummarizing = false;

  // Settings
  static const int maxRawMessages = 100; // เก็บ raw ไว้สูงสุด 100 ข้อความ
  static const Duration summarizeAfter = Duration(hours: 24);
  static const int messagesPerSummary = 20; // สรุปทุก 20 ข้อความ

  // Getters
  List<ChatEntry> get rawHistory => List.unmodifiable(_rawHistory);
  List<ChatSummary> get summaries => List.unmodifiable(_summaries);
  bool get isSummarizing => _isSummarizing;

  /// 🚀 Initialize service
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadFromStorage();

    // ลงทะเบียนกับ BatteryService เพื่อ summarize ตอนชาร์จ
    _batteryService.onChargingStarted = _onChargingStarted;

    _isInitialized = true;
    debugPrint('✅ Chat History Service initialized');
    debugPrint('   - Raw messages: ${_rawHistory.length}');
    debugPrint('   - Summaries: ${_summaries.length}');
  }

  /// 📥 Load จาก storage
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load raw history
      final rawJson = prefs.getString(_rawHistoryKey);
      if (rawJson != null) {
        final List<dynamic> list = jsonDecode(rawJson);
        _rawHistory = list.map((e) => ChatEntry.fromJson(e)).toList();
      }

      // Load summaries
      final summaryJson = prefs.getString(_summaryKey);
      if (summaryJson != null) {
        final List<dynamic> list = jsonDecode(summaryJson);
        _summaries = list.map((e) => ChatSummary.fromJson(e)).toList();
      }

      // Load last summarized time
      final lastStr = prefs.getString(_lastSummarizedKey);
      if (lastStr != null) {
        _lastSummarized = DateTime.parse(lastStr);
      }
    } catch (e) {
      debugPrint('⚠️ Error loading chat history: $e');
    }
  }

  /// 💾 Save to storage
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        _rawHistoryKey,
        jsonEncode(_rawHistory.map((e) => e.toJson()).toList()),
      );

      await prefs.setString(
        _summaryKey,
        jsonEncode(_summaries.map((e) => e.toJson()).toList()),
      );

      if (_lastSummarized != null) {
        await prefs.setString(
          _lastSummarizedKey,
          _lastSummarized!.toIso8601String(),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error saving chat history: $e');
    }
  }

  /// ➕ เพิ่มข้อความใหม่
  Future<void> addMessage({
    required String role,
    required String content,
    List<String>? actions,
  }) async {
    final entry = ChatEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: role,
      content: content,
      timestamp: DateTime.now(),
      actions: actions,
    );

    _rawHistory.add(entry);

    // ตัด history ถ้าเกิน max
    if (_rawHistory.length > maxRawMessages) {
      // ย้ายข้อความเก่าไปรอสรุป
      _markForSummarization();
    }

    await _saveToStorage();
  }

  /// 📝 ดึง context สำหรับ AI (รวม summaries + recent raw)
  String getContextForAI({int recentCount = 10}) {
    final buffer = StringBuffer();

    // เพิ่ม summaries ก่อน (เรียงจากเก่าไปใหม่)
    if (_summaries.isNotEmpty) {
      buffer.writeln('📋 สรุปบทสนทนาก่อนหน้า:');
      for (final summary in _summaries.take(3)) {
        buffer.writeln('- ${summary.period}: ${summary.content}');
      }
      buffer.writeln();
    }

    // เพิ่ม recent raw messages
    final recent = _rawHistory.length > recentCount
        ? _rawHistory.sublist(_rawHistory.length - recentCount)
        : _rawHistory;

    if (recent.isNotEmpty) {
      buffer.writeln('💬 บทสนทนาล่าสุด:');
      for (final entry in recent) {
        final roleLabel = entry.role == 'user' ? 'ผู้ใช้' : 'Haku';
        buffer.writeln('$roleLabel: ${entry.content}');
      }
    }

    return buffer.toString();
  }

  /// 🔌 Callback เมื่อเริ่มชาร์จ
  void _onChargingStarted() {
    debugPrint('🔌 Charging started - checking for pending summarization');
    _checkAndSummarize();
  }

  /// ✅ ตรวจสอบและสรุป (ถ้าถึงเวลา)
  Future<void> _checkAndSummarize() async {
    if (_isSummarizing) return;

    // ตรวจสอบว่าถึงเวลาสรุปหรือยัง
    final now = DateTime.now();
    if (_lastSummarized != null) {
      final elapsed = now.difference(_lastSummarized!);
      if (elapsed < summarizeAfter) {
        debugPrint('⏳ Not time to summarize yet (${elapsed.inHours}h elapsed)');
        return;
      }
    }

    // ตรวจสอบว่ามีข้อความพอที่จะสรุป
    if (_rawHistory.length < messagesPerSummary) {
      debugPrint('📝 Not enough messages to summarize (${_rawHistory.length})');
      return;
    }

    // ตรวจสอบว่ากำลังชาร์จ
    if (!_batteryService.isChargingOrFull) {
      debugPrint('🔋 Not charging - deferring summarization');
      return;
    }

    await _performSummarization();
  }

  /// 📊 ทำการสรุป
  Future<void> _performSummarization() async {
    if (_isSummarizing) return;

    _isSummarizing = true;
    debugPrint('📝 Starting chat summarization...');

    try {
      // แยกข้อความที่จะสรุป (เก็บล่าสุดไว้)
      final toSummarize = _rawHistory.length > messagesPerSummary
          ? _rawHistory.sublist(0, _rawHistory.length - 10)
          : [];

      if (toSummarize.isEmpty) {
        debugPrint('⚠️ No messages to summarize');
        return;
      }

      // สร้าง prompt สำหรับสรุป
      final messagesText = toSummarize.map((e) {
        final roleLabel = e.role == 'user' ? 'ผู้ใช้' : 'Haku';
        return '$roleLabel: ${e.content}';
      }).join('\n');

      final summaryPrompt = '''
สรุปบทสนทนาต่อไปนี้เป็นภาษาไทย แบบกระชับ จับใจความสำคัญ:
- หัวข้อที่คุยกัน
- อารมณ์/ความรู้สึกของผู้ใช้
- สิ่งสำคัญที่ต้องจำ (นัด, งาน, เป้าหมาย)

บทสนทนา:
$messagesText

สรุป (ไม่เกิน 3 ประโยค):''';

      // เรียก LLM สรุป
      final summaryContent = await _llmService.generate(summaryPrompt);

      // สร้าง summary object
      final firstDate = toSummarize.first.timestamp;
      final lastDate = toSummarize.last.timestamp;
      final summary = ChatSummary(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: summaryContent.trim(),
        period: _formatPeriod(firstDate, lastDate),
        startDate: firstDate,
        endDate: lastDate,
        messageCount: toSummarize.length,
        createdAt: DateTime.now(),
      );

      // อัพเดต state
      _summaries.add(summary);
      _rawHistory = _rawHistory.sublist(toSummarize.length);
      _lastSummarized = DateTime.now();

      // เก็บสรุปไม่เกิน 10 อัน
      if (_summaries.length > 10) {
        _summaries = _summaries.sublist(_summaries.length - 10);
      }

      await _saveToStorage();

      debugPrint('✅ Summarization complete');
      debugPrint('   - Summarized ${toSummarize.length} messages');
      debugPrint('   - Remaining raw: ${_rawHistory.length}');
    } catch (e) {
      debugPrint('⚠️ Summarization failed: $e');
    } finally {
      _isSummarizing = false;
    }
  }

  /// 🏷️ Mark messages for summarization
  void _markForSummarization() {
    // ถ้ากำลังชาร์จ ให้สรุปเลย
    if (_batteryService.isChargingOrFull) {
      _checkAndSummarize();
    }
    // ถ้าไม่ได้ชาร์จ จะสรุปตอนเริ่มชาร์จ
  }

  /// 📅 Format period string
  String _formatPeriod(DateTime start, DateTime end) {
    final startStr = '${start.day}/${start.month}';
    final endStr = '${end.day}/${end.month}';

    if (startStr == endStr) {
      return startStr;
    }
    return '$startStr - $endStr';
  }

  /// 🗑️ ล้างประวัติทั้งหมด
  Future<void> clearAll() async {
    _rawHistory.clear();
    _summaries.clear();
    _lastSummarized = null;
    await _saveToStorage();
  }

  /// 🔄 Force summarize (สำหรับ debug)
  Future<void> forceSummarize() async {
    await _performSummarization();
  }
}

/// 📝 Chat Entry - ข้อความแชทเดี่ยว
class ChatEntry {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;
  final List<String>? actions;

  ChatEntry({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.actions,
  });

  factory ChatEntry.fromJson(Map<String, dynamic> json) {
    return ChatEntry(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      actions: json['actions'] != null
          ? List<String>.from(json['actions'] as List)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'actions': actions,
    };
  }
}

/// 📊 Chat Summary - สรุปบทสนทนา
class ChatSummary {
  final String id;
  final String content;
  final String period;
  final DateTime startDate;
  final DateTime endDate;
  final int messageCount;
  final DateTime createdAt;

  ChatSummary({
    required this.id,
    required this.content,
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.messageCount,
    required this.createdAt,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    return ChatSummary(
      id: json['id'] as String,
      content: json['content'] as String,
      period: json['period'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      messageCount: json['messageCount'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'period': period,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'messageCount': messageCount,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
