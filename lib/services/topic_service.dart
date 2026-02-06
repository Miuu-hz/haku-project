import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 📚 Topic Service - Topic Detection & Indexing
///
/// จัดกลุ่มข้อความเป็น Topics พร้อม English Summary
/// ใช้สำหรับ RAG และ Reply Context Loading
///
/// Structure:
/// - Topic: กลุ่มข้อความที่เกี่ยวข้องกัน
/// - msgRange: ช่วงข้อความที่อยู่ใน topic
/// - summary: English summary (สำหรับ AI)
/// - keywords: คำสำคัญ (สำหรับค้นหา)

class TopicService {
  static final TopicService _instance = TopicService._internal();
  factory TopicService() => _instance;
  TopicService._internal();

  static const String _topicsKey = 'chat_topics';
  static const String _indexKey = 'message_topic_index';

  List<Topic> _topics = [];
  Map<String, String> _messageIndex = {}; // messageId -> topicId

  bool _isInitialized = false;

  // Settings
  static const int minMessagesForTopic = 3;
  static const int maxTopicsStored = 50;
  static const double similarityThreshold = 0.3;

  // Getters
  List<Topic> get topics => List.unmodifiable(_topics);
  int get topicCount => _topics.length;

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadTopics();
    await _loadIndex();

    _isInitialized = true;
    debugPrint('✅ Topic Service initialized');
    debugPrint('   - Topics: ${_topics.length}');
  }

  /// 📥 Load topics
  Future<void> _loadTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_topicsKey);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json);
        _topics = list.map((e) => Topic.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading topics: $e');
    }
  }

  /// 📥 Load message index
  Future<void> _loadIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_indexKey);

      if (json != null) {
        _messageIndex = Map<String, String>.from(jsonDecode(json));
      }
    } catch (e) {
      debugPrint('⚠️ Error loading index: $e');
    }
  }

  /// 💾 Save topics
  Future<void> _saveTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _topicsKey,
        jsonEncode(_topics.map((t) => t.toJson()).toList()),
      );
      await prefs.setString(_indexKey, jsonEncode(_messageIndex));
    } catch (e) {
      debugPrint('⚠️ Error saving topics: $e');
    }
  }

  // ============================================================
  // 🔍 TOPIC DETECTION
  // ============================================================

  /// 🔍 Find or create topic for message
  ///
  /// เรียกเมื่อมีข้อความใหม่เข้ามา
  Future<Topic?> assignTopic({
    required String messageId,
    required String content,
    required int messageIndex,
  }) async {
    // 1. ลองหา existing topic ที่ match
    final existingTopic = await _findMatchingTopic(content);

    if (existingTopic != null) {
      // ขยาย range
      existingTopic.expandRange(messageIndex);
      existingTopic.addKeywords(_extractKeywords(content));
      _messageIndex[messageId] = existingTopic.id;
      await _saveTopics();
      return existingTopic;
    }

    // 2. ถ้าไม่เจอ สร้าง pending topic
    // (Worker จะมารวมและตั้งชื่อทีหลัง)
    final pendingTopic = _getOrCreatePendingTopic(messageIndex);
    pendingTopic.addKeywords(_extractKeywords(content));
    _messageIndex[messageId] = pendingTopic.id;
    await _saveTopics();

    return pendingTopic;
  }

  /// 🔍 Find matching topic
  Future<Topic?> _findMatchingTopic(String content) async {
    final contentKeywords = _extractKeywords(content);
    if (contentKeywords.isEmpty) return null;

    Topic? bestMatch;
    double bestScore = 0;

    for (final topic in _topics) {
      if (topic.isPending) continue;

      final score = _calculateSimilarity(contentKeywords, topic.keywords);
      if (score > bestScore && score >= similarityThreshold) {
        bestScore = score;
        bestMatch = topic;
      }
    }

    return bestMatch;
  }

  /// 📝 Extract keywords from text
  Set<String> _extractKeywords(String text) {
    // Remove common Thai particles and short words
    final stopWords = {
      'ครับ', 'ค่ะ', 'นะ', 'จ้า', 'จ๊ะ', 'ก็', 'แล้ว', 'ด้วย',
      'ที่', 'ของ', 'ใน', 'จะ', 'ได้', 'ไม่', 'มี', 'เป็น',
      'ว่า', 'และ', 'หรือ', 'แต่', 'ถ้า', 'เมื่อ', 'ให้',
      'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be',
    };

    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\u0E00-\u0E7Fa-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .toSet();

    return words;
  }

  /// 📊 Calculate keyword similarity (Jaccard)
  double _calculateSimilarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;

    final intersection = a.intersection(b).length;
    final union = a.union(b).length;

    return intersection / union;
  }

  /// 📝 Get or create pending topic
  Topic _getOrCreatePendingTopic(int messageIndex) {
    // หา pending topic ที่ยังใกล้กัน
    final recentPending = _topics.where((t) =>
        t.isPending &&
        (messageIndex - t.endIndex).abs() <= 5).firstOrNull;

    if (recentPending != null) {
      return recentPending;
    }

    // สร้างใหม่
    final newTopic = Topic(
      id: 'topic_${DateTime.now().millisecondsSinceEpoch}',
      name: '',
      summary: '',
      startIndex: messageIndex,
      endIndex: messageIndex,
      keywords: {},
      isPending: true,
      createdAt: DateTime.now(),
    );

    _topics.add(newTopic);
    return newTopic;
  }

  // ============================================================
  // 📋 TOPIC MANAGEMENT
  // ============================================================

  /// 📋 Get topic by message ID
  Topic? getTopicForMessage(String messageId) {
    final topicId = _messageIndex[messageId];
    if (topicId == null) return null;

    final index = _topics.indexWhere((t) => t.id == topicId);
    if (index < 0) return null;
    return _topics[index];
  }

  /// 📋 Get topic by ID
  Topic? getTopicById(String topicId) {
    final index = _topics.indexWhere((t) => t.id == topicId);
    if (index < 0) return null;
    return _topics[index];
  }

  /// 📋 Get recent topics
  List<Topic> getRecentTopics({int limit = 5}) {
    final sorted = _topics.where((t) => !t.isPending).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted.take(limit).toList();
  }

  /// 🔍 Search topics by keyword
  List<Topic> searchTopics(String query) {
    final queryKeywords = _extractKeywords(query);
    if (queryKeywords.isEmpty) return [];

    final scored = <Topic, double>{};

    for (final topic in _topics.where((t) => !t.isPending)) {
      final score = _calculateSimilarity(queryKeywords, topic.keywords);
      if (score > 0.1) {
        scored[topic] = score;
      }
    }

    final sorted = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.map((e) => e.key).toList();
  }

  /// 📊 Get topic for context (Lean format)
  String getTopicContextLean(String topicId) {
    final topic = getTopicById(topicId);
    if (topic == null) return '';

    // Topic:DoctorAppt|Range:1-15|Sum:Planning visit, feeling anxious
    return 'Topic:${topic.name}|Range:${topic.startIndex}-${topic.endIndex}|Sum:${topic.summary}';
  }

  // ============================================================
  // 👷 WORKER METHODS (Background Processing)
  // ============================================================

  /// 👷 Process pending topics (Worker calls this)
  ///
  /// รับ summaryCallback เพื่อให้ Worker ส่ง messages ไป summarize
  Future<void> processPendingTopics({
    required Future<String> Function(List<String> messages) summarizeCallback,
    required Future<String> Function(String summary) nameCallback,
    required List<String> Function(int start, int end) getMessagesCallback,
  }) async {
    final pendingTopics = _topics.where((t) => t.isPending).toList();

    for (final topic in pendingTopics) {
      // Skip if too few messages
      if (topic.messageCount < minMessagesForTopic) continue;

      try {
        // 1. Get messages in range
        final messages = getMessagesCallback(topic.startIndex, topic.endIndex);

        // 2. Summarize (English)
        final summary = await summarizeCallback(messages);

        // 3. Generate name
        final name = await nameCallback(summary);

        // 4. Update topic
        topic.name = name;
        topic.summary = summary;
        topic.isPending = false;
        topic.updatedAt = DateTime.now();

        debugPrint('✅ Processed topic: $name (${topic.startIndex}-${topic.endIndex})');
      } catch (e) {
        debugPrint('⚠️ Error processing topic ${topic.id}: $e');
      }
    }

    // Cleanup old topics
    _cleanupOldTopics();
    await _saveTopics();
  }

  /// 🔄 Update topic summary
  Future<void> updateTopicSummary(String topicId, String summary) async {
    final topic = getTopicById(topicId);
    if (topic == null) return;

    topic.summary = summary;
    topic.updatedAt = DateTime.now();
    await _saveTopics();
  }

  /// 🔄 Merge topics
  Future<void> mergeTopics(String topicId1, String topicId2) async {
    final topic1 = getTopicById(topicId1);
    final topic2 = getTopicById(topicId2);

    if (topic1 == null || topic2 == null) return;

    // Merge into topic1
    topic1.expandRange(topic2.startIndex);
    topic1.expandRange(topic2.endIndex);
    topic1.keywords.addAll(topic2.keywords);
    topic1.summary = '${topic1.summary} ${topic2.summary}';

    // Update index
    for (final entry in _messageIndex.entries) {
      if (entry.value == topicId2) {
        _messageIndex[entry.key] = topicId1;
      }
    }

    // Remove topic2
    _topics.removeWhere((t) => t.id == topicId2);
    await _saveTopics();

    debugPrint('🔗 Merged topics: $topicId1 + $topicId2');
  }

  /// 🧹 Cleanup old topics
  void _cleanupOldTopics() {
    if (_topics.length <= maxTopicsStored) return;

    // Sort by updatedAt, remove oldest
    _topics.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final removed = _topics.sublist(maxTopicsStored);

    // Remove from index
    for (final topic in removed) {
      _messageIndex.removeWhere((_, v) => v == topic.id);
    }

    _topics = _topics.take(maxTopicsStored).toList();
    debugPrint('🧹 Cleaned up ${removed.length} old topics');
  }

  /// 🗑️ Clear all
  Future<void> clearAll() async {
    _topics.clear();
    _messageIndex.clear();
    await _saveTopics();
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// 📚 Topic
class Topic {
  final String id;
  String name; // English name (short)
  String summary; // English summary
  int startIndex; // First message index
  int endIndex; // Last message index
  Set<String> keywords;
  bool isPending;
  final DateTime createdAt;
  DateTime updatedAt;

  Topic({
    required this.id,
    required this.name,
    required this.summary,
    required this.startIndex,
    required this.endIndex,
    required this.keywords,
    required this.isPending,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  factory Topic.empty() => Topic(
        id: '',
        name: '',
        summary: '',
        startIndex: 0,
        endIndex: 0,
        keywords: {},
        isPending: true,
        createdAt: DateTime.now(),
      );

  /// Message count in topic
  int get messageCount => endIndex - startIndex + 1;

  /// Expand range to include index
  void expandRange(int index) {
    if (index < startIndex) startIndex = index;
    if (index > endIndex) endIndex = index;
    updatedAt = DateTime.now();
  }

  /// Add keywords
  void addKeywords(Set<String> newKeywords) {
    keywords.addAll(newKeywords);
    // Keep only top 20 keywords
    if (keywords.length > 20) {
      keywords = keywords.take(20).toSet();
    }
  }

  factory Topic.fromJson(Map<String, dynamic> json) {
    return Topic(
      id: json['id'] as String,
      name: json['name'] as String,
      summary: json['summary'] as String,
      startIndex: json['startIndex'] as int,
      endIndex: json['endIndex'] as int,
      keywords: Set<String>.from(json['keywords'] ?? []),
      isPending: json['isPending'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'summary': summary,
        'startIndex': startIndex,
        'endIndex': endIndex,
        'keywords': keywords.toList(),
        'isPending': isPending,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
