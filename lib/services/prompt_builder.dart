// 🎯 Prompt Builder สำหรับ Haku AI (Split Roles Architecture)
//
// 🎭 THE FACE (Realtime): ตอบสนทนาไทยธรรมชาติ (ไม่ใช่ JSON!)
// 👷 THE WORKER (Batch): สร้าง structured data สำหรับ RAG

import 'llm_service.dart';

class PromptBuilder {
  // ═══════════════════════════════════════════════════════════
  // 🎭 THE FACE - Realtime Chat (ตอบเป็นภาษาไทยธรรมชาติ)
  // ═══════════════════════════════════════════════════════════
  
  // ═══════════════════════════════════════════════════════════
  // 🎭 Stage 1: THE FACE — ตอบสนทนาภาษาไทยธรรมชาติ (ไม่มี actions)
  // ═══════════════════════════════════════════════════════════

  /// 🧬 System Prompt สำหรับตอบกลับผู้ใช้ (language-agnostic, ไม่มี ACTION tags)
  static const String hakuFacePrompt = r'''
You are Haku (箱), a warm personal AI assistant.

CRITICAL RULES:
- Reply in the SAME language the user writes in (Thai → Thai, English → English).
- Write exactly ONE reply (1-2 short sentences). Include one emoji.
- STOP after your reply. Do NOT write "U:", "User:", "Haku:", or any dialogue continuation.

How to respond:
1. Answer the exact question or topic the user raised. Stay focused on that topic only.
2. When user shares a future appointment or plan, confirm it was noted with the place/time.
3. When user asks about their schedule, use the Context section to answer.
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
  /// ใช้สำหรับ On-device Gemma (ต้องการ chat template tokens)
  ///
  static String buildGemmaPrompt({
    required String userMessage,
    String? context,
  }) {
    final timeContext = 'Current DateTime: $_currentDateTime';

    // ตัด context ให้พอดีกับ model config — ไม่ใช่ hardcode 400 อีกต่อไป
    String? ctx = context;
    if (ctx != null && ctx.isNotEmpty) {
      final maxChars = LLMService().modelConfig.maxContextChars;
      if (ctx.length > maxChars) {
        ctx = ctx.substring(ctx.length - maxChars);
      }
    }

    final contextSection = ctx != null && ctx.isNotEmpty
        ? '\nContext:\n$ctx'
        : '';

    // Gemma 3 1B ไม่ค่อยทำตาม "same language" rule — บังคับภาษาตรงๆ
    final langInstruction = _isThai(userMessage)
        ? 'ตอบเป็นภาษาไทยเท่านั้น 1-2 ประโยค'
        : 'Reply in English only. 1-2 sentences.';

    return '<start_of_turn>user\n$hakuFacePrompt\n$langInstruction\n$timeContext$contextSection\n\nUser: $userMessage<end_of_turn>\n<start_of_turn>model\n';
  }

  /// ตรวจว่าข้อความมี Thai characters อย่างน้อย 20%
  static bool _isThai(String text) {
    if (text.isEmpty) return false;
    final thaiCount = text.codeUnits.where((c) => c >= 0x0E00 && c <= 0x0E7F).length;
    return thaiCount / text.length > 0.20;
  }

  // ═══════════════════════════════════════════════════════════
  // 💬 Stateful LiteRT-LM — แยก System Instruction ออกจาก User Turn
  // ═══════════════════════════════════════════════════════════

  /// System Instruction สำหรับ Stateful Conversation (ตั้งครั้งเดียวต่อ session)
  ///
  /// Conversation API จัดการ template tokens เอง → ไม่ต้องใส่ <start_of_turn>
  static String buildSystemInstruction() => hakuFacePrompt;

  /// User Turn สำหรับ Stateful Conversation (ส่งทุกรอบ)
  ///
  /// ไม่มี history ใน string — Conversation จัดการ KV cache เอง
  static String buildUserTurn({
    required String userMessage,
    String? context,
  }) {
    final timeContext = 'Current DateTime: $_currentDateTime';

    String? ctx = context;
    if (ctx != null && ctx.isNotEmpty) {
      final maxChars = LLMService().modelConfig.maxContextChars;
      if (ctx.length > maxChars) ctx = ctx.substring(ctx.length - maxChars);
    }

    final contextSection = ctx != null && ctx.isNotEmpty ? '\nContext:\n$ctx' : '';
    final langInstruction = _isThai(userMessage)
        ? 'ตอบเป็นภาษาไทยเท่านั้น 1-2 ประโยค'
        : 'Reply in English only. 1-2 sentences.';

    return '$langInstruction\n$timeContext$contextSection\n\nUser: $userMessage';
  }

  /// ☁️ Stage 1: THE FACE — Cloud LLM (OpenRouter, Gemini, Claude, OpenAI)
  /// ไม่ใช้ Gemma template tokens เพราะ cloud models ไม่ต้องการ
  static String buildCloudPrompt({
    required String userMessage,
    String? context,
  }) {
    final timeContext = 'Current DateTime: $_currentDateTime';

    final contextSection = context != null && context.isNotEmpty
        ? '\n\nContext:\n$context'
        : '';

    return '$hakuFacePrompt\n$timeContext$contextSection\n\nUser: $userMessage\nHaku:';
  }

  /// 🧹 Strip Gemma template tokens + hallucinated dialogue จาก response
  static String cleanResponse(String raw) {
    var result = raw
        .replaceAll('</start_of_turn>', '')
        .replaceAll('<end_of_turn>', '')
        .replaceAll(RegExp(r'<start_of_turn>\w*'), '')
        .trim();

    // ถ้า model echo "Haku:" นำหน้า → ตัดออกทั้งหมด (อาจซ้ำหลายครั้ง)
    result = result.replaceFirst(RegExp(r'^(Haku:\s*)+'), '');

    // ตัด dialogue hallucination: Gemma 1B มักต่อบทสนทนาเอง
    // case 1: \nU: / \nUser: / \nHaku: / \nH: (multi-line dialogue)
    final dialogueCut = RegExp(r'\n\s*(U:|H:|User:|Haku:)', multiLine: true);
    final match = dialogueCut.firstMatch(result);
    if (match != null) {
      result = result.substring(0, match.start).trim();
    }

    // case 2: response ขึ้นต้นด้วย "U:" ทันที → เป็น dialogue ล้วน, คืน empty
    if (RegExp(r'^(U:|H:|User:)\s').hasMatch(result)) {
      return '';
    }

    return result;
  }

  /// 🧠 Stage 2: BIG MANAGER — Lean classification (ไม่มี RAG/context)
  static String buildManagerPrompt({required String userMessage}) {
    return '<start_of_turn>user\n$hakuManagerPrompt\nMsg: $userMessage<end_of_turn>\n<start_of_turn>model\n';
  }

  // ═══════════════════════════════════════════════════════════
  // 🔬 Pre-Classify — LLM intent from user message only (before Face)
  // ═══════════════════════════════════════════════════════════


  // ═══════════════════════════════════════════════════════════
  // 👷 THE WORKER - Batch Processing (สร้าง structured data)
  // ═══════════════════════════════════════════════════════════
  
  /// 👷 Worker: Extract structured data จาก chat (สำหรับ RAG)
  static String buildWorkerExtractPrompt(String userMessage, String aiResponse) {
    return '''<start_of_turn>user
You are a data extraction worker. Extract structured information from this conversation.

User said: "$userMessage"
AI replied: "$aiResponse"

Intent rules:
- "log"      = user sharing personal event/activity/experience (went somewhere, did something, felt something)
- "schedule" = user mentions future appointment, plan, reminder
- "query"    = user asking a question or searching for information
- "chat"     = casual greeting or small talk with no actionable info

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

  /// 🌐 Worker: Translate Thai diary entry to English (สำหรับ Vector DB + token saving)
  static String buildTranslateEntryPrompt(String thaiContent) {
    return '''<start_of_turn>user
Translate this Thai diary entry to English (max 30 words).
Keep: activities, places, people, emotions, dates.

Thai:
$thaiContent

Output ONLY the English translation, no JSON.<end_of_turn>
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
