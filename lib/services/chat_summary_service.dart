import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/entry.dart';
import 'mediapipe_llm_service.dart';
import 'prompt_builder.dart';

/// 💬 Unified Chat & Summary Service
/// 
/// รวม 3 ไฟล์เก่า:
/// - chat_history_service.dart (เก็บประวัติแชท + context ให้ AI)
/// - summarization_service.dart (สรุป entries + sentiment)
/// - chat_summary_service.dart (deferred processing ตอนชาร์จ)
///
/// หน้าที่:
/// 1. เก็บ raw chat history (100 ข้อความล่าสุด)
/// 2. ให้ context สำหรับ AI response (สรุป + ข้อความล่าสุด)
/// 3. สรุป entries (entry เดี่ยว/หลาย entries)
/// 4. วิเคราะห์ sentiment
/// 5. Deferred processing: สรุป chat ตอนชาร์จ

class ChatSummaryService {
  static final ChatSummaryService _instance = ChatSummaryService._internal();
  factory ChatSummaryService() => _instance;
  ChatSummaryService._internal();

  // ============================================================================
  // Dependencies
  // ============================================================================
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batterySubscription;
  Timer? _queueCheckTimer;
  bool _isProcessing = false;

  // ============================================================================
  // Constants
  // ============================================================================
  static const int _maxRawMessages = 100;      // เก็บ raw message สูงสุด
  static const int _contextMessageCount = 10;  // ใช้ 10 ข้อความล่าสุดเป็น context
  static const int _summaryThresholdHours = 24;
  static const int _maxWaitHours = 30;
  static const int _messageThreshold = 10;
  static const int _queueCheckIntervalMinutes = 15;

  // ============================================================================
  // Storage Keys
  // ============================================================================
  static const String _chatHistoryKey = 'chat_history_queue';
  static const String _chatSummariesKey = 'chat_summaries_v2';  // สรุปแชทแยก
  static const String _pendingSummariesKey = 'pending_summaries';
  static const String _lastSummaryTimeKey = 'last_summary_time';

  // ============================================================================
  // Initialization
  // ============================================================================
  Future<void> initialize() async {
    debugPrint('💬 ChatSummaryService initialized');
    _startBatteryMonitoring();
    _startQueueChecker();
  }

  void dispose() {
    _batterySubscription?.cancel();
    _queueCheckTimer?.cancel();
  }

  // ============================================================================
  // PART 1: Chat History Management (จาก chat_history_service.dart)
  // ============================================================================

  /// 📝 บันทึกข้อความแชทใหม่
  Future<void> addMessage({
    required String role,      // 'user' | 'assistant' | 'system'
    required String content,
    String? intent,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_chatHistoryKey) ?? [];

    final entry = ServiceChatMessage(
      timestamp: DateTime.now(),
      role: role,
      content: content,
      intent: intent,
    );

    history.add(jsonEncode(entry.toJson()));

    // เก็บแค่ 100 ข้อความล่าสุด
    while (history.length > _maxRawMessages) {
      history.removeAt(0);
    }

    await prefs.setStringList(_chatHistoryKey, history);

    // ตรวจสอบ threshold สรุป
    await _checkSummaryThreshold();
  }

  /// 🤖 ดึง Context สำหรับ AI (สรุป + ข้อความล่าสุด)
  Future<String> getContextForAI() async {
    // 1. ดึงสรุปเก่า
    final summaries = await _loadSummaries();
    final recentSummaries = summaries.take(3).toList();

    // 2. ดึงข้อความล่าสุด
    final history = await _loadChatHistory();
    final recentMessages = history.length > _contextMessageCount
        ? history.sublist(history.length - _contextMessageCount)
        : history;

    // 3. สร้าง context string
    final buffer = StringBuffer();

    if (recentSummaries.isNotEmpty) {
      buffer.writeln('=== บทสนทนาก่อนหน้า (สรุป) ===');
      for (final s in recentSummaries) {
        buffer.writeln('[${s.date}] ${s.summary.substring(0, min(200, s.summary.length))}...');
      }
      buffer.writeln();
    }

    if (recentMessages.isNotEmpty) {
      buffer.writeln('=== บทสนทนาล่าสุด ===');
      for (final m in recentMessages) {
        final role = m.role == 'user' ? 'User' : 'Haku';
        buffer.writeln('$role: ${m.content}');
      }
    }

    return buffer.toString();
  }

