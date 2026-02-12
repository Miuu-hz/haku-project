import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'llm_provider.dart';
import 'llm_provider_manager.dart';
import 'prompt_builder.dart';

/// 🔋 Chat Summary Service - Deferred Processing
/// 
/// เก็บประวัติแชทไว้ 24 ชม. แล้วสรุปตอนชาร์จ
/// 
/// กลยุทธ์:
/// 1. เก็บแชทแบบ lightweight (text only) ไม่กินแบต
/// 2. รอจนครบ 24 ชม. หรือมีข้อความครบ threshold
/// 3. ตรวจจับการชาร์จ - เริ่มสรุปทันที
/// 4. ถ้าไม่ชาร์จภายใน 6 ชม. สรุปเลย (ไม่งั้นเสียความสด)
///
/// ข้อดี:
/// - ไม่กิน CPU ตอนใช้งานปกติ
/// - LLM ทำงานตอนชาร์จเท่านั้น
/// - มีสรุปให้ทุกวันแบบอัตโนมัติ

class ChatSummaryService {
  static final ChatSummaryService _instance = ChatSummaryService._internal();
  factory ChatSummaryService() => _instance;
  ChatSummaryService._internal();

  /// 🔋 Battery state monitor
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batterySubscription;
  
  /// ⏰ Timer ตรวจสอบคิวสรุป
  Timer? _queueCheckTimer;
  
  /// 📊 สถานะการทำงาน
  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  /// 🕐 ช่วงเวลาต่างๆ
  static const int _summaryThresholdHours = 24;      // สรุปทุก 24 ชม.
  static const int _maxWaitHours = 30;               // รอนานสุด 30 ชม.
  static const int _messageThreshold = 10;           // หรือครบ 10 ข้อความ
  static const int _queueCheckIntervalMinutes = 15;  // เช็คคิวทุก 15 นาที

  /// 📁 Keys สำหรับ SharedPreferences
  static const String _chatHistoryKey = 'chat_history_queue';
  static const String _pendingSummariesKey = 'pending_summaries';
  static const String _lastSummaryTimeKey = 'last_summary_time';

  /// 🚀 เริ่มต้น Service
  Future<void> initialize() async {
    debugPrint('🔋 ChatSummaryService initialized');
    
    // เริ่มต้นตรวจจับการชาร์จ
    _startBatteryMonitoring();
    
    // เริ่มต้น timer เช็คคิว
    _startQueueChecker();
  }

  /// 📝 บันทึกข้อความแชทใหม่ (Lightweight - ไม่กินแบต)
  ///
  /// เรียกเมื่อมีข้อความใหม่ในแชท
  Future<void> logChatMessage({
    required String message,
    required bool isUser,
    String? intent, // log, schedule, chat, etc.
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // ดึงประวัติเดิม
      final historyJson = prefs.getStringList(_chatHistoryKey) ?? [];
      
      // เพิ่มข้อความใหม่ (เก็บแบบ minimal)
      final entry = {
        'timestamp': DateTime.now().toIso8601String(),
        'isUser': isUser,
        'message': message,
        'intent': intent ?? 'chat',
        'length': message.length,
      };
      
      historyJson.add(jsonEncode(entry));
      
      // เก็บแค่ 100 ข้อความล่าสุด (ประหยัด memory)
      if (historyJson.length > 100) {
        historyJson.removeAt(0);
      }
      
      await prefs.setStringList(_chatHistoryKey, historyJson);
      
      // ตรวจสอบว่าครบ threshold ยัง
      await _checkSummaryThreshold();
      
    } catch (e) {
      debugPrint('❌ Error logging chat: $e');
    }
  }

