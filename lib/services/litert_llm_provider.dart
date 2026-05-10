import '../models/llm_model_config.dart';
import 'llm_provider.dart';
import 'llm_service.dart';

/// 🤖 LiteRT LLM Provider — On-device LLM via LiteRT-LM
///
/// รองรับโมเดล:
///   - Gemma 4 E2B/E4B (.litertlm)
///   - Gemma 3 1B (.task legacy)
///   - TFLite ทั่วไป (.tflite)
///
/// Delegate ไปยัง LLMService singleton ที่คุยกับ LiteRTLMBridge (Kotlin)

class LiteRTLLMProvider implements LLMProvider {
  final LLMService _service = LLMService();

  @override
  String get providerName => 'LiteRT-LM (On-device)';

  @override
  bool get isInitialized => _service.isInitialized;

  @override
  bool get isLoading => _service.isLoading;

  @override
  LLMModelConfig get modelConfig => _service.modelConfig;

  @override
  Future<bool> initialize({int? maxTokens}) =>
      _service.initialize(maxTokens: maxTokens);

  @override
  Future<String> generate(String prompt) => _service.generate(prompt);

  @override
  Future<void> dispose() => _service.dispose();

  // ── LiteRT-specific methods (not in LLMProvider interface) ──

  /// ดึง custom model path
  Future<String?> getCustomModelPath() => _service.getCustomModelPath();

  /// ตั้ง custom model path
  Future<void> setCustomModelPath(String? path) =>
      _service.setCustomModelPath(path);

  /// ตรวจสอบ custom model
  Future<Map<String, dynamic>> validateCustomModel() =>
      _service.validateCustomModel();

  /// ข้อมูลโมเดลจาก Native
  Future<Map<dynamic, dynamic>?> getModelInfo() => _service.getModelInfo();

  /// ตรวจสอบว่าโมเดลถูกโหลดแล้วหรือยัง
  Future<bool> isModelLoaded() => _service.isModelLoaded();

  /// ยกเลิก auto-unload
  void cancelAutoUnload() => _service.cancelAutoUnload();

  /// ตั้งค่า system instruction (Gemma 4 ready)
  /// รีเซ็ต conversation อัตโนมัติ (Native side จัดการ)
  Future<void> setSystemInstruction(String instruction) =>
      _service.setSystemInstruction(instruction);

  /// Generate แบบ stateful — ใช้ KV cache ต่อ session
  /// ส่งแค่ user message (ไม่มี history ใน string)
  Future<String> generateTurn(String userMessage, {double? temperature}) =>
      _service.generateTurn(userMessage, temperature: temperature);

  /// รีเซ็ต Conversation — เรียกเมื่อเริ่ม chat session ใหม่
  Future<void> resetConversation() => _service.resetConversation();
}
