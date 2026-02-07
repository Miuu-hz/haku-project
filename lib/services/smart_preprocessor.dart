import 'package:flutter/foundation.dart';

import 'web_search_service.dart';
import 'user_profile_service.dart';

/// 🧠 Smart Preprocessor - ตรวจจับ Intent และเสริม Context
///
/// เนื่องจาก Gemma 3 1B เล็กเกินไปที่จะเข้าใจ structured actions
/// เราจึงใช้ keyword detection ในแอพแทน
///
/// Features:
/// - ตรวจจับคำค้นหา → เรียก Web Search อัตโนมัติ
/// - ตรวจจับชื่อผู้ใช้ → บันทึกลง UserProfile
/// - สร้าง Chat History สำหรับส่งให้ LLM

class SmartPreprocessor {
  static final SmartPreprocessor _instance = SmartPreprocessor._internal();
  factory SmartPreprocessor() => _instance;
  SmartPreprocessor._internal();

  final WebSearchService _webSearch = WebSearchService();
  final UserProfileService _userProfile = UserProfileService();

  // ============================================================
  // 🔍 KEYWORD PATTERNS
  // ============================================================

  /// คำที่บ่งบอกว่าต้องการค้นหาข้อมูล
  static final List<RegExp> _searchPatterns = [
    RegExp(r'ค้นหา(.+)', caseSensitive: false),
    RegExp(r'หา(.+)ให้หน่อย', caseSensitive: false),
    RegExp(r'หา(.+)ให้ที', caseSensitive: false),
    RegExp(r'(.+)คืออะไร', caseSensitive: false),
    RegExp(r'(.+)หมายความว่าอะไร', caseSensitive: false),
    RegExp(r'อากาศ(.*)วันนี้', caseSensitive: false),
    RegExp(r'อากาศ(.*)พรุ่งนี้', caseSensitive: false),
    RegExp(r'พยากรณ์อากาศ', caseSensitive: false),
    RegExp(r'ข่าว(.+)', caseSensitive: false),
    RegExp(r'ราคา(.+)', caseSensitive: false),
    RegExp(r'วิธี(.+)', caseSensitive: false),
    RegExp(r'สูตร(.+)', caseSensitive: false),
  ];

  /// คำที่บ่งบอกชื่อผู้ใช้
  static final List<RegExp> _namePatterns = [
    RegExp(r'ฉันชื่อ\s*(.+?)(?:\s|นะ|ค่ะ|ครับ|$)', caseSensitive: false),
    RegExp(r'ชื่อฉัน(?:คือ)?\s*(.+?)(?:\s|นะ|ค่ะ|ครับ|$)', caseSensitive: false),
    RegExp(r'เรียกฉันว่า\s*(.+?)(?:\s|นะ|ค่ะ|ครับ|$)', caseSensitive: false),
    RegExp(r'ผมชื่อ\s*(.+?)(?:\s|นะ|ค่ะ|ครับ|$)', caseSensitive: false),
  ];

  // ============================================================
  // 🚀 MAIN PREPROCESSING
  // ============================================================

  /// 🧠 Preprocess ข้อความก่อนส่งให้ LLM
  ///
  /// Returns: PreprocessResult ที่มี:
  /// - enrichedContext: ข้อมูลเสริมจาก web search, user profile
  /// - detectedIntent: intent ที่ตรวจจับได้
  Future<PreprocessResult> preprocess(
    String userMessage, {
    List<ChatHistoryItem>? recentHistory,
  }) async {
    debugPrint('🧠 SmartPreprocessor: Processing "$userMessage"');

    String enrichedContext = '';
    DetectedIntent intent = DetectedIntent.general;

    // 1. ตรวจจับและบันทึกชื่อผู้ใช้
    await _detectAndSaveName(userMessage);

    // 2. ตรวจจับว่าต้องการค้นหาข้อมูลไหม
    final searchQuery = _detectSearchIntent(userMessage);
    if (searchQuery != null) {
      debugPrint('🔍 Detected search intent: $searchQuery');
      intent = DetectedIntent.search;

      try {
        // เรียก Web Search
        final searchResult = await _webSearch.searchForAI(searchQuery);
        if (searchResult.isNotEmpty) {
          enrichedContext += '\n\n📊 ข้อมูลจากการค้นหา:\n$searchResult';
          debugPrint('✅ Web search completed');
        }
      } catch (e) {
        debugPrint('⚠️ Web search failed: $e');
      }
    }

    // 3. เพิ่ม User Identity
    final identity = _userProfile.getIdentityCard();
    if (identity.isNotEmpty) {
      enrichedContext = '👤 ผู้ใช้: $identity\n$enrichedContext';
    }

    // 4. เพิ่ม Chat History
    if (recentHistory != null && recentHistory.isNotEmpty) {
      final historyStr = _buildChatHistory(recentHistory);
      enrichedContext = '$historyStr\n$enrichedContext';
    }

    debugPrint('✅ Preprocessing complete, context length: ${enrichedContext.length}');

    return PreprocessResult(
      enrichedContext: enrichedContext.trim(),
      detectedIntent: intent,
      searchQuery: searchQuery,
    );
  }

