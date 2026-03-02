import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'context_retriever.dart';
import 'mvp_trigger_service.dart';
import 'secret_chat_service.dart';

/// 💬 Place Feedback Service - จัดการถาม feedback หลังออกจากสถานที่
///
/// Flow:
/// 1. DwellTracker เสร็จ → GeofenceService เรียก PlaceFeedbackService.queueFeedback()
/// 2. User เปิดแอพ → ChatScreen เรียก dequeuePending() → _handleTrigger()
/// 3. Haku ถาม "เป็นยังไงบ้างที่ [ร้าน X]?"
/// 4. User ตอบ → _runSecretChat() → resolveSentiment() → PlaceService.updatePlaceSentiment()

class PlaceFeedbackService {
  static final PlaceFeedbackService _instance = PlaceFeedbackService._internal();
  factory PlaceFeedbackService() => _instance;
  PlaceFeedbackService._internal();

  static const String _queueKey = 'place_feedback_queue';

  List<PlaceFeedbackRequest> _queue = [];
  bool _isInitialized = false;

  // request ที่กำลัง "รอ user ตอบ" อยู่
  String? _activeRequestId;

  // ── Getters ───────────────────────────────────────────────────────

  bool get hasPending => _queue.isNotEmpty;
  String? get activeRequestId => _activeRequestId;

  PlaceFeedbackRequest? getActiveRequest() =>
      _activeRequestId == null
          ? null
          : _queue.cast<PlaceFeedbackRequest?>().firstWhere(
              (r) => r?.id == _activeRequestId,
              orElse: () => null,
            );

