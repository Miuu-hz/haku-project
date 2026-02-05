// 🎯 Prompt Builder สำหรับ Gemma-3 และ LLM อื่นๆ
//
// รองรับ:
// - Gemma-3 format (<start_of_turn>)
// - System prompt + Context + User message
// - ควบคุมความยาวและ style ของคำตอบ

class PromptBuilder {
  /// 📝 System Prompt หลักของ Haku
  static const String hakuSystemPrompt = '''คุณคือ "ฮาคุ" (箱) AI ผู้ช่วยส่วนตัวในแอพบันทึกประจำวัน

บุคลิก:
- พูดภาษาไทยเป็นหลัก สุภาพ เป็นกันเอง
- ตอบกระชับ 2-4 ประโยค (ไม่เกิน 100 คำ)
- ใช้อิโมจิ 1-2 ตัวต่อข้อความ
- เข้าใจอารมณ์และให้กำลังใจเมื่อเหมาะสม
- อ้างอิงข้อมูลจากบันทึกของผู้ใช้เมื่อมี context

สิ่งที่ต้องทำ:
- ตอบคำถามเกี่ยวกับบันทึกของผู้ใช้
- สรุปวัน/สัปดาห์ให้กระชับ
- ให้กำลังใจและคำแนะนำเบาๆ
- จำรายละเอียดจาก context ที่ให้มา

สิ่งที่ห้ามทำ:
- ตอบยาวเกินไป
- แต่งเรื่องที่ไม่มีใน context
- ถามคำถามกลับมากเกินไป''';

  /// 🔨 สร้าง prompt สำหรับ Gemma-3
  ///
  /// Format: <start_of_turn>user\n...<end_of_turn>\n<start_of_turn>model\n
  static String buildGemmaPrompt({
    required String userMessage,
    String? context,
    String? systemPrompt,
  }) {
    final system = systemPrompt ?? hakuSystemPrompt;

    // สร้าง full prompt ที่รวม system + context
    final contextSection = context != null && context.isNotEmpty
        ? '\n\n📋 ข้อมูลจากบันทึก:\n$context'
        : '';

    return '''<start_of_turn>user
$system$contextSection

คำถาม: $userMessage<end_of_turn>
<start_of_turn>model
''';
  }

  // 📅 Prompt สำหรับสรุปวัน
  static String buildDailySummaryPrompt({
    required String entriesContent,
    String? period,
    String? context,
  }) {
    final contextSection = context != null && context.isNotEmpty
        ? '\n\n📋 บริบทเพิ่มเติม:\n$context'
        : '';
    
    return '''<start_of_turn>user
คุณคือฮาคุ ช่วยสรุปบันทึกให้กระชับ 3-5 ประโยค พร้อมอิโมจิ

บันทึก${period ?? 'วันนี้'}:
$entriesContent$contextSection

สรุป:<end_of_turn>
<start_of_turn>model
''';
  }

  /// 🔔 Prompt สำหรับ Proactive Message
  static String buildProactivePrompt({
    required String triggerContext,
    required String suggestedMessage,
    String? context,
  }) {
    final extraContext = context != null && context.isNotEmpty
        ? '\n\n📋 ข้อมูลจากบันทึก:\n$context'
        : '';
    
    return '''<start_of_turn>user
คุณคือฮาคุ กำลังทักทายผู้ใช้ ตอบสั้นๆ 1-2 ประโยค พร้อมอิโมจิ

บริบท:
$triggerContext$extraContext

ทักทาย: $suggestedMessage<end_of_turn>
<start_of_turn>model
''';
  }

  /// 📊 Prompt สำหรับวิเคราะห์ข้อมูล
  static String buildAnalysisPrompt({
    required String content,
    required String analysisType,
    String? context,
  }) {
    final contextSection = context != null && context.isNotEmpty
        ? '\n\n📋 บริบทจากบันทึกอื่น:\n$context'
        : '';
    
    return '''<start_of_turn>user
วิเคราะห์ข้อมูลต่อไปนี้แบบ $analysisType ตอบกระชับ

$content$contextSection<end_of_turn>
<start_of_turn>model
''';
  }

  /// 📝 Prompt สำหรับ Scheduler (ดึง event จากข้อความ)
  static String buildSchedulerPrompt(String text) => '''<start_of_turn>user
วิเคราะห์ข้อความและดึงข้อมูลกิจกรรม ตอบเป็น JSON เท่านั้น:
{"title": "ชื่อกิจกรรม", "date": "YYYY-MM-DD", "time": "HH:MM", "duration_minutes": number, "location": "สถานที่"}
ถ้าไม่มีข้อมูลใดให้ใส่ null

ข้อความ: $text<end_of_turn>
<start_of_turn>model
''';

  /// 📝 Prompt สำหรับสรุป Entry
  static String buildSummarizeEntryPrompt(String content, {String? context}) {
    final contextSection = context != null && context.isNotEmpty
        ? '\n\n📋 บริบทที่เกี่ยวข้อง:\n$context'
        : '';
    
    return '''<start_of_turn>user
สรุปบันทึกนี้ให้กระชับ 2-3 ประโยค พร้อมอิโมจิ ถ้ามีอารมณ์ให้ระบุด้วย

บันทึก:
$content$contextSection<end_of_turn>
<start_of_turn>model
''';
  }

  /// 🔍 Prompt สำหรับดึง Insights
  static String buildInsightsPrompt(String content, {String? context}) {
    final contextSection = context != null && context.isNotEmpty
        ? '\n\n📋 บริบทเพิ่มเติม:\n$context'
        : '';
    
    return '''<start_of_turn>user
ดึง 3-5 ประเด็นสำคัญจากบันทึกนี้ ตอบเป็นรายการ:
- ประเด็น 1
- ประเด็น 2
...

บันทึก:
$content$contextSection<end_of_turn>
<start_of_turn>model
''';
  }
}
