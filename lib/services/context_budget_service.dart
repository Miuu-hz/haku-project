// Context Budget Service
//
// จัดการ token budget สำหรับ Gemma 4 4B (context window 8192 tokens)
// แต่ละ slot มี hard cap — ป้องกัน context overflow

/// ประมาณ token count จากจำนวนตัวอักษร
int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  // Thai ~2 chars/token, English ~4 chars/token
  // ใช้ค่า conservative ~3 chars/token สำหรับข้อความผสม
  return (text.length / 3).ceil();
}

/// ตัด text ให้อยู่ใน token budget
String truncateToTokens(String text, int maxTokens) {
  final maxChars = maxTokens * 3;
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}…';
}

/// Token budget สำหรับแต่ละ slot ใน context
///
/// Total input: ~4100 tokens / Response: ~2000 tokens
/// Total: ~6100 / 8192 → safety margin ~2000 tokens
class ContextBudget {
  final int systemTokens;      // system instruction + persona
  final int resumeTokens;      // session resume summary
  final int calendarTokens;    // calendar events
  final int workingTokens;     // last N chat turns
  final int episodicTokens;    // FTS5 search results
  final int wikiTokens;        // knowledge pages
  final int userMessageTokens; // current user message

  const ContextBudget({
    required this.systemTokens,
    required this.resumeTokens,
    required this.calendarTokens,
    required this.workingTokens,
    required this.episodicTokens,
    required this.wikiTokens,
    required this.userMessageTokens,
  });

  int get totalInputBudget =>
      systemTokens +
      resumeTokens +
      calendarTokens +
      workingTokens +
      episodicTokens +
      wikiTokens +
      userMessageTokens;
}

/// Preset budgets ตาม intent ของ query
class ContextBudgets {
  // Default budget สำหรับ Gemma 4 4B / 8192 context
  static const ContextBudget general = ContextBudget(
    systemTokens: 300,
    resumeTokens: 300,
    calendarTokens: 200,
    workingTokens: 800,
    episodicTokens: 1000,
    wikiTokens: 1200,
    userMessageTokens: 300,
  );

  // recall query: อ่านข้อมูลเก่า → เพิ่ม wiki/episodic, ลด working
  static const ContextBudget recall = ContextBudget(
    systemTokens: 300,
    resumeTokens: 200,
    calendarTokens: 100,
    workingTokens: 300,
    episodicTokens: 1500,
    wikiTokens: 1700,
    userMessageTokens: 300,
  );

  // schedule: เน้น calendar + episodic
  static const ContextBudget schedule = ContextBudget(
    systemTokens: 300,
    resumeTokens: 200,
    calendarTokens: 500,
    workingTokens: 400,
    episodicTokens: 1500,
    wikiTokens: 700,
    userMessageTokens: 300,
  );

  // chat: สนทนาทั่วไป → เน้น working memory
  static const ContextBudget chat = ContextBudget(
    systemTokens: 300,
    resumeTokens: 300,
    calendarTokens: 100,
    workingTokens: 1200,
    episodicTokens: 800,
    wikiTokens: 1100,
    userMessageTokens: 300,
  );
}

class ContextBudgetService {
  static final ContextBudgetService _instance = ContextBudgetService._();
  ContextBudgetService._();
  factory ContextBudgetService() => _instance;

  /// เลือก budget ตาม intent (จาก PreClassifyResult หรือ SmartPreprocessor)
  ContextBudget allocate(String intent) {
    switch (intent.toLowerCase()) {
      case 'recall':
      case 'query':
      case 'search':
        return ContextBudgets.recall;
      case 'schedule':
      case 'reminder':
      case 'calendar':
        return ContextBudgets.schedule;
      case 'chat':
      case 'general':
        return ContextBudgets.chat;
      default:
        return ContextBudgets.general;
    }
  }

  /// ตัด context string ให้อยู่ใน slot budget
  String fitSlot(String text, int tokenBudget) =>
      truncateToTokens(text, tokenBudget);

  /// ตรวจสอบ token usage สำหรับ debug
  Map<String, int> audit({
    required String system,
    required String resume,
    required String calendar,
    required String working,
    required String episodic,
    required String wiki,
    required String userMessage,
  }) {
    return {
      'system': estimateTokens(system),
      'resume': estimateTokens(resume),
      'calendar': estimateTokens(calendar),
      'working': estimateTokens(working),
      'episodic': estimateTokens(episodic),
      'wiki': estimateTokens(wiki),
      'userMessage': estimateTokens(userMessage),
      'total': estimateTokens(
          '$system$resume$calendar$working$episodic$wiki$userMessage'),
    };
  }
}
