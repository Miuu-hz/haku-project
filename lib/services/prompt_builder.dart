// 🎯 Prompt Builder สำหรับ Haku AI (Split Roles Architecture)
//
// 🎭 THE FACE (Realtime): ตอบสนทนาไทยธรรมชาติ (ไม่ใช่ JSON!)
// 👷 THE WORKER (Batch): สร้าง structured data สำหรับ RAG

class PromptBuilder {
  // ═══════════════════════════════════════════════════════════
  // 🎭 THE FACE - Realtime Chat (ตอบเป็นภาษาไทยธรรมชาติ)
  // ═══════════════════════════════════════════════════════════
  
  // ═══════════════════════════════════════════════════════════
  // 🎭 Stage 1: THE FACE — ตอบสนทนาภาษาไทยธรรมชาติ (ไม่มี actions)
  // ═══════════════════════════════════════════════════════════

  /// 🧬 System Prompt สำหรับตอบกลับผู้ใช้ (สนทนาไทยล้วน ไม่มี ACTION tags)
  static const String hakuFacePrompt = r'''
You are "Haku" (箱), a Thai-speaking AI assistant on the user's phone.

PERSONALITY:
- Smart, empathetic, proactive but not intrusive
- Minimalist responses (1-2 sentences usually)
- Uses Thai language naturally with occasional emoji
- Remembers context from previous messages

RULES:
1. Reply in NATURAL Thai (conversational, NOT JSON)
2. Be concise but warm
3. If user shares personal info (name, preferences), acknowledge it
4. If user mentions events/locations, show you remember
5. NEVER output JSON format - just chat naturally
6. NEVER output action tags like [ACTION:...] - just answer naturally

EXAMPLE RESPONSES:
- "สวัสดีค่ะ วันนี้เป็นยังไงบ้างคะ? 😊"
- "เข้าใจค่ะ จะจำไว้ว่าคุณชื่อ Arm"
- "เหนื่อยเหรอคะ? พักผ่อนบ้างนะ 💪"
''';

  // ═══════════════════════════════════════════════════════════
  // 🧠 Stage 2: BIG MANAGER — Lean classification (ไม่มี RAG/context)
  // ═══════════════════════════════════════════════════════════

  /// 🧠 Manager Prompt — ultra-lean (~120 tokens), classify + dispatch
  static const String hakuManagerPrompt = r'''
Classify intent. Output ONE line only.
SEARCH:query - needs web search
SCHEDULE:title,date,time - has appointment
REMIND:message,time - wants reminder
PLACE:query - looking for place
NONE - just chatting

Output:''';

  /// 🔨 Helper ดึงเวลาปัจจุบัน (จำเป็นมากสำหรับ AI)
  static String get _currentDateTime => DateTime.now().toString().substring(0, 16);

  /// 🗣️ Stage 1: THE FACE — General Chat (ตอบเป็นภาษาไทยธรรมชาติ)
  static String buildGemmaPrompt({
    required String userMessage,
    String? context,
  }) {
    final timeContext = 'Current DateTime: $_currentDateTime';

    final contextSection = context != null && context.isNotEmpty
        ? '\nContext (Retrieval):\n$context\n(Use this context ONLY if relevant)'
        : '';

    return '<start_of_turn>user\n$hakuFacePrompt\n$timeContext$contextSection\n\nUser: $userMessage<end_of_turn>\n<start_of_turn>model\n';
  }

  /// 🧠 Stage 2: BIG MANAGER — Lean classification (ไม่มี RAG/context)
  static String buildManagerPrompt({required String userMessage}) {
    return '<start_of_turn>user\n$hakuManagerPrompt\nMsg: $userMessage<end_of_turn>\n<start_of_turn>model\n';
  }

  // ═══════════════════════════════════════════════════════════
  // 👷 THE WORKER - Batch Processing (สร้าง structured data)
  // ═══════════════════════════════════════════════════════════
  
  /// 👷 Worker: Extract structured data จาก chat (สำหรับ RAG)
  static String buildWorkerExtractPrompt(String userMessage, String aiResponse) {
    return '''<start_of_turn>user
You are a data extraction worker. Extract structured information from this conversation.

User said: "$userMessage"
AI replied: "$aiResponse"

Output JSON ONLY:
{
  "intent": "log|schedule|query|chat",
  "extracted_data": {
    "activity": "what user did/will do",
    "location": "where",
    "time": "when",
    "mood": 1-10,
    "tags": ["tag1", "tag2"],
    "entities": ["names", "places"]
  },
  "summary_en": "Brief English summary for RAG (max 20 words)"
}<end_of_turn>
<start_of_turn>model
''';
  }
  
  /// 👷 Worker: Summarize chat to English (สำหรับ Vector DB)
  static String buildWorkerSummarizePrompt(String chatContent) {
    return '''<start_of_turn>user
Summarize this chat in English (max 30 words) for vector search.
Focus on: what, when, where, mood.

Chat:
$chatContent

Output ONLY the summary text, no JSON.<end_of_turn>
<start_of_turn>model
''';
  }