  /// 💬 ดึงบริบทย่อยสำหรับการตอบกลับ (±2 ข้อความรอบ target)
  Future<String> getReplyContext(int targetMessageId) async {
    final history = await _loadChatHistory();
    final targetIndex = history.indexWhere((m) => m.timestamp.millisecondsSinceEpoch == targetMessageId);

    if (targetIndex == -1) return '';

    final start = max(0, targetIndex - 2);
    final end = min(history.length, targetIndex + 3);
    final contextMessages = history.sublist(start, end);

    return contextMessages
        .map((m) => '${m.role == 'user' ? 'User' : 'Haku'}: ${m.content}')
        .join('\n');
  }

  // ============================================================================
  // PART 2: Entry Summarization (จาก summarization_service.dart)
  // ============================================================================

  /// 📝 สรุป Entry เดี่ยว
  Future<String> summarizeEntry(Entry entry) async {
    final prompt = PromptBuilder.buildDailySummaryPrompt(
      entriesContent: entry.content,
      period: 'บันทึกนี้',
    );

    try {
      final response = await MediaPipeLLMService().generate(prompt);
      return response.isEmpty ? _fallbackSummarizeEntry(entry) : response.trim();
    } catch (e) {
      return _fallbackSummarizeEntry(entry);
    }
  }

  /// 📅 สรุปหลาย Entries
  Future<String> summarizeEntries(List<Entry> entries, {String? period}) async {
    if (entries.isEmpty) {
      return 'ยังไม่มีบันทึกสำหรับ${period ?? 'ช่วงนี้'}ค่ะ';
    }

    final content = entries
        .map((e) => '- ${e.createdAt.hour}:${e.createdAt.minute.toString().padLeft(2, '0')}: ${e.content}')
        .join('\n');

    final prompt = PromptBuilder.buildDailySummaryPrompt(
      entriesContent: content,
      period: period ?? 'ช่วงนี้',
    );

    try {
      final response = await MediaPipeLLMService().generate(prompt);
      return response.isEmpty ? _fallbackSummarizeEntries(entries, period: period) : response.trim();
    } catch (e) {
      return _fallbackSummarizeEntries(entries, period: period);
    }
  }

  /// 🔍 ดึง Key Insights จาก Entry
  Future<List<String>> extractInsights(Entry entry) async {
    final prompt = '''<|im_start|>system
ดึง 3-5 ประเด็นสำคัญจากบันทึก (กิจกรรม ความรู้สึก สถานที่)
ตอบเป็นรายการ:
- ประเด็น 1
- ประเด็น 2<|im_end|>
<|im_start|>user
${entry.content}<|im_end|>
<|im_start|>assistant
''';  

    try {
      final response = await MediaPipeLLMService().generate(prompt);
      if (response.isEmpty) return _fallbackExtractInsights(entry);

      final lines = response
          .split('\n')
          .where((l) => l.trim().startsWith('-'))
          .map((l) => l.trim().substring(1).trim())
          .where((l) => l.isNotEmpty)
          .toList();

      return lines.isEmpty ? _fallbackExtractInsights(entry) : lines;
    } catch (e) {
      return _fallbackExtractInsights(entry);
    }
  }

