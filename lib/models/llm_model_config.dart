
/// 🧠 LLM Model Configuration
///
/// กำหนดพารามิเตอร์สำหรับแต่ละโมเดลแบบ dynamic
/// แทนการ hardcode ค่าต่างๆ ในแอพ
class LLMModelConfig {
  final String modelId;
  final String displayName;
  final int maxNumTokens; // Total context window for LiteRT engine
  final int maxContextTokens; // Token budget for ContextBuilder
  final int maxContextChars; // Char limit for PromptBuilder context
  final int workerMaxTokens; // Max output tokens for worker tasks
  final int summaryMaxTokens; // Max output tokens for summarization
  final int faceMaxTokens; // Max output tokens for Face LLM
  final double defaultTemperature;
  final int defaultTopK;
  final double defaultTopP;
  final bool supportsSystemInstruction;

  const LLMModelConfig({
    required this.modelId,
    required this.displayName,
    required this.maxNumTokens,
    required this.maxContextTokens,
    required this.maxContextChars,
    required this.workerMaxTokens,
    required this.summaryMaxTokens,
    required this.faceMaxTokens,
    this.defaultTemperature = 0.8,
    this.defaultTopK = 40,
    this.defaultTopP = 0.95,
    this.supportsSystemInstruction = false,
  });

  /// Gemma 4 models รองรับ vision (load ด้วย visionBackend=GPU) และ thinking tags
  bool get supportsVision => modelId.contains('gemma-4') || modelId.contains('gemma4');
  bool get supportsThinking => modelId.contains('gemma-4') || modelId.contains('gemma4');

  /// Gemma 3 1B (small, conservative)
  static const gemma3_1b = LLMModelConfig(
    modelId: 'gemma-3-1b',
    displayName: 'Gemma 3 1B',
    maxNumTokens: 1024,
    maxContextTokens: 600,
    maxContextChars: 400,
    workerMaxTokens: 100,
    summaryMaxTokens: 100,
    faceMaxTokens: 512,
    defaultTemperature: 0.8,
    defaultTopK: 40,
    defaultTopP: 0.95,
    supportsSystemInstruction: false,
  );

  /// Gemma 4 E2B (medium context)
  static const gemma4E2b = LLMModelConfig(
    modelId: 'gemma-4-e2b',
    displayName: 'Gemma 4 E2B',
    maxNumTokens: 4096,
    maxContextTokens: 2048,
    maxContextChars: 1500,
    workerMaxTokens: 256,
    summaryMaxTokens: 256,
    faceMaxTokens: 1024,
    defaultTemperature: 0.8,
    defaultTopK: 40,
    defaultTopP: 0.95,
    supportsSystemInstruction: true,
  );

  /// Gemma 4 E4B (larger context)
  static const gemma4E4b = LLMModelConfig(
    modelId: 'gemma-4-e4b',
    displayName: 'Gemma 4 E4B',
    maxNumTokens: 8192,
    maxContextTokens: 4096,
    maxContextChars: 3000,
    workerMaxTokens: 512,
    summaryMaxTokens: 512,
    faceMaxTokens: 1024,
    defaultTemperature: 0.8,
    defaultTopK: 40,
    defaultTopP: 0.95,
    supportsSystemInstruction: true,
  );

  /// Cloud LLM (generous defaults)
  static const cloud = LLMModelConfig(
    modelId: 'cloud',
    displayName: 'Cloud LLM',
    maxNumTokens: 8192,
    maxContextTokens: 4096,
    maxContextChars: 3000,
    workerMaxTokens: 512,
    summaryMaxTokens: 512,
    faceMaxTokens: 1024,
    defaultTemperature: 0.7,
    defaultTopK: 40,
    defaultTopP: 0.95,
    supportsSystemInstruction: true,
  );

  /// Fallback
  static const unknown = LLMModelConfig(
    modelId: 'unknown',
    displayName: 'Unknown Model',
    maxNumTokens: 2048,
    maxContextTokens: 1024,
    maxContextChars: 800,
    workerMaxTokens: 128,
    summaryMaxTokens: 128,
    faceMaxTokens: 512,
    defaultTemperature: 0.8,
    defaultTopK: 40,
    defaultTopP: 0.95,
    supportsSystemInstruction: false,
  );

  /// Auto-detect from filename
  static LLMModelConfig detect(String filename) {
    final lower = filename.toLowerCase();
    if (lower.contains('gemma-4-e4b') || lower.contains('gemma4-e4b')) {
      return gemma4E4b;
    }
    if (lower.contains('gemma-4-e2b') || lower.contains('gemma4-e2b')) {
      return gemma4E2b;
    }
    if (lower.contains('gemma-4') || lower.contains('gemma4')) {
      return gemma4E4b;
    }
    if (lower.contains('gemma-3') || lower.contains('gemma3')) {
      return gemma3_1b;
    }
    if (lower.endsWith('.litertlm')) return gemma4E4b;
    if (lower.endsWith('.task')) return gemma3_1b;
    return unknown;
  }

  LLMModelConfig copyWith({
    String? modelId,
    String? displayName,
    int? maxNumTokens,
    int? maxContextTokens,
    int? maxContextChars,
    int? workerMaxTokens,
    int? summaryMaxTokens,
    int? faceMaxTokens,
    double? defaultTemperature,
    int? defaultTopK,
    double? defaultTopP,
    bool? supportsSystemInstruction,
  }) =>
      LLMModelConfig(
        modelId: modelId ?? this.modelId,
        displayName: displayName ?? this.displayName,
        maxNumTokens: maxNumTokens ?? this.maxNumTokens,
        maxContextTokens: maxContextTokens ?? this.maxContextTokens,
        maxContextChars: maxContextChars ?? this.maxContextChars,
        workerMaxTokens: workerMaxTokens ?? this.workerMaxTokens,
        summaryMaxTokens: summaryMaxTokens ?? this.summaryMaxTokens,
        faceMaxTokens: faceMaxTokens ?? this.faceMaxTokens,
        defaultTemperature: defaultTemperature ?? this.defaultTemperature,
        defaultTopK: defaultTopK ?? this.defaultTopK,
        defaultTopP: defaultTopP ?? this.defaultTopP,
        supportsSystemInstruction:
            supportsSystemInstruction ?? this.supportsSystemInstruction,
      );

  @override
  String toString() =>
      'LLMModelConfig($modelId: maxNum=$maxNumTokens, ctxTok=$maxContextTokens, '
      'ctxChars=$maxContextChars, worker=$workerMaxTokens, face=$faceMaxTokens)';
}
