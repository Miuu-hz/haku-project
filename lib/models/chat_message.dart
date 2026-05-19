// 💬 Chat Message Model
//
// ใช้เก็บข้อความในหน้าแชท รองรับหลายประเภท:
// - User message
// - Assistant message
// - Proactive message (trigger)
// - Loading indicator
// - Error message

import 'dart:convert';

enum ChatMessageType {
  user,
  assistant,
  proactive,
  loading,
  error,
  welcome,
  searching,
  workerSummary, // Brain-Dump summary card
  confirmationCard, // 🛡️ Device command confirmation card
}

class ChatMessage {
  final String id;
  final ChatMessageType type;
  final String content;
  final DateTime timestamp;
  final List<String>? sources;
  final String? triggerTitle;
  final List<String>? actions;
  final List<String>? imagePaths; // file paths สำหรับแสดง thumbnail ในบับเบิล

  // 🛡️ Fields สำหรับ confirmation card
  final String? command;
  final Map<String, dynamic>? params;

  ChatMessage({
    String? id,
    required this.type,
    required this.content,
    DateTime? timestamp,
    this.sources,
    this.triggerTitle,
    this.actions,
    this.imagePaths,
    this.command,
    this.params,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();

  // Getters
  bool get isUser => type == ChatMessageType.user;
  bool get isAssistant => type == ChatMessageType.assistant;
  bool get isProactive => type == ChatMessageType.proactive;
  bool get isLoading => type == ChatMessageType.loading;
  bool get isError => type == ChatMessageType.error;
  bool get isWelcome => type == ChatMessageType.welcome;
  bool get isSearching => type == ChatMessageType.searching;
  bool get isWorkerSummary => type == ChatMessageType.workerSummary;
  bool get isConfirmationCard => type == ChatMessageType.confirmationCard;
  bool get hasActions => actions != null && actions!.isNotEmpty;

  // Factory constructors
  factory ChatMessage.user(String content, {List<String>? imagePaths}) => ChatMessage(
        type: ChatMessageType.user,
        content: content,
        imagePaths: imagePaths,
      );

  factory ChatMessage.assistant(
    String content, {
    List<String>? sources,
    List<String>? actions,
  }) =>
      ChatMessage(
        type: ChatMessageType.assistant,
        content: content,
        sources: sources,
        actions: actions,
      );

  factory ChatMessage.proactive(
    String content, {
    String? triggerTitle,
  }) =>
      ChatMessage(
        type: ChatMessageType.proactive,
        content: content,
        triggerTitle: triggerTitle,
      );

  factory ChatMessage.loading() => ChatMessage(
        type: ChatMessageType.loading,
        content: '',
      );

  factory ChatMessage.error(String message) => ChatMessage(
        type: ChatMessageType.error,
        content: message,
      );

  factory ChatMessage.searching(String content) => ChatMessage(
        type: ChatMessageType.searching,
        content: content,
      );

  factory ChatMessage.workerSummary(String summary) => ChatMessage(
        type: ChatMessageType.workerSummary,
        content: summary,
      );

  factory ChatMessage.confirmationCard({
    required String content,
    required String command,
    Map<String, dynamic>? params,
  }) => ChatMessage(
        type: ChatMessageType.confirmationCard,
        content: content,
        command: command,
        params: params,
      );

  factory ChatMessage.welcome() => ChatMessage(
        type: ChatMessageType.welcome,
        content: 'สวัสดีค่ะ! ฉันคือ Haku (箱) ผู้ช่วยส่วนตัวของคุณ\n\n'
            'ฉันสามารถ:\n'
            '• ตอบคำถามจากบันทึกของคุณ\n'
            '• สรุปวันของคุณ\n'
            '• ช่วยจดบันทึกและตั้งเตือน\n'
            '• รู้จักคุณมากขึ้นเรื่อยๆ\n\n'
            'ลองถามอะไรก็ได้เลยค่ะ! 💜',
      );

  ChatMessage copyWith({
    String? content,
    List<String>? sources,
    String? triggerTitle,
    List<String>? actions,
  }) =>
      ChatMessage(
        id: id,
        type: type,
        content: content ?? this.content,
        timestamp: timestamp,
        sources: sources ?? this.sources,
        triggerTitle: triggerTitle ?? this.triggerTitle,
        actions: actions ?? this.actions,
      );

  // ══════════════════════════════════════════════════
  // 💾 Persistence — บันทึก/โหลด chat history
  // ══════════════════════════════════════════════════

  /// ประเภทที่ควรบันทึก (ข้ามสถานะชั่วคราว)
  bool get isPersistable =>
      type != ChatMessageType.loading &&
      type != ChatMessageType.searching &&
      type != ChatMessageType.confirmationCard;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (sources != null) 'sources': sources,
        if (triggerTitle != null) 'triggerTitle': triggerTitle,
        if (actions != null) 'actions': actions,
        if (command != null) 'command': command,
        if (params != null) 'params': params,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        type: ChatMessageType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ChatMessageType.assistant,
        ),
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        sources: (json['sources'] as List<dynamic>?)?.cast<String>(),
        triggerTitle: json['triggerTitle'] as String?,
        actions: (json['actions'] as List<dynamic>?)?.cast<String>(),
        command: json['command'] as String?,
        params: (json['params'] as Map<String, dynamic>?)?.cast<String, dynamic>(),
      );

  /// Encode list → JSON string สำหรับ SharedPreferences
  static String encodeList(List<ChatMessage> messages) =>
      jsonEncode(messages.where((m) => m.isPersistable).map((m) => m.toJson()).toList());

  /// Decode JSON string → list จาก SharedPreferences
  static List<ChatMessage> decodeList(String json) {
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
