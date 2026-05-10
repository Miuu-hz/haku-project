import '../models/llm_model_config.dart';
import 'mediapipe_llm_service.dart';
import 'llm_provider.dart';

/// 📱 MediaPipe LLM Provider — On-device SLM (Gemma 3 1B)
///
/// Wrapper ครอบ MediaPipeLLMService ที่มีอยู่ให้ implement LLMProvider interface
/// ไม่แก้ logic เดิม แค่ delegate ไปยัง singleton ที่มีอยู่

class MediaPipeLLMProvider implements LLMProvider {
  final MediaPipeLLMService _service = MediaPipeLLMService();

  @override
  String get providerName => 'Gemma 3 1B (On-device)';

  @override
  bool get isInitialized => _service.isInitialized;

  @override
  bool get isLoading => _service.isLoading;

  @override
  LLMModelConfig get modelConfig => LLMModelConfig.gemma3_1b;

  @override
  Future<bool> initialize({int? maxTokens}) =>
      _service.initialize(maxTokens: maxTokens);

  @override
  Future<String> generate(String prompt) => _service.generate(prompt);

  @override
  Future<void> dispose() => _service.dispose();

  // ── MediaPipe-specific methods (not in LLMProvider interface) ──

  /// ดึง custom model path
  Future<String?> getCustomModelPath() => _service.getCustomModelPath();

  /// ตั้ง custom model path
  Future<void> setCustomModelPath(String? path) =>
      _service.setCustomModelPath(path);

  /// ตรวจสอบ custom model
  Future<Map<String, dynamic>> validateCustomModel() =>
      _service.validateCustomModel();

  /// ข้อมูลโมเดล
  Future<Map<dynamic, dynamic>?> getModelInfo() => _service.getModelInfo();

  /// ตรวจสอบว่าโมเดลถูกโหลดแล้วหรือยัง
  Future<bool> isModelLoaded() => _service.isModelLoaded();

  /// ยกเลิก auto-unload
  void cancelAutoUnload() => _service.cancelAutoUnload();
}
