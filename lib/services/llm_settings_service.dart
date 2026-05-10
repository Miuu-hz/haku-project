
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/llm_model_config.dart';

/// 🎛️ LLM Settings Service
///
/// จัดการการตั้งค่า LLM ที่ user ปรับเอง (override ค่า default ของ model)
/// เก็บใน SharedPreferences แยกตาม modelId
class LlmSettingsService {
  static final LlmSettingsService _instance = LlmSettingsService._internal();
  factory LlmSettingsService() => _instance;
  LlmSettingsService._internal();

  static const String _prefPrefix = 'llm_settings_';

  /// โหลดค่าที่ user ปรับ รวมกับ default ของ model
  Future<LLMModelConfig> loadEffectiveConfig(LLMModelConfig baseConfig) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefPrefix${baseConfig.modelId}';

    final maxTokens = prefs.getInt('${key}_maxTokens');
    final temperature = prefs.getDouble('${key}_temperature');
    final topK = prefs.getInt('${key}_topK');
    final topP = prefs.getDouble('${key}_topP');

    return baseConfig.copyWith(
      maxNumTokens: maxTokens,
      defaultTemperature: temperature,
      defaultTopK: topK,
      defaultTopP: topP,
    );
  }

  /// บันทึกค่าที่ user ปรับ
  Future<void> saveOverride(
    String modelId, {
    int? maxTokens,
    double? temperature,
    int? topK,
    double? topP,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefPrefix$modelId';

    if (maxTokens != null) {
      await prefs.setInt('${key}_maxTokens', maxTokens);
    }
    if (temperature != null) {
      await prefs.setDouble('${key}_temperature', temperature);
    }
    if (topK != null) {
      await prefs.setInt('${key}_topK', topK);
    }
    if (topP != null) {
      await prefs.setDouble('${key}_topP', topP);
    }
    debugPrint('🎛️ Saved LLM override for $modelId: '
        'maxTokens=$maxTokens, temp=$temperature, topK=$topK, topP=$topP');
  }

  /// ลบ override กลับไปใช้ default
  Future<void> clearOverride(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefPrefix$modelId';
    await prefs.remove('${key}_maxTokens');
    await prefs.remove('${key}_temperature');
    await prefs.remove('${key}_topK');
    await prefs.remove('${key}_topP');
    debugPrint('🎛️ Cleared LLM override for $modelId');
  }

  /// ตรวจสอบว่ามี override หรือไม่
  Future<bool> hasOverride(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefPrefix$modelId';
    return prefs.containsKey('${key}_maxTokens') ||
        prefs.containsKey('${key}_temperature') ||
        prefs.containsKey('${key}_topK') ||
        prefs.containsKey('${key}_topP');
  }

  /// Clamp ค่าให้อยู่ในช่วงที่ปลอดภัย
  static int clampMaxTokens(int value, LLMModelConfig config) {
    return value.clamp(512, config.maxNumTokens);
  }

  static double clampTemperature(double value) {
    return value.clamp(0.0, 2.0);
  }

  static int clampTopK(int value) {
    return value.clamp(1, 100);
  }

  static double clampTopP(double value) {
    return value.clamp(0.0, 1.0);
  }
}