  // ============================================================
  // 🔍 DETECTION METHODS
  // ============================================================

  /// ตรวจจับว่าต้องการค้นหาข้อมูลไหม
  String? _detectSearchIntent(String message) {
    final lower = message.toLowerCase();

    // ตรวจสอบ patterns
    for (final pattern in _searchPatterns) {
      final match = pattern.firstMatch(lower);
      if (match != null) {
        // สร้าง search query
        if (match.groupCount > 0 && match.group(1)?.isNotEmpty == true) {
          return match.group(1)!.trim();
        }
        // ถ้าไม่มี capture group ให้ใช้ข้อความเต็ม
        return message;
      }
    }

    // ตรวจสอบคำสำคัญ
    final searchKeywords = ['อากาศ', 'ข่าว', 'ราคา', 'หุ้น', 'สกุลเงิน'];
    for (final keyword in searchKeywords) {
      if (lower.contains(keyword)) {
        return message;
      }
    }

    return null;
  }

  /// ตรวจจับและบันทึกชื่อผู้ใช้
  Future<void> _detectAndSaveName(String message) async {
    for (final pattern in _namePatterns) {
      final match = pattern.firstMatch(message);
      if (match != null && match.groupCount > 0) {
        final name = match.group(1)?.trim();
        if (name != null && name.isNotEmpty && name.length < 50) {
          debugPrint('👤 Detected user name: $name');
          await _userProfile.setBasicInfo(name: name);
          return;
        }
      }
    }
  }

  /// สร้าง Chat History string
  String _buildChatHistory(List<ChatHistoryItem> history) {
    if (history.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('💬 บทสนทนาล่าสุด:');

    // เอาแค่ 6 ข้อความล่าสุด (3 รอบสนทนา)
    final recent = history.length > 6 ? history.sublist(history.length - 6) : history;

    for (final item in recent) {
      final role = item.isUser ? 'User' : 'Haku';
      // ตัดข้อความยาวเกินไป
      final content = item.content.length > 100
          ? '${item.content.substring(0, 100)}...'
          : item.content;
      buffer.writeln('$role: $content');
    }

    return buffer.toString();
  }

  // ============================================================
  // 🎯 QUICK ACTIONS
  // ============================================================

  /// ตรวจสอบว่าเป็น Quick Action ไหม (ไม่ต้องผ่าน LLM)
  QuickAction? detectQuickAction(String message) {
    final lower = message.toLowerCase();

    // สวัสดี / ทักทาย
    if (_isGreeting(lower)) {
      final userName = _userProfile.name;
      final greeting = userName.isNotEmpty
          ? 'สวัสดีค่ะ คุณ$userName! วันนี้เป็นอย่างไรบ้างคะ? 😊'
          : 'สวัสดีค่ะ! ยินดีที่ได้พบ วันนี้เป็นอย่างไรบ้างคะ? 😊';
      return QuickAction(type: QuickActionType.greeting, response: greeting);
    }

    // ถามชื่อ AI
    if (lower.contains('ชื่ออะไร') && (lower.contains('เธอ') || lower.contains('คุณ'))) {
      return QuickAction(
        type: QuickActionType.askAIName,
        response: 'ฉันชื่อ Haku ค่ะ (箱 แปลว่า "กล่อง" ในภาษาญี่ปุ่น) ยินดีที่ได้รู้จักค่ะ! 📦✨',
      );
    }

    // ถามว่าผู้ใช้ชื่ออะไร
    if ((lower.contains('ฉันชื่ออะไร') || lower.contains('ฉันคือใคร')) && _userProfile.name.isNotEmpty) {
      return QuickAction(
        type: QuickActionType.askUserName,
        response: 'คุณชื่อ ${_userProfile.name} ค่ะ! จำได้แม่นเลย 😊',
      );
    }

    return null;
  }

  bool _isGreeting(String lower) {
    final greetings = ['สวัสดี', 'หวัดดี', 'ดีจ้า', 'hello', 'hi ', 'hey'];
    return greetings.any((g) => lower.startsWith(g) || lower == g);
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// ผลลัพธ์จากการ Preprocess
class PreprocessResult {
  final String enrichedContext;
  final DetectedIntent detectedIntent;
  final String? searchQuery;

  PreprocessResult({
    required this.enrichedContext,
    required this.detectedIntent,
    this.searchQuery,
  });
}

/// Intent ที่ตรวจจับได้
enum DetectedIntent {
  general,
  search,
  schedule,
  reminder,
  navigation,
}

/// Quick Action (ตอบได้เลยไม่ต้องผ่าน LLM)
class QuickAction {
  final QuickActionType type;
  final String response;

  QuickAction({required this.type, required this.response});
}

enum QuickActionType {
  greeting,
  askAIName,
  askUserName,
}

/// Chat History Item
class ChatHistoryItem {
  final String content;
  final bool isUser;
  final DateTime timestamp;

  ChatHistoryItem({
    required this.content,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
