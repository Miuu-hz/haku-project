import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// 🤖 MediaPipe GenAI LLM Service - On-device LLM
/// 
/// ใช้ MediaPipe Tasks GenAI สำหรับรันโมเดล LiteRT (.task)
/// ✅ All-in-One: มี tokenizer รวมในไฟล์โมเดลแล้ว
/// ✅ รองรับ Gemma-3, Qwen, Llama ผ่าน LiteRT
/// ✅ ไม่ต้อง compile native library เอง

class MediaPipeLLMService {
  static final MediaPipeLLMService _instance = MediaPipeLLMService._internal();
  factory MediaPipeLLMService() => _instance;
  MediaPipeLLMService._internal();

  static const MethodChannel _channel = MethodChannel('com.example.haku/llm');

  bool _isInitialized = false;
  bool _isLoading = false;
  String? _currentModelPath;
  
  /// 🔋 Auto-unload timer สำหรับประหยัดแบตเตอรี่
  Timer? _autoUnloadTimer;
  
  /// ⏱️ เวลาที่ไม่ใช้งานก่อน auto-unload (นาที)
  static const int autoUnloadMinutes = 5;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get currentModelPath => _currentModelPath;

  /// 📂 อ่าน custom model path จาก SharedPreferences
  Future<String?> getCustomModelPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageKeys.customLlmModelPath);
  }

  /// 📂 บันทึก custom model path ลง SharedPreferences
  Future<void> setCustomModelPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(StorageKeys.customLlmModelPath);
    } else {
      await prefs.setString(StorageKeys.customLlmModelPath, path);
    }
  }

  /// ✅ ตรวจสอบว่าไฟล์ model มีอยู่จริงและอ่านได้
  Future<Map<String, dynamic>> validateCustomModel() async {
    final customPath = await getCustomModelPath();

    if (customPath == null || customPath.isEmpty) {
      return {'valid': false, 'message': 'ไม่ได้ระบุ custom path', 'path': null};
    }

    final file = File(customPath);

    try {
      if (!await file.exists()) {
        return {'valid': false, 'message': 'ไฟล์ไม่มีอยู่จริง', 'path': customPath};
      }

      final size = await file.length();
      if (size == 0) {
        return {'valid': false, 'message': 'ไฟล์ว่างเปล่า', 'path': customPath};
      }

      return {
        'valid': true,
        'message': 'ไฟล์พร้อมใช้งาน',
        'path': customPath,
        'size': '${(size / 1024 / 1024).toStringAsFixed(2)} MB',
      };
    } catch (e) {
      return {'valid': false, 'message': 'ไม่สามารถอ่านไฟล์ได้: $e', 'path': customPath};
    }
  }

  /// 🚀 เริ่มต้น LLM
  /// 
  /// @param modelFileName ชื่อไฟล์โมเดล (เช่น 'gemma-3-270m-it-int8.task')
  /// @param maxTokens จำนวน token สูงสุด (default: 1024)
  /// @param temperature ค่าความสร้างสรรค์ 0.0-1.0 (default: 0.7)
  Future<bool> initialize({
    String? modelFileName,
    int maxTokens = 1024,
    double temperature = 0.7,
  }) async {
    if (_isInitialized) return true;
    if (_isLoading) return false;

    _isLoading = true;

    try {
      // หา path ของโมเดล
      final modelPath = await _getModelPath(modelFileName: modelFileName);
      if (modelPath == null) {
        debugPrint('❌ ไม่พบไฟล์โมเดล .task');
        _isLoading = false;
        return false;
      }

      debugPrint('📥 Loading MediaPipe model: $modelPath');

      // เรียก native ผ่าน MethodChannel
      final success = await _channel.invokeMethod<bool>('loadModel', {
        'modelPath': modelPath,
        'maxTokens': maxTokens,
        'temperature': temperature,
      });

      _isInitialized = success ?? false;
      _currentModelPath = modelPath;
      _isLoading = false;

      if (_isInitialized) {
        debugPrint('✅ MediaPipe LLM initialized');
        // เริ่มต้น auto-unload timer
        _resetAutoUnloadTimer();
      } else {
        debugPrint('❌ Failed to initialize MediaPipe LLM');
      }

      return _isInitialized;
    } catch (e, stackTrace) {
      debugPrint('❌ MediaPipe init error: $e');
      debugPrint('Stack: $stackTrace');
      _isLoading = false;
      return false;
    }
  }

  /// 💬 Generate text
  /// 
  /// @param prompt ข้อความ input
  /// @return ข้อความที่สร้าง
  Future<String> generate(String prompt) async {
    if (!_isInitialized) {
      throw StateError('MediaPipe LLM not initialized');
    }

    // 🔋 Reset auto-unload timer เมื่อมีการใช้งาน
    _resetAutoUnloadTimer();

    try {
      debugPrint('🤖 Generating with MediaPipe...');
      
      final response = await _channel.invokeMethod<String>('generate', {
        'prompt': prompt,
      });

      debugPrint('✅ MediaPipe generated ${response?.length ?? 0} chars');
      return response ?? '';
    } catch (e, stackTrace) {
      debugPrint('❌ MediaPipe generate error: $e');
      debugPrint('Stack: $stackTrace');
      return '';
    }
  }

  /// ⏰ ตั้ง Timer สำหรับ auto-unload
  void _resetAutoUnloadTimer() {
    _autoUnloadTimer?.cancel();
    _autoUnloadTimer = Timer(const Duration(minutes: autoUnloadMinutes), () {
      _autoUnload();
    });
    debugPrint('⏰ Auto-unload timer reset: จะ unload ใน $autoUnloadMinutes นาที');
  }

  /// 🔋 Auto-unload โมเดลเมื่อไม่ใช้งาน
  Future<void> _autoUnload() async {
    if (!_isInitialized) return;
    
    debugPrint('🔋 Auto-unloading LLM เพื่อประหยัดแบตเตอรี่...');
    await dispose();
  }

  /// 🛑 หยุด auto-unload timer (ใช้เมื่อต้องการ keep model loaded)
  void cancelAutoUnload() {
    _autoUnloadTimer?.cancel();
    _autoUnloadTimer = null;
    debugPrint('⏰ Auto-unload timer cancelled');
  }

  /// 🗑️ ปิดโมเดล
  Future<void> dispose() async {
    // ยกเลิก auto-unload timer
    _autoUnloadTimer?.cancel();
    _autoUnloadTimer = null;
    
    try {
      await _channel.invokeMethod('unloadModel');
      _isInitialized = false;
      _currentModelPath = null;
      debugPrint('🗑️ MediaPipe model unloaded');
    } catch (e) {
      debugPrint('❌ Error unloading MediaPipe: $e');
    }
  }

  /// 🔍 หา path ของไฟล์โมเดล
  ///
  /// ค้นหาลำดับ:
  /// 0. Custom path จาก SharedPreferences (file picker)
  /// 1. models/ ใน app documents
  /// 2. /sdcard/Android/data/com.example.haku/files/models/
  /// 3. ถ้าระบุ modelFileName จะค้นหาเฉพาะไฟล์นั้น
  Future<String?> _getModelPath({String? modelFileName}) async {
    // 0. ตรวจสอบ custom path จาก SharedPreferences ก่อน (file picker)
    final customPath = await getCustomModelPath();
    if (customPath != null && customPath.isNotEmpty) {
      if (await File(customPath).exists()) {
        debugPrint('✅ ใช้ custom model path: $customPath');
        return customPath;
      } else {
        debugPrint('⚠️ Custom model path ไม่พบไฟล์: $customPath');
      }
    }

    // ถ้าระบุชื่อไฟล์เฉพาะ
    if (modelFileName != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final appPath = '${appDir.path}/models/$modelFileName';
      if (await File(appPath).exists()) return appPath;

      final extPath = '/sdcard/Android/data/com.example.haku/files/models/$modelFileName';
      if (await File(extPath).exists()) return extPath;
    }

    // ค้นหาไฟล์ .task อัตโนมัติ
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');

    if (await modelsDir.exists()) {
      final files = await modelsDir
          .list()
          .where((f) => f is File && f.path.endsWith('.task'))
          .toList();

      if (files.isNotEmpty) {
        return files.first.path;
      }
    }

    // ค้นหาใน external storage
    final extDir = Directory('/sdcard/Android/data/com.example.haku/files/models');
    if (await extDir.exists()) {
      final files = await extDir
          .list()
          .where((f) => f is File && f.path.endsWith('.task'))
          .toList();

      if (files.isNotEmpty) {
        // Copy ไปยัง app storage
        final targetDir = Directory('${appDir.path}/models');
        await targetDir.create(recursive: true);

        final sourceFile = files.first as File;
        final targetPath = '${targetDir.path}/${sourceFile.uri.pathSegments.last}';
        await sourceFile.copy(targetPath);

        return targetPath;
      }
    }

    return null;
  }

  /// 📊 ข้อมูลโมเดล
  Future<Map<dynamic, dynamic>?> getModelInfo() async {
    try {
      final info = await _channel.invokeMethod('getModelInfo');
      return info as Map<dynamic, dynamic>?;
    } catch (e) {
      debugPrint('❌ Error getting model info: $e');
      return null;
    }
  }

  /// ✅ ตรวจสอบว่าโมเดลถูกโหลดแล้วหรือยัง
  Future<bool> isModelLoaded() async {
    try {
      final loaded = await _channel.invokeMethod<bool>('isModelLoaded');
      _isInitialized = loaded ?? false;
      return _isInitialized;
    } catch (e) {
      return false;
    }
  }
}
