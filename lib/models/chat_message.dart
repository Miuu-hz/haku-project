/// 💬 โมเดลข้อความแชท
/// 
/// เก็บข้อมูลข้อความระหว่างผู้ใช้กับ AI
library chat_message;

class ChatMessage {
  final String id;
  final String content;
  final bool isUser;        // true = ผู้ใช้, false = AI
  final bool isLoading;     // กำลังรอคำตอบ
  final bool isProactive;   // ข้อความกระตุ้นจากระบบ (Trigger)
  final DateTime timestamp;
  final List<String>? sources;  // อ้างอิงจาก Entry ไหน (สำหรับ RAG)
  final Map<String, dynamic>? action; // สำหรับ Auto-scheduling
  final String? triggerTitle; // หัวข้อ trigger (สำหรับ proactive message)

  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    this.isLoading = false,
    this.isProactive = false,
    required this.timestamp,
    this.sources,
    this.action,
    this.triggerTitle,
  });

  /// 👤 สร้างข้อความจากผู้ใช้
  factory ChatMessage.user(String content) => ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isUser: true,
      timestamp: DateTime.now(),
    );

  /// 🤖 สร้างข้อความจาก AI
  factory ChatMessage.assistant(String content, {List<String>? sources}) => ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isUser: false,
      timestamp: DateTime.now(),
      sources: sources,
    );

  /// ⏳ ข้อความ "กำลังพิมพ์..."
  factory ChatMessage.loading() => ChatMessage(
      id: 'loading',
      content: '...',
      isUser: false,
      isLoading: true,
      timestamp: DateTime.now(),
    );

  /// 👋 ข้อความต้อนรับเริ่มต้น
  factory ChatMessage.welcome() => ChatMessage(
      id: 'welcome',
      content: 'สวัสดีค่ะ! ฮาคุพร้อมช่วยเหลือคุณแล้ว 🌸\n\n'
          'คุณสามารถถามฉันเกี่ยวกับบันทึกของคุณได้ เช่น:\n'
          '• "วันนี้กินอะไรมา?"\n'
          '• "สรุปวันนี้หน่อย"\n'
          '• "เมื่อวานไปไหนมา?"\n\n'
          'หรือเลือกคำถามสำเร็จรูปด้านล่างได้เลยค่ะ',
      isUser: false,
      timestamp: DateTime.now(),
    );

  /// ❌ ข้อความ Error
  factory ChatMessage.error(String errorMessage) => ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: errorMessage,
      isUser: false,
      timestamp: DateTime.now(),
    );

  /// 🔔 ข้อความ Proactive (จาก Trigger)
  factory ChatMessage.proactive(String content, {String? triggerTitle}) => ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isUser: false,
      isProactive: true,
      timestamp: DateTime.now(),
      triggerTitle: triggerTitle,
    );
}
