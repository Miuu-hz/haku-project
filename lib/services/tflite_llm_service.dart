import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// 🤖 TFLite LLM Service - ใช้ Gemma-2 ผ่าน TensorFlow Lite
/// 
/// ✅ ข้อดี:
/// - Google TFLite (official)
/// - รองรับ Gemma-2 โดยเฉพาะ
/// - ไม่ใช้ Vulkan (ไม่ crash บน Samsung)
/// - มี Flutter plugin พร้อมใช้

class TfliteLLMService {
  static final TfliteLLMService _instance = TfliteLLMService._internal();
  factory TfliteLLMService() => _instance;
  TfliteLLMService._internal();

  Interpreter? _interpreter;
  
  bool _isInitialized = false;
  bool _isLoading = false;
  
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;

  /// 🚀 เริ่มต้น LLM
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    if (_isLoading) return false;
    
    _isLoading = true;
    
    try {
      // หาโมเดล
      final modelPath = await _getModelPath();
      if (modelPath == null) {
        debugPrint('❌ ไม่พบโมเดล gemma2-2b-cpu-int8.task');
        _isLoading = false;
        return false;
      }
      
      // โหลด TFLite model
      final options = InterpreterOptions()
        ..threads = 4  // ใช้ 4 cores
        ..useNnApiForAndroid = false;  // ปิด NNAPI (บางเครื่องมีปัญหา)
      
      _interpreter = Interpreter.fromFile(
        File(modelPath),
        options: options,
      );
      
      _isInitialized = true;
      debugPrint('✅ TFLite LLM loaded: $modelPath');
      return true;
      
    } catch (e) {
      debugPrint('❌ TFLite init failed: $e');
      _isLoading = false;
      return false;
    }
  }

  /// 💬 Generate text
  Future<String> generate(String prompt) async {
    if (!_isInitialized || _interpreter == null) {
      throw StateError('LLM not initialized');
    }
    
    try {
      // TODO: Tokenization + Inference
      // อันนี้ต้องใช้ Gemma Tokenizer ร่วมด้วย
      
      // Placeholder สำหรับตอนนี้
      return '[Gemma-2] ตอบ: $prompt';
      
    } catch (e) {
      debugPrint('❌ Generate error: $e');
      return '';
    }
  }

  /// 🔍 หา path โมเดล
  Future<String?> _getModelPath() async {
    const modelFile = 'gemma2-2b-it-cpu-int8.task';
    
    final appDir = await getApplicationDocumentsDirectory();
    final appPath = '${appDir.path}/models/$modelFile';
    
    if (await File(appPath).exists()) return appPath;
    
    const extPath = '/sdcard/Android/data/com.example.haku/files/models/$modelFile';
    if (await File(extPath).exists()) {
      await Directory('${appDir.path}/models').create(recursive: true);
      await File(extPath).copy(appPath);
      return appPath;
    }
    
    return null;
  }

  /// 🧹 Dispose
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
