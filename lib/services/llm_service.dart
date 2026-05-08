import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// 🤖 LLM Service — LiteRT-LM On-device LLM Runtime
///
/// รองรับโมเดล:
///   - Gemma 4 E2B/E4B (.litertlm) — แนะนำ
///   - Gemma 3 1B (.task legacy)
///   - TFLite ทั่วไป (.tflite)
///
/// โมเดลจะถูกเก็บใน:
/// - Android: /sdcard/Android/data/com.example.haku/files/models/
/// - iOS: App Documents/models/
/// - Development: โหลดจาก ../models/ (relative to app)

class LLMService {
  /// ชื่อไฟล์โมเดลเริ่มต้น (LiteRT-LM .litertlm format)
  static const String defaultModelFile = 'gemma-4-e4b-it.litertlm';

  /// รูปแบบไฟล์โมเดลที่รองรับ
  static const List<String> supportedExtensions = ['.litertlm', '.task', '.tflite'];

  /// เวลาที่ไม่ใช้งานก่อน auto-unload (นาที)
  static const int autoUnloadMinutes = 5;

  // MethodChannel สื่อสารกับ Native (Android/iOS)
  static const MethodChannel _channel = MethodChannel('com.example.haku/llm');

  bool _isInitialized = false;
  bool _isLoading = false;
  String? _modelPath;
  String _currentModelName = defaultModelFile;

  /// Timer สำหรับ auto-unload
  Timer? _autoUnloadTimer;

  /// เวลาล่าสุดที่ใช้งาน
  DateTime? _lastUsedTime;

  // Singleton
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  /// สถานะโมเดล
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get modelPath => _modelPath;
  String get currentModelName => _currentModelName;
  DateTime? get lastUsedTime => _lastUsedTime;

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