  /// 📅 Scheduler (ต้องเพิ่ม now เพื่อคำนวณ relative date)
  static String buildSchedulerPrompt(String text) {
    // เพิ่ม DateTime.now() เข้าไปใน Prompt
    final now = _currentDateTime;
    
    return '<start_of_turn>user\nRole: Event Extractor. Current Date: $now\nTask: Extract event details from text to JSON. Calculate relative dates (tomorrow, next friday) based on Current Date.\n\nInput: $text\n\nOutput JSON ONLY (No Markdown):\n{\n  "type": "schedule",\n  "data": {\n    "title": "String",\n    "date": "YYYY-MM-DD",\n    "time": "HH:MM",\n    "location": "String?"\n  },\n  "response": "Confirm in Thai"\n}<end_of_turn>\n<start_of_turn>model\n';
  }

  /// 📝 Summarize Entry (Log)
  static String buildLogPrompt(String userMessage, {String? context}) {
    final contextSection = context != null && context.isNotEmpty
        ? '\nRelated Context: $context'
        : '';
    
    return '<start_of_turn>user\nRole: Life Logger. Analyze and categorize this event.\nContext:$contextSection\nInput: $userMessage\n\nOutput JSON ONLY:\n{\n  "type": "log",\n  "data": {\n    "activity": "String",\n    "location": "String?",\n    "mood": "int (1-10)",\n    "tags": ["Tag1", "Tag2"],\n    "summary": "Thai summary"\n  },\n  "response": "Thai empathetic reply"\n}<end_of_turn>\n<start_of_turn>model\n';
  }

  /// 📅 สรุปวัน
  static String buildDailySummaryPrompt({
    required String entriesContent,
    String? period,
    String? context,
  }) {
    final now = _currentDateTime;
    final contextSection = context != null && context.isNotEmpty
        ? '\nContext:\n$context'
        : '';

    return '<start_of_turn>user\nRole: Daily Summarizer. Current Date: $now\nTask: Summarize these entries in 3-5 sentences with emoji.\n\nEntries${period != null ? ' ($period)' : ''}:\n$entriesContent$contextSection\n\nOutput JSON ONLY:\n{\n  "type": "chat",\n  "response": "Thai summary with emoji"\n}<end_of_turn>\n<start_of_turn>model\n';
  }

  /// 🔔 Proactive Message
  static String buildProactivePrompt({
    required String triggerContext,
    required String suggestedMessage,
    String? context,
  }) {
    final now = _currentDateTime;
    final extraContext = context != null && context.isNotEmpty
        ? '\nUser Context:\n$context'
        : '';
    
    return '<start_of_turn>user\nRole: Proactive Assistant. Current Date: $now\nTrigger: $triggerContext$extraContext\nSuggested: $suggestedMessage\n\nTask: Create a short greeting (1-2 sentences, Thai, friendly, emoji).\n\nOutput JSON ONLY:\n{\n  "type": "chat",\n  "response": "Thai greeting"\n}<end_of_turn>\n<start_of_turn>model\n';
  }

  /// 📊 วิเคราะห์ข้อมูล
  static String buildAnalysisPrompt({
    required String content,
    required String analysisType,
    String? context,
  }) {
    final contextSection = context != null && context.isNotEmpty
        ? '\nContext:\n$context'
        : '';
    
    return '<start_of_turn>user\nRole: Data Analyzer. Task: $analysisType\n\nContent:\n$content$contextSection\n\nOutput JSON ONLY:\n{\n  "type": "analysis",\n  "data": {\n    "key_points": ["Point 1", "Point 2"],\n    "sentiment": "positive|neutral|negative",\n    "summary": "Brief summary"\n  },\n  "response": "Thai analysis reply"\n}<end_of_turn>\n<start_of_turn>model\n';
  }

  /// 📝 สรุป Entry
  static String buildSummarizeEntryPrompt(String content, {String? context}) {
    final contextSection = context != null && context.isNotEmpty
        ? '\nContext:\n$context'
        : '';
    
    return '<start_of_turn>user\nRole: Entry Summarizer.\n\nEntry:\n$content$contextSection\n\nOutput JSON ONLY:\n{\n  "type": "summary",\n  "data": {\n    "summary": "Thai summary",\n    "mood": "Detected mood",\n    "tags": ["Tag1", "Tag2"]\n  },\n  "response": "Thai reply with emoji"\n}<end_of_turn>\n<start_of_turn>model\n';
  }

  /// 🔍 Insights
  static String buildInsightsPrompt(String content, {String? context}) {
    final contextSection = context != null && context.isNotEmpty
        ? '\nContext:\n$context'
        : '';
    
    return '<start_of_turn>user\nRole: Insight Extractor.\n\nContent:\n$content$contextSection\n\nOutput JSON ONLY:\n{\n  "type": "insights",\n  "data": {\n    "insights": ["Insight 1", "Insight 2", "Insight 3"],\n    "patterns": ["Pattern 1"]\n  },\n  "response": "Thai summary of insights"\n}<end_of_turn>\n<start_of_turn>model\n';
  }
}
