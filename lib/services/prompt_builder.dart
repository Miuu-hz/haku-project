// 🎯 Prompt Builder สำหรับ Haku AI (MediaPipe / Gemma-3)
//
// ⚡ Tip: ใช้ภาษาอังกฤษใน System Instruction หลักจะช่วยลด Token และ Model เข้าใจ Logic ได้ดีกว่า
// แต่เราสั่งให้ตอบกลับ (Response) เป็นภาษาไทย

class PromptBuilder {
  /// 🧬 System Prompt หลักของ Haku (English = better token efficiency)
  static const String hakuSystemPrompt = r'''
You are "Haku", a Private Life OS on the user's phone.
Role: Smart, Minimalist, Empathetic, Proactive. Offline-first privacy.

RULES:
1. Analyze user input.
2. Output ONLY raw JSON. NO Markdown blocks (```json). NO introductory text.
3. If user shares an event -> "type": "log"
4. If user asks to schedule -> "type": "schedule"
5. If casual talk -> "type": "chat"
6. "response" field MUST be in Thai (Short, Natural, Friendly).

JSON SCHEMA:
{
  "type": "log" | "schedule" | "chat",
  "data": {
    "activity": "String?",
    "location": "String?",
    "mood": "int (1-10)?",
    "tags": ["String"],
    "summary": "String",
    "schedule_time": "YYYY-MM-DD HH:MM"
  },
  "response": "Thai string"
}
''';

  /// 🔨 Helper ดึงเวลาปัจจุบัน (จำเป็นมากสำหรับ AI)
  static String get _currentDateTime => DateTime.now().toString().substring(0, 16);

  /// 🗣️ General Chat & Log (Main Loop)
  static String buildGemmaPrompt({
    required String userMessage,
    String? context,
  }) {
    // Inject เวลาปัจจุบันเสมอ เพื่อให้ AI รู้ว่า "เย็นนี้", "พรุ่งนี้" คือเมื่อไหร่
    final timeContext = 'Current DateTime: $_currentDateTime';
    
    final contextSection = context != null && context.isNotEmpty
        ? '\nContext (Retrieval):\n$context\n(Use this context ONLY if relevant)'
        : '';

    return '<start_of_turn>user\n$hakuSystemPrompt\n$timeContext$contextSection\n\nInput: $userMessage<end_of_turn>\n<start_of_turn>model\n';
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
  }) {
    final now = _currentDateTime;
    
    return '<start_of_turn>user\nRole: Daily Summarizer. Current Date: $now\nTask: Summarize these entries in 3-5 sentences with emoji.\n\nEntries${period != null ? ' ($period)' : ''}:\n$entriesContent\n\nOutput JSON ONLY:\n{\n  "type": "chat",\n  "response": "Thai summary with emoji"\n}<end_of_turn>\n<start_of_turn>model\n';
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