  /// 🔋 เริ่มต้นตรวจจับการชาร์จ
  void _startBatteryMonitoring() {
    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
      if (state == BatteryState.charging) {
        debugPrint('🔌 Device is charging - checking summary queue');
        _processPendingSummaries();
      }
    });
  }

  /// ⏰ เริ่มต้น timer เช็คคิว
  void _startQueueChecker() {
    _queueCheckTimer?.cancel();
    _queueCheckTimer = Timer.periodic(
      const Duration(minutes: _queueCheckIntervalMinutes),
      (_) => _checkQueue(),
    );
  }

  /// 📋 ตรวจสอบคิวสรุป
  Future<void> _checkQueue() async {
    if (_isProcessing) return;
    
    try {
      // เช็คว่ามีงานค้างไหม
      final pending = await _getPendingSummaries();
      if (pending.isEmpty) return;
      
      // เช็คว่าชาร์จอยู่ไหม
      final batteryState = await _battery.batteryState;
      final isCharging = batteryState == BatteryState.charging || 
                         batteryState == BatteryState.full;
      
      for (final summaryJob in pending) {
        final age = DateTime.now().difference(summaryJob.createdAt);
        
        // เงื่อนไขการสรุป:
        // 1. ชาร์จอยู่ + อายุเกิน 6 ชม. (ดีที่สุด)
        // 2. ไม่ชาร์จแต่อายุเกิน 30 ชม. (สรุปเลยไม่งั้นเสียความสด)
        
        final shouldProcess = (isCharging && age.inHours >= 6) || 
                              age.inHours >= _maxWaitHours;
        
        if (shouldProcess) {
          await _processSummary(summaryJob);
        }
      }
      
    } catch (e) {
      debugPrint('❌ Error checking queue: $e');
    }
  }

  /// 📊 ตรวจสอบ Threshold สำหรับสรุป
  Future<void> _checkSummaryThreshold() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // เช็คเวลาสรุปล่าสุด
      final lastSummaryStr = prefs.getString(_lastSummaryTimeKey);
      if (lastSummaryStr != null) {
        final lastSummary = DateTime.parse(lastSummaryStr);
        final hoursSinceLast = DateTime.now().difference(lastSummary).inHours;
        
        // ถ้ายังไม่ครบ 24 ชม. ไม่ต้องสร้างคิวใหม่
        if (hoursSinceLast < _summaryThresholdHours) return;
      }
      
      // ดึงข้อความที่ยังไม่ได้สรุป
      final history = await _getChatHistory(since: lastSummaryStr);
      if (history.length < _messageThreshold) return;
      
      // สร้างคิวสรุปใหม่
      await _createSummaryJob(history);
      
      // ล้างประวัติที่สรุปแล้ว
      await _clearProcessedHistory();
      
    } catch (e) {
      debugPrint('❌ Error checking threshold: $e');
    }
  }

  /// 🏭 สร้างงานสรุปใหม่
  Future<void> _createSummaryJob(List<ChatEntry> history) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final job = SummaryJob(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
        entries: history,
        status: SummaryStatus.pending,
      );
      
      // ดึงคิงเดิม
      final pendingJson = prefs.getStringList(_pendingSummariesKey) ?? [];
      pendingJson.add(jsonEncode(job.toJson()));
      
      await prefs.setStringList(_pendingSummariesKey, pendingJson);
      
      // อัปเดตเวลาสรุปล่าสุด
      await prefs.setString(_lastSummaryTimeKey, DateTime.now().toIso8601String());
      
      debugPrint('📋 Created summary job: ${job.id} (${history.length} messages)');
      
    } catch (e) {
      debugPrint('❌ Error creating summary job: $e');
    }
  }

  /// ⚡ ประมวลผลงานสรุปที่ค้างไว้
  Future<void> _processPendingSummaries() async {
    if (_isProcessing) return;
    
    final pending = await _getPendingSummaries();
    if (pending.isEmpty) return;
    
    debugPrint('⚡ Processing ${pending.length} pending summaries...');
    
    for (final job in pending) {
      await _processSummary(job);
    }
  }

  /// 🤖 ประมวลผลสรุปด้วย LLM
  Future<void> _processSummary(SummaryJob job) async {
    if (_isProcessing) return;
    _isProcessing = true;
    
    try {
      debugPrint('🤖 Processing summary ${job.id}...');
      
      // เตรียมข้อมูล
      final conversationText = job.entries
          .map((e) => '${e.isUser ? 'User' : 'Haku'}: ${e.message}')
          .join('\n');
      
      // เรียก LLM (ตอนนี้ชาร์จอยู่ ไม่ต้องห่วงแบต)
      final llm = LLMProviderManager().provider;
      
      if (!llm.isInitialized) {
        debugPrint('⚠️ LLM not available, skipping summary');
        _isProcessing = false;
        return;
      }
      
      final prompt = PromptBuilder.buildDailySummaryPrompt(
        entriesContent: conversationText,
        period: 'ช่วง 24 ชั่วโมง',
      );
      
      final response = await llm.generate(prompt);
      
      // บันทึกผลลัพธ์
      await _saveSummaryResult(job, response);
      
      // ลบออกจากคิว
      await _removeFromQueue(job.id);
      
      debugPrint('✅ Summary completed: ${job.id}');
      
    } catch (e) {
      debugPrint('❌ Error processing summary: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// 💾 บันทึกผลสรุป
  Future<void> _saveSummaryResult(SummaryJob job, String summary) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // เก็บสรุปใน key แยก (ไม่เกิน 7 วัน)
      final summaryKey = 'daily_summary_${job.id}';
      await prefs.setString(summaryKey, jsonEncode({
        'date': job.createdAt.toIso8601String(),
        'summary': summary,
        'messageCount': job.entries.length,
      }));
      
      // ล้างสรุปเก่า (เก็บแค่ 7 วัน)
      await _cleanupOldSummaries();
      
    } catch (e) {
      debugPrint('❌ Error saving summary: $e');
    }
  }

  /// 🗑️ ล้างสรุปเก่า (เก็บแค่ 7 วัน)
  Future<void> _cleanupOldSummaries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      
      for (final key in keys) {
        if (key.startsWith('daily_summary_')) {
          final json = prefs.getString(key);
          if (json != null) {
            final data = jsonDecode(json) as Map<String, dynamic>;
            final date = DateTime.parse(data['date'] as String);
            if (date.isBefore(cutoff)) {
              await prefs.remove(key);
            }
          }
        }
      }
      
    } catch (e) {
      debugPrint('❌ Error cleaning up: $e');
    }
  }

  /// 📖 ดึงประวัติแชท
  Future<List<ChatEntry>> _getChatHistory({String? since}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList(_chatHistoryKey) ?? [];
      
      final sinceTime = since != null ? DateTime.parse(since) : null;
      
      return historyJson
          .map((json) => ChatEntry.fromJson(jsonDecode(json) as Map<String, dynamic>))
          .where((e) => sinceTime == null || e.timestamp.isAfter(sinceTime))
          .toList();
          
    } catch (e) {
      debugPrint('❌ Error getting history: $e');
      return [];
    }
  }

  /// 📋 ดึงคิวสรุปที่ค้าง
  Future<List<SummaryJob>> _getPendingSummaries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getStringList(_pendingSummariesKey) ?? [];
      
      return pendingJson
          .map((json) => SummaryJob.fromJson(jsonDecode(json) as Map<String, dynamic>))
          .where((j) => j.status == SummaryStatus.pending)
          .toList();
          
    } catch (e) {
      debugPrint('❌ Error getting pending: $e');
      return [];
    }
  }

  /// 🗑️ ลบออกจากคิว
  Future<void> _removeFromQueue(String jobId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getStringList(_pendingSummariesKey) ?? [];
      
      pendingJson.removeWhere((json) {
        final data = jsonDecode(json);
        return data['id'] == jobId;
      });
      
      await prefs.setStringList(_pendingSummariesKey, pendingJson);
      
    } catch (e) {
      debugPrint('❌ Error removing from queue: $e');
    }
  }

  /// 🧹 ล้างประวัติที่ประมวลผลแล้ว
  Future<void> _clearProcessedHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_chatHistoryKey);
      
    } catch (e) {
      debugPrint('❌ Error clearing history: $e');
    }
  }

  /// 🚫 ปิด Service
  void dispose() {
    _batterySubscription?.cancel();
    _queueCheckTimer?.cancel();
    debugPrint('🚫 ChatSummaryService disposed');
  }

  /// 📊 ดึงสรุปล่าสุด (สำหรับแสดง UI)
  Future<List<DailySummary>> getRecentSummaries({int limit = 7}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys()
          .where((k) => k.startsWith('daily_summary_'))
          .toList();
      
      final summaries = <DailySummary>[];
      
      for (final key in keys) {
        final json = prefs.getString(key);
        if (json != null) {
          final data = jsonDecode(json) as Map<String, dynamic>;
          summaries.add(DailySummary(
            date: DateTime.parse(data['date'] as String),
            summary: data['summary'] as String,
            messageCount: data['messageCount'] as int,
          ));
        }
      }
      
      // เรียงล่าสุดก่อน
      summaries.sort((a, b) => b.date.compareTo(a.date));
      
      return summaries.take(limit).toList();
      
    } catch (e) {
      debugPrint('❌ Error getting summaries: $e');
      return [];
    }
  }
}

