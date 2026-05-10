import 'package:flutter/foundation.dart';

import '../models/llm_model_config.dart';

/// 🔌 LLM Provider — Abstract Interface
///
/// Abstraction layer สำหรับ LLM ทุกชนิด ทั้ง on-device (MediaPipe)
/// และ cloud (Gemini, Claude, OpenAI) ผ่าน API tunnel
///
/// ทุก call site ใน app จะใช้ interface นี้แทน MediaPipeLLMService ตรงๆ

abstract class LLMProvider {
  /// ชื่อ provider สำหรับแสดงใน UI
  String get providerName;

  /// โมเดลพร้อมใช้งานหรือยัง
  bool get isInitialized;

  /// กำลังโหลดโมเดลอยู่
  bool get isLoading;

  /// Model config ปัจจุบัน
  LLMModelConfig get modelConfig;

  /// 🚀 Initialize provider
  ///
  /// สำหรับ on-device: โหลดโมเดลจากไฟล์
  /// สำหรับ cloud: ตรวจสอบ connection + health check
  Future<bool> initialize({int? maxTokens});

  /// 💬 Generate text จาก prompt
  Future<String> generate(String prompt);

  /// 🗑️ ปิด/cleanup resources
  Future<void> dispose();
}

/// 🧪 Mock LLM Provider — สำหรับ fallback เมื่อไม่มี LLM พร้อมใช้
class MockLLMProvider implements LLMProvider {
  bool _initialized = false;

  @override
  String get providerName => 'Mock (Offline)';

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isLoading => false;

  @override
  LLMModelConfig get modelConfig => LLMModelConfig.unknown;

  @override
  Future<bool> initialize({int? maxTokens}) async {
    _initialized = true;
    debugPrint('🧪 Mock LLM Provider initialized');
    return true;
  }

  @override
  Future<String> generate(String prompt) async {
    // Simple keyword-based responses for offline mode
    final lower = prompt.toLowerCase();

    if (lower.contains('สวัสดี') || lower.contains('hello')) {
      return 'สวัสดีค่ะ! วันนี้เป็นยังไงบ้างคะ? 😊';
    }
    if (lower.contains('ขอบคุณ')) {
      return 'ยินดีค่ะ! 💜';
    }
    if (lower.contains('สรุป') || lower.contains('summary')) {
      return 'ขอโทษค่ะ ตอนนี้อยู่ในโหมดออฟไลน์ ยังไม่สามารถสรุปข้อมูลได้ค่ะ';
    }

    return 'รับทราบค่ะ! ตอนนี้อยู่ในโหมดออฟไลน์ เชื่อมต่อ LLM เพื่อใช้งานเต็มรูปแบบนะคะ 📱';
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
