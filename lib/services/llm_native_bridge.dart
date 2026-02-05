/// 🔌 DEPRECATED: LlamaNativeBridge
/// 
/// 📝 หมายเหตุ: ไฟล์นี้ถูกแทนที่ด้วย MediaPipeLLMBridge
/// 
/// llama.cpp + Vulkan ถูกปิดการใช้งานแล้ว 
/// ใช้ MediaPipe GenAI (mediapipe_llm_service.dart) แทน
/// 
/// เหตุผล:
/// - ไม่ต้อง compile native library (C++)
/// - ใช้ prebuilt AAR จาก Google
/// - All-in-one: มี tokenizer ในตัว
/// - รองรับ Gemma, Phi, Qwen ผ่าน LiteRT
/// 
/// วิธีใช้งานใหม่:
/// ```dart
/// import 'mediapipe_llm_service.dart';
/// 
/// final llm = MediaPipeLLMService();
/// await llm.initialize(modelFileName: 'gemma-3-270m-it.task');
/// final response = await llm.generate('สวัสดี');
/// ```

// ignore: unused_import
import 'dart:ffi';
// ignore: unused_import
import 'dart:io';
// ignore: unused_import
import 'package:flutter/foundation.dart';

/// DEPRECATED: ใช้ MediaPipeLLMService แทน
@deprecated
class LlamaNativeBridge {
  @deprecated
  static final LlamaNativeBridge _instance = LlamaNativeBridge._internal();
  @deprecated
  factory LlamaNativeBridge() => _instance;
  @deprecated
  LlamaNativeBridge._internal();

  @deprecated
  bool get isAvailable => false;

  @deprecated
  Future<bool> loadModel(String modelPath, {int contextSize = 4096, int gpuLayers = 0}) async {
    debugPrint('⚠️ LlamaNativeBridge ถูกปิดการใช้งาน - ใช้ MediaPipeLLMService แทน');
    return false;
  }

  @deprecated
  Future<String> generate(String prompt, {double temperature = 0.7, int maxTokens = 512}) async {
    debugPrint('⚠️ LlamaNativeBridge ถูกปิดการใช้งาน - ใช้ MediaPipeLLMService แทน');
    return '';
  }

  @deprecated
  void unloadModel() {
    debugPrint('⚠️ LlamaNativeBridge ถูกปิดการใช้งาน');
  }
}