  /// 📊 วิเคราะห์ Sentiment
  SentimentAnalysis analyzeSentiment(Entry entry) {
    final text = entry.content;
    final positiveWords = ['happy', 'มีความสุข', 'สนุก', 'ผ่อนคลาย', 'ภูมิใจ', 'สำเร็จ', 'ดีใจ', 'รักเลย', 'ชอบมาก', 'สดใส', 'ยินดี'];
    final negativeWords = ['เสียใจ', 'เศร้า', 'โกรธ', 'เหนื่อย', 'เบื่อ', 'กังวล', 'เครียด', 'ผิดหวัง', 'ปวดหัว', 'หดหู่', 'ท้อแท้'];
    final negationWords = ['ไม่', 'ไม่ได้', 'ไม่ค่อย', 'ยัง'];

    int positiveCount = 0;
    int negativeCount = 0;

    for (final word in positiveWords) {
      if (_containsWordWithNegation(text, word, negationWords)) {
        negativeCount++;
      } else if (text.contains(word)) {
        positiveCount++;
      }
    }
    for (final word in negativeWords) {
      if (_containsWordWithNegation(text, word, negationWords)) {
        positiveCount++;
      } else if (text.contains(word)) {
        negativeCount++;
      }
    }

    double score = 0.5;
    if (entry.mood != null) {
      score = entry.mood! / 5.0;
    } else {
      final total = positiveCount + negativeCount;
      if (total > 0) score = positiveCount / total;
    }

    String label;
    String emoji;
    if (score >= 0.65) {
      label = 'บวก'; emoji = '😊';
    } else if (score >= 0.35) {
      label = 'ปานกลาง'; emoji = '😐';
    } else {
      label = 'ลบ'; emoji = '😔';
    }

    return SentimentAnalysis(
      score: score,
      label: label,
      emoji: emoji,
      keywords: _extractKeywords(text),
    );
  }

  // ============================================================================
  // PART 3: Deferred Processing (จาก chat_summary_service.dart)
  // ============================================================================

