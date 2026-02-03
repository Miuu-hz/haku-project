import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// 🤖 LLM Service - จัดการโมเดลจาก external models/ folder
/// 
/// โมเดลจะถูกเก็บใน:
/// - Android: /sdcard/Android/data/com.example.haku/files/models/
/// - iOS: App Documents/models/
/// - Development: โหลดจาก ../models/ (relative to app)
///
/// วิธีใช้:
/// 1. วางไฟล์ .gguf ใน folder `models/` ที่ root ของ project
/// 2. แอพจะ copy ไปยัง app storage ตอนเริ่มต้น (ถ้ายังไม่มี)
/// 3. หรือจะโหลดโมเดลผ่าน `downloadModel()` จาก URL

class LLMService {
  /// ชื่อไฟล์โมเดลเริ่มต้น
  static const String defaultModelFile = 'Qwen3-VL-4B-Thinking-Q4_K_M.gguf';
  
  // MethodChannel สื่อสารกับ Native (Android/iOS)
  static const MethodChannel _channel = MethodChannel('com.example.haku/llm');
  
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _modelPath;
  String _currentModelName = defaultModelFile;
  
  // Singleton
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();
  
  /// สถานะโมเดล
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get modelPath => _modelPath;
  String get currentModelName => _currentModelName;