  // ── Init ─────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadQueue();
    _isInitialized = true;
    debugPrint('✅ PlaceFeedbackService: ${_queue.length} pending feedback(s)');
  }

  // ── Queue management ──────────────────────────────────────────────

  /// เพิ่ม feedback request เข้า queue
  ///
  /// Skip ถ้า: name=null, routine zone, หรือ placeId เดิมอยู่ใน queue ภายใน 24h
  Future<void> queueFeedback(PlaceFeedbackRequest request) async {
    await initialize();

    // dedup: ถ้า placeId นี้อยู่ใน queue ภายใน 24h → skip
    if (request.placeId != null) {
      final alreadyQueued = _queue.any(
        (r) =>
            r.placeId == request.placeId &&
            DateTime.now().difference(r.visitedAt).inHours < 24,
      );
      if (alreadyQueued) {
        debugPrint('⏭️ Place feedback: skipping duplicate (${request.placeName})');
        return;
      }
    }

    _queue.add(request);
    await _persist();
    debugPrint('📬 Queued feedback for: ${request.placeName}');
  }

  /// คืน request แรกที่รอ (FIFO, ไม่ลบออก — ลบหลัง markDelivered)
  PlaceFeedbackRequest? dequeuePending() {
    if (_queue.isEmpty) return null;
    return _queue.first;
  }

  /// Mark ว่า trigger ถูกส่งให้ user แล้ว (กำลังรอคำตอบ)
  void markAsked(String requestId) {
    _activeRequestId = requestId;
  }

  /// Mark ว่า user ตอบแล้ว (หรือ expired) — ลบออก queue
  Future<void> markDelivered(String requestId) async {
    _queue.removeWhere((r) => r.id == requestId);
    if (_activeRequestId == requestId) _activeRequestId = null;
    await _persist();
    debugPrint('✅ Place feedback delivered: $requestId');
  }

  /// ลบ request ที่เก่าเกิน 48 ชั่วโมง
  Future<void> pruneExpired() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));
    final before = _queue.length;
    _queue.removeWhere((r) => r.visitedAt.isBefore(cutoff));
    if (_queue.length != before) await _persist();
  }

  // ── Sentiment resolution ──────────────────────────────────────────

  /// วิเคราะห์ sentiment จาก user reply (rule-based, 0 LLM)
  ///
  /// ใช้ EnglishLogEntry.mood (1-5) ก่อน, fallback keyword matching
  PlaceSentiment resolveSentiment({
    EnglishLogEntry? logEntry,
    String? rawMsg,
  }) {
    // 1. LLM mood score (1–5)
    if (logEntry?.mood != null) {
      final mood = logEntry!.mood!;
      if (mood >= 4) return PlaceSentiment.liked;
      if (mood <= 2) return PlaceSentiment.disliked;
      return PlaceSentiment.neutral;
    }

    // 2. Keyword fallback (Thai + English)
    final text = '${rawMsg ?? ''} ${logEntry?.summaryEn ?? ''}'.toLowerCase();
    const positiveWords = [
      'ชอบ', 'ดี', 'อร่อย', 'สนุก', 'ประทับใจ', 'เยี่ยม', 'เพราะ',
      'like', 'good', 'love', 'great', 'nice', 'amazing', 'delicious',
    ];
    const negativeWords = [
      'ไม่ชอบ', 'แย่', 'ห่วย', 'น่าเบื่อ', 'ผิดหวัง', 'แพง', 'ไม่ดี',
      'dislike', 'bad', 'awful', 'terrible', 'boring', 'disappointing',
    ];

    if (positiveWords.any(text.contains)) return PlaceSentiment.liked;
    if (negativeWords.any(text.contains)) return PlaceSentiment.disliked;
    return PlaceSentiment.neutral;
  }

  // ── TriggerEvent builder ──────────────────────────────────────────

  /// สร้าง TriggerEvent สำหรับส่งให้ ChatNotifier
  TriggerEvent buildTriggerEvent(PlaceFeedbackRequest request) {
    final timeStr = _formatVisitTime(request.visitedAt);
    final dwellStr = request.dwellMinutes >= 60
        ? '${(request.dwellMinutes / 60).round()} ชั่วโมง'
        : '${request.dwellMinutes} นาที';

    return TriggerEvent(
      type: TriggerType.placeFeedback,
      timestamp: DateTime.now(),
      suggestedMessage:
          '${timeStr}คุณอยู่ที่ "${request.placeName}" นาน $dwellStr\n'
          'เป็นยังไงบ้างคะ? ชอบที่นั่นไหม? 😊',
      context: ContextData(
        recentEntries: [],
        timePattern: TimePattern(
          currentHour: DateTime.now().hour,
          similarEntriesCount: 0,
          commonActivities: [],
        ),
        preferences: UserPreferences.empty(),
        relatedEntries: [],
      ),
      quickReplyOptions: const ['ชอบมาก', 'โอเค', 'ไม่ค่อยชอบ'],
      payloadJson: {
        'feedbackRequestId': request.id,
        'placeId': request.placeId,
      },
    );
  }

  String _formatVisitTime(DateTime visitedAt) {
    final diff = DateTime.now().difference(visitedAt);
    if (diff.inMinutes < 90) return 'เมื่อกี้ ';
    if (diff.inHours < 6) return '${diff.inHours} ชั่วโมงที่แล้ว ';
    return 'เมื่อวานนี้ ';
  }

  // ── Persistence ────────────────────────────────────────────────────

  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_queueKey) ?? [];
      _queue = raw
          .map((j) => PlaceFeedbackRequest.fromJson(
              jsonDecode(j) as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ PlaceFeedbackService load failed: $e');
      _queue = [];
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _queueKey,
        _queue.map((r) => jsonEncode(r.toJson())).toList(),
      );
    } catch (e) {
      debugPrint('⚠️ PlaceFeedbackService persist failed: $e');
    }
  }
}

// ── Models ────────────────────────────────────────────────────────────

/// ความรู้สึกของ user ต่อสถานที่
enum PlaceSentiment { liked, disliked, neutral }

/// Request ที่รอถาม feedback
class PlaceFeedbackRequest {
  final String id;
  final String? placeId;    // SavedPlace.id (null ถ้าสถานที่ไม่มีชื่อ)
  final String placeName;   // ชื่อแสดงผล
  final DateTime visitedAt;
  final int dwellMinutes;

  PlaceFeedbackRequest({
    required this.id,
    this.placeId,
    required this.placeName,
    required this.visitedAt,
    required this.dwellMinutes,
  });

  factory PlaceFeedbackRequest.fromJson(Map<String, dynamic> json) =>
      PlaceFeedbackRequest(
        id: json['id'] as String,
        placeId: json['placeId'] as String?,
        placeName: json['placeName'] as String,
        visitedAt: DateTime.parse(json['visitedAt'] as String),
        dwellMinutes: json['dwellMinutes'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'placeId': placeId,
        'placeName': placeName,
        'visitedAt': visitedAt.toIso8601String(),
        'dwellMinutes': dwellMinutes,
      };
}