/// 📄 โมเดลข้อมูล

class ChatEntry {
  final DateTime timestamp;
  final bool isUser;
  final String message;
  final String intent;
  final int length;

  ChatEntry({
    required this.timestamp,
    required this.isUser,
    required this.message,
    required this.intent,
    required this.length,
  });

  factory ChatEntry.fromJson(Map<String, dynamic> json) => ChatEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        isUser: json['isUser'] as bool,
        message: json['message'] as String,
        intent: json['intent'] as String,
        length: json['length'] as int,
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'isUser': isUser,
        'message': message,
        'intent': intent,
        'length': length,
      };
}

class SummaryJob {
  final String id;
  final DateTime createdAt;
  final List<ChatEntry> entries;
  final SummaryStatus status;

  SummaryJob({
    required this.id,
    required this.createdAt,
    required this.entries,
    required this.status,
  });

  factory SummaryJob.fromJson(Map<String, dynamic> json) => SummaryJob(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        entries: (json['entries'] as List<dynamic>)
            .map((e) => ChatEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        status: SummaryStatus.values.byName(json['status'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'status': status.name,
      };
}

class DailySummary {
  final DateTime date;
  final String summary;
  final int messageCount;

  DailySummary({
    required this.date,
    required this.summary,
    required this.messageCount,
  });
}

enum SummaryStatus { pending, processing, completed, failed }