  /// โหลด custom model path จาก SharedPreferences
  Future<String?> getCustomModelPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageKeys.customLlmModelPath);
  }

  /// ตรวจสอบว่าไฟล์ custom model มีอยู่จริงและอ่านได้
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

  /// บันทึก custom model path ลง SharedPreferences
  Future<void> setCustomModelPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(StorageKeys.customLlmModelPath);
    } else {
      await prefs.setString(StorageKeys.customLlmModelPath, path);
    }
  }
  
  /// 🚀 เริ่มต้น LLM (โหลดโมเดล)
  /// 
  /// [modelName] - ชื่อไฟล์โมเดล (optional, default = Qwen3-VL-4B-Thinking-Q4_K_M.gguf)
  Future<bool> initialize({String? modelName}) async {
    if (_isInitialized) return true;
    if (_isLoading) return false;
    
    _isLoading = true;
    if (modelName != null) _currentModelName = modelName;
    
    try {
      // หา path โมเดล
      final modelPath = await _getModelPath(_currentModelName);
      if (modelPath == null) {
        if (kDebugMode) print('❌ ไม่พบไฟล์โมเดล: $_currentModelName');
        _isLoading = false;
        return false;
      }
      
      // เรียก Native ให้ load โมเดล
      // gpuLayers: จำนวน layers ที่ให้ GPU ประมวลผล
      // 0 = CPU only, 99 = GPU ทั้งหมด (Vulkan backend)
      final result = await _channel.invokeMethod('loadModel', {
        'modelPath': modelPath,
        'contextSize': 2048,  // ลดลงเพื่อประหยัด RAM
        'gpuLayers': 99,  // 🎮 ใช้ GPU ทั้งหมด (Vulkan acceleration)
      });
      
      if (result == true) {
        _modelPath = modelPath;
        _isInitialized = true;
        if (kDebugMode) print('✅ โหลดโมเดลสำเร็จ: $_currentModelName');
        return true;
      }
    } on PlatformException catch (e) {
      if (kDebugMode) print('❌ โหลดโมเดลล้มเหลว: ${e.message}');
    } finally {
      _isLoading = false;
    }
    
    return false;
  }
  
  /// 💬 ส่งข้อความไปให้ LLM
  Future<String> generate(
    String prompt, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 512,
  }) async {
    if (!_isInitialized) {
      throw StateError('LLM ยังไม่ถูก initialize');
    }
    
    try {
      if (onToken == null) {
        final result = await _channel.invokeMethod('generate', {
          'prompt': prompt,
          'temperature': temperature,
          'maxTokens': maxTokens,
        });
        return result?.toString() ?? '';
      }

      final stream = _channel.invokeMethod('generateStream', {
        'prompt': prompt,
        'temperature': temperature,
        'maxTokens': maxTokens,
      });

      final buffer = StringBuffer();
      await for (final token in _tokenStream(stream)) {
        buffer.write(token);
        onToken(token);
      }

      return buffer.toString();
    } on PlatformException catch (e) {
      if (kDebugMode) print('❌ Generate PlatformException: ${e.message}');
      return '';
    } catch (e) {
      if (kDebugMode) print('❌ Generate ล้มเหลว: $e');
      return '';
    }
  }
  
  /// 🔍 หา path ของไฟล์โมเดล
  /// 
  /// ลำดับการค้นหา:
  /// 1. ใน app documents (ถ้าเคย copy ไว้)
  /// 2. ใน external storage /sdcard/.../models/
  /// 3. ใน ../models/ (development)
  Future<String?> _getModelPath(String modelName) async {
    // 0. ตรวจสอบ custom path จาก Settings ก่อน (ไม่ copy, โหลดตรงจาก path เลย)
    final customPath = await getCustomModelPath();
    if (customPath != null && customPath.isNotEmpty) {
      if (await File(customPath).exists()) {
        if (kDebugMode) print('✅ ใช้ custom model path: $customPath');
        return customPath;
      } else {
        if (kDebugMode) print('⚠️ Custom model path ไม่พบไฟล์: $customPath');
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory(join(appDir.path, 'models'));

    // 1. ตรวจสอบใน app documents/models/
    final appModelPath = join(modelDir.path, modelName);
    if (await File(appModelPath).exists()) {
      return appModelPath;
    }
    
    // 2. สร้าง model directory ถ้ายังไม่มี
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    
    // 3. ตรวจสอบใน external storage (Android)
    // เช็คหลาย path เพราะ Android มี symbolic links หลายตัว
    final possiblePaths = <String>[
      // Path /data/local/tmp (dev: adb push)
      '/data/local/tmp/$modelName',
      // Path /sdcard โดยตรง
      '/sdcard/Android/data/com.example.haku/files/models/$modelName',
      // Path /storage/emulated/0 โดยตรง
      '/storage/emulated/0/Android/data/com.example.haku/files/models/$modelName',
    ];

    // เพิ่ม path จาก getExternalStorageDirectory (อาจ return null)
    try {
      final extDir = await getExternalStorageDirectory();
      if (kDebugMode) print('🔍 getExternalStorageDirectory: ${extDir?.path}');
      if (extDir != null) {
        possiblePaths.insert(0, join(extDir.path, 'models', modelName));
        // Debug: list ไฟล์ทั้งหมดใน models directory
        final modelsDir = Directory(join(extDir.path, 'models'));
        if (await modelsDir.exists()) {
          final files = await modelsDir.list().toList();
          if (kDebugMode) print('📂 Files in ${modelsDir.path}: ${files.map((f) => f.path).toList()}');
        } else {
          if (kDebugMode) print('📂 Models directory does not exist: ${modelsDir.path}');
        }
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ getExternalStorageDirectory failed: $e');
    }

    for (final path in possiblePaths) {
      if (kDebugMode) print('🔍 Looking for model at: $path');
      try {
        if (await File(path).exists()) {
          if (kDebugMode) print('✅ Found model at: $path');
          await File(path).copy(appModelPath);
          return appModelPath;
        }
      } catch (e) {
        if (kDebugMode) print('⚠️ Cannot access $path: $e');
      }
    }
    
    // 4. ตรวจสอบใน development path (../models/)
    final devModelPath = await _findDevModel(modelName);
    if (devModelPath != null) {
      // Copy ไปยัง app storage
      if (kDebugMode) print('📥 Copying model from dev path: $devModelPath');
      await File(devModelPath).copy(appModelPath);
      return appModelPath;
    }
    
    return null;
  }
  
  /// 🔍 หาโมเดลใน development path
  Future<String?> _findDevModel(String modelName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      
      // ลองหา relative path จาก app documents
      // ปกติ: /data/data/.../app_flutter -> project_root/models/
      final possiblePaths = [
        // Flutter run debug
        join(appDir.parent.parent.parent.parent.path, 'models', modelName),
        // Android studio
        join(appDir.parent.parent.parent.parent.parent.path, 'models', modelName),
        // iOS Simulator
        join(appDir.parent.parent.path, 'models', modelName),
      ];
      
      for (final path in possiblePaths) {
        if (await File(path).exists()) {
          return path;
        }
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Dev path check error: $e');
    }
    return null;
  }
  
  /// 📥 Import โมเดลจาก path ที่ user เลือก
  Future<bool> importModel(String sourcePath, {String? customName}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory(join(appDir.path, 'models'));
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      
      final fileName = customName ?? basename(sourcePath);
      final destPath = join(modelDir.path, fileName);
      
      await File(sourcePath).copy(destPath);
      if (kDebugMode) print('✅ Imported model to: $destPath');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Import failed: $e');
      return false;
    }
  }
  
  /// 📋 รายการโมเดลที่มีในเครื่อง
  Future<List<String>> listAvailableModels() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory(join(appDir.path, 'models'));
      
      if (!await modelDir.exists()) return [];
      
      return await modelDir
          .list()
          .where((f) => f is File && f.path.endsWith('.gguf'))
          .map((f) => basename(f.path))
          .toList();
    } catch (e) {
      return [];
    }
  }
  
  /// 🗑️ ลบโมเดล
  Future<bool> deleteModel(String modelName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = join(appDir.path, 'models', modelName);
      final file = File(modelPath);
      
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Delete failed: $e');
      return false;
    }
  }
  
  /// 🧹 ปิดโมเดล
  Future<void> dispose() async {
    if (!_isInitialized) return;
    
    try {
      await _channel.invokeMethod('unloadModel');
      _isInitialized = false;
    } catch (e) {
      if (kDebugMode) print('⚠️ Unload model failed: $e');
    }
  }
  
  /// 🔄 Stream tokens
  Stream<String> _tokenStream(dynamic stream) async* {
    yield* const Stream<String>.empty();
  }
  
  /// 📊 ข้อมูลโมเดล
  Map<String, dynamic> getModelInfo() => {
      'name': _currentModelName.replaceAll('.gguf', ''),
      'quantization': 'Q4_K_M',
      'size': '~2.4GB',
      'contextLength': 4096,
      'supportsVision': _currentModelName.toLowerCase().contains('vl'),
    };
}