  void _startBatteryMonitoring() {
    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
      if (state == BatteryState.charging || state == BatteryState.full) {
        _processPendingSummaries();
      }
    });
  }

  void _startQueueChecker() {
    _queueCheckTimer?.cancel();
    _queueCheckTimer = Timer.periodic(
      const Duration(minutes: _queueCheckIntervalMinutes),
      (_) => _checkQueue(),
    );
  }

  Future<void> _checkQueue() async {
    if (_isProcessing) return;

    try {
      final pending = await _getPendingSummaries();
      if (pending.isEmpty) return;

      final batteryState = await _battery.batteryState;
      final isCharging = batteryState == BatteryState.charging || batteryState == BatteryState.full;

      for (final job in pending) {
        final age = DateTime.now().difference(job.createdAt);
        final shouldProcess = (isCharging && age.inHours >= 6) || age.inHours >= _maxWaitHours;

        if (shouldProcess) {
          await _processSummaryJob(job);
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking queue: $e');
    }
  }

  Future<void> _checkSummaryThreshold() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSummaryStr = prefs.getString(_lastSummaryTimeKey);

      if (lastSummaryStr != null) {
        final lastSummary = DateTime.parse(lastSummaryStr);
        if (DateTime.now().difference(lastSummary).inHours < _summaryThresholdHours) {
          return;
        }
      }

      final history = await _loadChatHistory(since: lastSummaryStr);
      if (history.length < _messageThreshold) return;

      await _createSummaryJob(history);
      await _clearProcessedHistory();
    } catch (e) {
      debugPrint('❌ Error checking threshold: $e');
    }
  }

  Future<void> _createSummaryJob(List<ServiceChatMessage> history) async {
    final prefs = await SharedPreferences.getInstance();
    final job = SummaryJob(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      messages: history,
      status: SummaryStatus.pending,
    );

    final pending = prefs.getStringList(_pendingSummariesKey) ?? [];
    pending.add(jsonEncode(job.toJson()));
    await prefs.setStringList(_pendingSummariesKey, pending);
    await prefs.setString(_lastSummaryTimeKey, DateTime.now().toIso8601String());

    debugPrint('📋 Created summary job: ${job.id} (${history.length} messages)');
  }

  Future<void> _processPendingSummaries() async {
    if (_isProcessing) return;
    final pending = await _getPendingSummaries();
    for (final job in pending) {
      await _processSummaryJob(job);
    }
  }

  Future<void> _processSummaryJob(SummaryJob job) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      debugPrint('🤖 Processing summary ${job.id}...');

      final llm = MediaPipeLLMService();
      if (!llm.isInitialized) {
        _isProcessing = false;
        return;
      }

      final conversation = job.messages
          .map((m) => '${m.role == 'user' ? 'User' : 'Haku'}: ${m.content}')
          .join('\n');

      final prompt = PromptBuilder.buildDailySummaryPrompt(
        entriesContent: conversation,
        period: 'ช่วง 24 ชั่วโมง',
      );

      final summary = await llm.generate(prompt);
      await _saveSummaryResult(job, summary);
      await _removeFromQueue(job.id);

      debugPrint('✅ Summary completed: ${job.id}');
    } catch (e) {
      debugPrint('❌ Error processing summary: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _saveSummaryResult(SummaryJob job, String summary) async {
    final prefs = await SharedPreferences.getInstance();
    final summaries = await _loadSummaries();

    summaries.add(ChatSummary(
      date: job.createdAt,
      summary: summary,
      messageCount: job.messages.length,
    ));

    // เก็บแค่ 30 วัน
    while (summaries.length > 30) {
      summaries.removeAt(0);
    }

    await prefs.setString(
      _chatSummariesKey,
      jsonEncode(summaries.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> _removeFromQueue(String jobId) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingSummariesKey) ?? [];
    pending.removeWhere((json) {
      final data = jsonDecode(json);
      return data['id'] == jobId;
    });
    await prefs.setStringList(_pendingSummariesKey, pending);
  }

  Future<void> _clearProcessedHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chatHistoryKey);
  }

  // ============================================================================
  // Storage Helpers
  // ============================================================================

  Future<List<ServiceChatMessage>> _loadChatHistory({String? since}) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_chatHistoryKey) ?? [];
    final sinceTime = since != null ? DateTime.parse(since) : null;

    return historyJson
        .map((json) => ServiceChatMessage.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .where((m) => sinceTime == null || m.timestamp.isAfter(sinceTime))
        .toList();
  }

  Future<List<ChatSummary>> _loadSummaries() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_chatSummariesKey);
    if (json == null) return [];

    try {
      final List<dynamic> data = jsonDecode(json) as List<dynamic>;
      return data.map((d) => ChatSummary.fromJson(d as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  // ============================================================================
  // Public API for Worker Service
  // ============================================================================

  /// 📋 ดึง raw history ทั้งหมด (สำหรับ Worker)
  Future<List<ServiceChatMessage>> getRawHistory() async => _loadChatHistory();

  /// ⚡ บังคับประมวลผลสรุปทันที (สำหรับ Worker)
  Future<void> forceProcess() async => _processPendingSummaries();

  Future<List<SummaryJob>> _getPendingSummaries() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingJson = prefs.getStringList(_pendingSummariesKey) ?? [];

    return pendingJson
        .map((json) => SummaryJob.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .where((j) => j.status == SummaryStatus.pending)
        .toList();
  }

  // ============================================================================
  // Fallback Methods
  // ============================================================================

  String _fallbackSummarizeEntry(Entry entry) {
    if (entry.content.length < 100) return entry.content;
    final sentences = entry.content
        .split(RegExp(r'[.!?。！？\n]'))
        .where((s) => s.trim().isNotEmpty)
        .take(2)
        .join('... ');
    return sentences.isNotEmpty ? '$sentences...' : '${entry.content.substring(0, min(100, entry.content.length))}...';
  }

  String _fallbackSummarizeEntries(List<Entry> entries, {String? period}) {
    final count = entries.length;
    final moods = entries.where((e) => e.mood != null).map((e) => e.mood!).toList();
    final avgMood = moods.isNotEmpty ? moods.reduce((a, b) => a + b) / moods.length : null;

    String moodText = '';
    if (avgMood != null) {
      if (avgMood >= 4) {
        moodText = ' ดูเหมือนจะเป็นวันที่ดีนะคะ 😊';
      } else if (avgMood <= 2) {
        moodText = ' ดูเหมือนวันนี้จะเหนื่อยหน่อยนะคะ 💪';
      } else {
        moodText = ' วันนี้ก็ผ่านไปได้ด้วยดีค่ะ 😌';
      }
    }

    return '${period ?? 'วันนี้'}คุณมี $count บันทึก$moodText';
  }

  List<String> _fallbackExtractInsights(Entry entry) {
    final insights = <String>[];
    if (entry.tags.isNotEmpty) insights.add('แท็ก: ${entry.tags.take(3).join(', ')}');
    if (entry.locationName != null) insights.add('สถานที่: ${entry.locationName}');
    if (entry.mood != null) {
      final moodInfo = Entry.getMoodInfo(entry.mood);
      insights.add('อารมณ์: ${moodInfo['label']} ${moodInfo['emoji']}');
    }
    if (insights.isEmpty) {
      insights.add('เริ่มต้นด้วย: "${entry.content.split(' ').take(5).join(' ')}..."');
    }
    return insights;
  }

  bool _containsWordWithNegation(String text, String word, List<String> negations) {
    for (final neg in negations) {
      if (text.contains('$neg$word') || text.contains('$neg $word')) return true;
    }
    return false;
  }

  List<String> _extractKeywords(String text) {
    final stopWords = {'จะ', 'ใน', 'ที่', 'ของ', 'และ', 'เป็น', 'ได้', 'ก็', 'ให้', 'ว่า', 'มี', 'the', 'a', 'is', 'and', 'แล้ว', 'ไป', 'มา', 'อยู่', 'กับ', 'จาก', 'ไม่'};
    final words = text.toLowerCase()
        .replaceAll(RegExp(r'[^\u0E00-\u0E7Fa-z0-9\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .toList();

    final frequency = <String, int>{};
    for (final w in words) {
      frequency[w] = (frequency[w] ?? 0) + 1;
    }

    final sorted = frequency.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) => e.key).toList();
  }
}

// ============================================================================
// Data Models
// ============================================================================

/// Chat message for internal service use (avoids conflict with models/chat_message.dart)
class ServiceChatMessage {
  final DateTime timestamp;
  final String role;      // 'user' | 'assistant' | 'system'
  final String content;
  final String? intent;

  ServiceChatMessage({
    required this.timestamp,
    required this.role,
    required this.content,
    this.intent,
  });

  factory ServiceChatMessage.fromJson(Map<String, dynamic> json) => ServiceChatMessage(
        timestamp: DateTime.parse(json['timestamp'] as String),
        role: json['role'] as String,
        content: json['content'] as String,
        intent: json['intent'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'role': role,
        'content': content,
        'intent': intent,
      };
}

class ChatSummary {
  final DateTime date;
  final String summary;
  final int messageCount;

  ChatSummary({
    required this.date,
    required this.summary,
    required this.messageCount,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> json) => ChatSummary(
        date: DateTime.parse(json['date'] as String),
        summary: json['summary'] as String,
        messageCount: json['messageCount'] as int,
      );

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'summary': summary,
        'messageCount': messageCount,
      };
}

class SummaryJob {
  final String id;
  final DateTime createdAt;
  final List<ServiceChatMessage> messages;
  final SummaryStatus status;

  SummaryJob({
    required this.id,
    required this.createdAt,
    required this.messages,
    required this.status,
  });

  factory SummaryJob.fromJson(Map<String, dynamic> json) => SummaryJob(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        messages: (json['messages'] as List<dynamic>)
            .map((m) => ServiceChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
        status: SummaryStatus.values.byName(json['status'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'status': status.name,
      };
}

enum SummaryStatus { pending, processing, completed, failed }

class SentimentAnalysis {
  final double score;
  final String label;
  final String emoji;
  final List<String> keywords;

  SentimentAnalysis({
    required this.score,
    required this.label,
    required this.emoji,
    required this.keywords,
  });
}
