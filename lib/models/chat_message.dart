/// 💬 Chat Message Model
///
/// ใช้เก็บข้อความในหน้าแชท รองรับหลายประเภท:
/// - User message
/// - Assistant message
/// - Proactive message (trigger)
/// - Loading indicator
/// - Error message

enum ChatMessageType {
  user,
  assistant,
  proactive,
  loading,
  error,
  welcome,
}

class ChatMessage {
  final String id;
  final ChatMessageType type;
  final String content;
  final DateTime timestamp;
  final List<String>? sources;
  final String? triggerTitle;
  final List<String>? actions; // 🆕 Actions ที่ AI ทำ

  ChatMessage({
    String? id,
    required this.type,
    required this.content,
    DateTime? timestamp,
    this.sources,
    this.triggerTitle,
    this.actions,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();

  // Getters
  bool get isUser => type == ChatMessageType.user;
  bool get isAssistant => type == ChatMessageType.assistant;
  bool get isProactive => type == ChatMessageType.proactive;
  bool get isLoading => type == ChatMessageType.loading;
  bool get isError => type == ChatMessageType.error;
  bool get isWelcome => type == ChatMessageType.welcome;
  bool get hasActions => actions != null && actions!.isNotEmpty;

  // Factory constructors
  factory ChatMessage.user(String content) => ChatMessage(
        type: ChatMessageType.user,
        content: content,
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
}