/// 📝 Helper: สร้าง Prompt
class HakuPrompts {
  static String forRAGQuestion(String question, List<String> contextEntries) {
    final context = contextEntries.join('\n\n');
    return '''<|im_start|>system
คุณคือ Haku (箱) ผู้ช่วยบันทึกชีวิตประจำวัน คุณมีข้อมูลบันทึกของผู้ใช้ดังนี้:

$context

ตอบคำถามโดยใช้ข้อมูลจากบันทึกเท่านั้น ถ้าไม่มีข้อมูลให้บอกว่าไม่พบ<|im_end|>
<|im_start|>user
$question<|im_end|>
<|im_start|>assistant
''';
  }
  
  static String forSummarization(String entries) => '''<|im_start|>system
คุณคือ Haku (箱) ผู้ช่วยสรุปบันทึกชีวิตประจำวัน<|im_end|>
<|im_start|>user
สรุปบันทึกต่อไปนี้เป็นข้อความสั้น ๆ 3-5 ประโยค:

$entries<|im_end|>
<|im_start|>assistant
''';
  
  static String forEventExtraction(String text) => '''<|im_start|>system
วิเคราะห์ข้อความและดึงข้อมูลกิจกรรม ตอบเป็น JSON เท่านั้น:
{
  "title": "ชื่อกิจกรรม",
  "date": "YYYY-MM-DD",
  "time": "HH:MM",
  "duration_minutes": number
}<|im_end|>
<|im_start|>user
$text<|im_end|>
<|im_start|>assistant
''';
  
  static String forChat(String message) => '''<|im_start|>system
คุณคือ Haku (箱) AI ผู้ช่วยส่วนตัวที่เป็นกันเอง พูดภาษาไทยธรรมชาติ
<|im_end|>
<|im_start|>user
$message<|im_end|>
<|im_start|>assistant
''';
}