      if (!_isSupportedExtension(customPath)) {
        return {
          'valid': false,
          'message': 'นามสกุลไฟล์ไม่รองรับ (ต้องเป็น .litertlm, .task, หรือ .tflite)',
          'path': customPath,
        };
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

  /// 🚀 เริ่มต้น LLM (โหลดโมเดล)
  ///
  /// [modelName] — ชื่อไฟล์โมเดล (optional)
  /// [maxTokens] — จำนวน token สูงสุด (default: 1024)
  /// [systemInstruction] — system prompt สำหรับ Gemma 4+ (optional)
  Future<bool> initialize({
    String? modelName,
    int maxTokens = 1024,
    String? systemInstruction,
  }) async {
    if (_isInitialized) {
      _resetAutoUnloadTimer();
      return true;
    }
    if (_isLoading) return false;

    _isLoading = true;
    if (modelName != null) _currentModelName = modelName;

    try {
      final modelPath = await _getModelPath(_currentModelName);
      if (modelPath == null) {
        if (kDebugMode) print('❌ ไม่พบไฟล์โมเดล: $_currentModelName');
        _isLoading = false;
        return false;
      }

      final result = await _channel.invokeMethod('loadModel', {
        'modelPath': modelPath,
        'maxTokens': maxTokens,
        if (systemInstruction != null && systemInstruction.isNotEmpty)
          'systemInstruction': systemInstruction,
      });

      if (result == true) {
        _modelPath = modelPath;
        _isInitialized = true;
        _lastUsedTime = DateTime.now();
        _resetAutoUnloadTimer();
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

  /// 🔋 ตรวจสอบและโหลดโมเดลถ้าจำเป็น (Lazy Loading)
  Future<bool> ensureLoaded({String? modelName}) async {
    if (_isInitialized) {
      _resetAutoUnloadTimer();
      _lastUsedTime = DateTime.now();
      return true;
    }
    return initialize(modelName: modelName);
  }

  /// ⏰ ตั้ง Timer สำหรับ auto-unload
  void _resetAutoUnloadTimer() {
    _autoUnloadTimer?.cancel();
    _autoUnloadTimer = Timer(const Duration(minutes: autoUnloadMinutes), () {
      _autoUnload();
    });
    if (kDebugMode) {
      print('⏰ Auto-unload timer reset: จะ unload ใน $autoUnloadMinutes นาที');
    }
  }

  /// 🔄 Auto-unload โมเดลเมื่อไม่ใช้งาน
  Future<void> _autoUnload() async {
    if (!_isInitialized) return;

    if (kDebugMode) {
      print('🔋 Auto-unloading LLM เพื่อประหยัดแบตเตอรี่...');
    }
    await dispose();
  }

  /// 🛑 หยุด auto-unload timer (ใช้เมื่อต้องการ keep model loaded)
  void cancelAutoUnload() {
    _autoUnloadTimer?.cancel();
    _autoUnloadTimer = null;
    if (kDebugMode) print('⏰ Auto-unload timer cancelled');
  }

  /// 💬 ส่งข้อความไปให้ LLM
  ///
  /// [autoLoad] — ถ้า true จะโหลดโมเดลอัตโนมัติ (default: true)
  /// [onToken] — callback สำหรับ simulate streaming
  Future<String> generate(
    String prompt, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 512,
    bool autoLoad = true,
  }) async {
    if (!_isInitialized) {
      if (autoLoad) {
        final loaded = await ensureLoaded();
        if (!loaded) {
          if (kDebugMode) print('⚠️ ไม่สามารถโหลดโมเดลได้');
          return '';
        }
      } else {
        throw StateError('LLM ยังไม่ถูก initialize');
      }
    }

    _lastUsedTime = DateTime.now();
    _resetAutoUnloadTimer();

    try {
      if (onToken == null) {
        final result = await _channel.invokeMethod('generate', {
          'prompt': prompt,
          'maxTokens': maxTokens,
        });
        return result?.toString() ?? '';
      }

      // Simulate streaming: เรียก blocking แล้ว split ทีละ token
      final result = await _channel.invokeMethod('generate', {
        'prompt': prompt,
        'maxTokens': maxTokens,
      });
      final text = result?.toString() ?? '';

      final buffer = StringBuffer();
      final tokens = _splitToTokens(text);
      for (final token in tokens) {
        buffer.write(token);
        onToken(token);
        await Future.delayed(const Duration(milliseconds: 8));
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

  /// 🔄 Split response text into tokens for simulate streaming
  List<String> _splitToTokens(String text) {
    final tokens = <String>[];
    final buffer = StringBuffer();

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      buffer.write(char);

      if (char == ' ' || char == '\n' || _isPunctuation(char) || buffer.length >= 4) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
      }
    }

    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }

    return tokens;
  }

  bool _isPunctuation(String char) {
    const punctuations = '.,!?;:"。，！？；：';
    return punctuations.contains(char);
  }

  /// 🔍 หา path ของไฟล์โมเดล
  Future<String?> _getModelPath(String modelName) async {
    // 0. ตรวจสอบ custom path
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
    final possiblePaths = <String>[
      '/data/local/tmp/$modelName',
      '/sdcard/Android/data/com.example.haku/files/models/$modelName',
      '/storage/emulated/0/Android/data/com.example.haku/files/models/$modelName',
    ];

    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        possiblePaths.insert(0, join(extDir.path, 'models', modelName));
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

    // 4. ตรวจสอบใน development path
    final devModelPath = await _findDevModel(modelName);
    if (devModelPath != null) {
      if (kDebugMode) print('📥 Copying model from dev path: $devModelPath');
      await File(devModelPath).copy(appModelPath);
      return appModelPath;
    }

    // 5. Auto-discover: หาไฟล์โมเดลที่รองรับใดๆ ใน models/
    if (await modelDir.exists()) {
      final files = await modelDir
          .list()
          .where((f) => f is File && _isSupportedExtension(f.path))
          .toList();
      if (files.isNotEmpty) {
        return files.first.path;
      }
    }

    return null;
  }

  /// 🔍 หาโมเดลใน development path
  Future<String?> _findDevModel(String modelName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final possiblePaths = [
        join(appDir.parent.parent.parent.parent.path, 'models', modelName),
        join(appDir.parent.parent.parent.parent.parent.path, 'models', modelName),
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
      if (!_isSupportedExtension(sourcePath)) {
        if (kDebugMode) print('❌ นามสกุลไฟล์ไม่รองรับ: $sourcePath');
        return false;
      }

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
          .where((f) => f is File && _isSupportedExtension(f.path))
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
    _autoUnloadTimer?.cancel();
    _autoUnloadTimer = null;

    if (!_isInitialized) return;

    try {
      await _channel.invokeMethod('unloadModel');
      _isInitialized = false;
      _modelPath = null;
      if (kDebugMode) print('✅ Unloaded LLM model successfully');
    } catch (e) {
      if (kDebugMode) print('⚠️ Unload model failed: $e');
    }
  }

  /// 📊 ข้อมูลโมเดลจาก Native
  Future<Map<dynamic, dynamic>?> getModelInfo() async {
    try {
      final info = await _channel.invokeMethod('getModelInfo');
      return info as Map<dynamic, dynamic>?;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting model info: $e');
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

  /// 🔧 ตั้งค่า system instruction (Gemma 4 ready)
  Future<void> setSystemInstruction(String instruction) async {
    try {
      await _channel.invokeMethod('setSystemInstruction', {
        'instruction': instruction,
      });
      if (kDebugMode) print('🔧 System instruction updated');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to set system instruction: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static bool _isSupportedExtension(String filePath) {
    return supportedExtensions.any((ext) => filePath.toLowerCase().endsWith(ext));
  }
}
