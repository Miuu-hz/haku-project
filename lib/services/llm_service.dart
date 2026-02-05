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
/// **Battery Optimization (Phase 2.1):**
/// - Lazy Loading: โมเดลจะถูกโหลดเฉพาะเมื่อมีการเรียกใช้งาน generate()
/// - Auto-Unload: โมเดลจะถูก unload หลังไม่ใช้งานตามเวลาที่กำหนด (default: 5 นาที)
/// - ไม่รันเบื้องหลังตลอดเวลา ประหยัดแบตเตอรี่
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
  /// **หมายเหตุ:** ไม่ควรเรียก method นี้โดยตรง ให้ใช้ [ensureLoaded] แทน
  /// เพื่อให้ระบบ lazy loading ทำงานได้ถูกต้อง
  ///
  /// [modelName] - ชื่อไฟล์โมเดล (optional, default = Qwen3-VL-4B-Thinking-Q4_K_M.gguf)
  Future<bool> initialize({String? modelName}) async {
    if (_isInitialized) {
      _resetAutoUnloadTimer();
      return true;
    }
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
        'contextSize': 2048, // ลดลงเพื่อประหยัด RAM
        'gpuLayers': 99, // 🎮 ใช้ GPU ทั้งหมด (Vulkan acceleration)
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
  ///
  /// ใช้ method นี้แทน [initialize] เพื่อให้ระบบ auto-unload ทำงานได้ถูกต้อง
  /// โมเดลจะถูกโหลดเฉพาะเมื่อเรียกใช้งานจริง
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
    _autoUnloadTimer = Timer(Duration(minutes: autoUnloadMinutes), () {
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
  /// **Lazy Loading:** จะโหลดโมเดลอัตโนมัติถ้ายังไม่ได้โหลด
  /// หลังใช้งานจะตั้ง timer สำหรับ auto-unload เพื่อประหยัดแบตเตอรี่
  ///
  /// [autoLoad] - ถ้า true จะโหลดโมเดลอัตโนมัติ (default: true)
  Future<String> generate(
    String prompt, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 512,
    bool autoLoad = true,
  }) async {
    // Lazy loading: โหลดโมเดลถ้ายังไม่ได้โหลด
    if (!_isInitialized) {
      if (autoLoad) {
        final loaded = await ensureLoaded();
        if (!loaded) {
          if (kDebugMode) print('⚠️ ไม่สามารถโหลดโมเดลได้ ใช้ Mock แทน');
          return ''; // ให้ caller ใช้ fallback
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
  ///
  /// จะถูกเรียกอัตโนมัติจาก auto-unload timer หรือเรียกเองได้
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

/// 📝 Helper: สร้าง Prompt สำหรับ Private Life OS
///
/// Haku = Private Life OS (ระบบปฏิบัติการชีวิตส่วนตัว)
/// ไม่ใช่แค่ไดอารี่ แต่เป็นตัวประมวลผลชีวิตที่:
/// 1. Proactive - รุก ไม่ใช่รอ (รู้ก่อน เตือนก่อน ทำให้เลย)
/// 2. Invisible Inputs - รู้ข้อมูลที่คุณไม่ได้พูด (location, time, pattern)
/// 3. Contextual Intelligence - ฉลาดตามสถานการณ์ (ค้นหาตามบริบท)
///
/// ⚠️ Optimized for Gemma 3 1B (small model, limited Thai)
/// - Keep prompts short and clear
/// - Use simple Thai sentences
/// - Provide explicit context
///
/// 🤖 AI Actions:
/// AI สามารถส่ง actions ในรูปแบบ:
/// [ACTION:SCHEDULE] title="...", date=..., time=...
/// [ACTION:PRESET] switch=...
/// [ACTION:REMINDER] message="...", minutes=...
/// [ACTION:OBJECTIVE] title="...", due=...
class HakuPrompts {
  /// System prompt พื้นฐานที่อธิบาย Haku
  static const String _hakuIdentity = '''คุณคือ Haku (箱) - Private Life OS ระบบปฏิบัติการชีวิตส่วนตัว
บทบาท: ผู้ช่วยที่รู้จักผู้ใช้ดีที่สุด เพราะมีข้อมูลชีวิตประจำวันทั้งหมด
หน้าที่:
- รู้ก่อน: วิเคราะห์ pattern จากข้อมูลที่มี
- เตือนก่อน: แจ้งเตือนเรื่องสำคัญ
- ทำให้เลย: ลงมือทำทันที (ลงปฏิทิน, สรุปข้อมูล)
การตอบ: กระชับ เป็นกันเอง ใช้อิโมจิ 1-2 ตัว พูดภาษาไทย''';

  /// Action instructions for AI
  static const String _actionInstructions = '''
เมื่อต้องการทำ actions ให้เพิ่ม tag ท้ายข้อความ:
- สร้างนัด: [ACTION:SCHEDULE] title="ชื่อ", date=พรุ่งนี้, time=09:00
- ตั้งเตือน: [ACTION:REMINDER] message="ข้อความ", minutes=15
- สร้างเป้าหมาย: [ACTION:OBJECTIVE] title="ชื่อ", due=พรุ่งนี้''';

  /// 🔍 RAG Question - ถามตอบจากบันทึก
  static String forRAGQuestion(String question, List<String> contextEntries) {
    final context = contextEntries.join('\n');
    return '''<|im_start|>system
$_hakuIdentity

ข้อมูลบันทึกของผู้ใช้:
$context

คำสั่ง: ตอบจากข้อมูลที่มี ถ้าไม่มีให้บอกตรงๆ<|im_end|>
<|im_start|>user
$question<|im_end|>
<|im_start|>assistant
''';
  }

  /// 📊 Summarization - สรุปบันทึก
  static String forSummarization(String entries) => '''<|im_start|>system
$_hakuIdentity

หน้าที่: สรุปบันทึกให้กระชับ 3-5 ประโยค
เน้น: อารมณ์ กิจกรรมหลัก สถานที่ ข้อสังเกต<|im_end|>
<|im_start|>user
บันทึก:
$entries

สรุปให้หน่อย<|im_end|>
<|im_start|>assistant
''';

  /// 📅 Event Extraction - ดึงกิจกรรมลงปฏิทิน
  static String forEventExtraction(String text) => '''<|im_start|>system
หน้าที่: ดึงข้อมูลกิจกรรมจากข้อความ
ตอบเป็น JSON เท่านั้น:
{"title":"ชื่อ","date":"YYYY-MM-DD","time":"HH:MM","duration_minutes":60}<|im_end|>
<|im_start|>user
$text<|im_end|>
<|im_start|>assistant
''';

  /// 💬 Chat - คุยทั่วไป (พร้อม action support)
  static String forChat(String message) => '''<|im_start|>system
$_hakuIdentity

$_actionInstructions<|im_end|>
<|im_start|>user
$message<|im_end|>
<|im_start|>assistant
''';

  /// 🎯 Chat with Objective Detection
  ///
  /// ใช้เมื่อต้องการให้ AI ตรวจจับ intent และสร้าง action อัตโนมัติ
  static String forChatWithActions(String message, {String? presetContext}) {
    final context =
        presetContext != null ? '\nโหมดปัจจุบัน: $presetContext' : '';
    return '''<|im_start|>system
$_hakuIdentity
$context

$_actionInstructions

สำคัญ: ถ้าผู้ใช้พูดถึงนัดหมาย/เวลา/กิจกรรม ให้สร้าง action tag ด้วย<|im_end|>
<|im_start|>user
$message<|im_end|>
<|im_start|>assistant
''';
  }

  /// 🔔 Proactive Trigger - ทักทายตามบริบท
  ///
  /// ใช้เมื่อ Haku ต้องการทักทายผู้ใช้ก่อน (ไม่รอให้ถาม)
  static String forProactiveTrigger(String context, String suggestedMessage) =>
      '''<|im_start|>system
$_hakuIdentity

บริบทปัจจุบัน:
$context

หน้าที่: ทักทายผู้ใช้ตามบริบท อ้างอิงข้อมูลเก่าถ้ามี<|im_end|>
<|im_start|>user
$suggestedMessage<|im_end|>
<|im_start|>assistant
''';

  /// 🎭 Preset-based Chat
  ///
  /// ใช้เมื่อ AI ต้องตอบตาม preset personality
  static String forPresetChat(
    String message, {
    required String presetName,
    required String personality,
    List<String> focusAreas = const [],
  }) {
    final focus =
        focusAreas.isNotEmpty ? '\nโฟกัส: ${focusAreas.join(', ')}' : '';
    return '''<|im_start|>system
$_hakuIdentity

โหมดปัจจุบัน: $presetName
บุคลิก: $personality$focus

$_actionInstructions<|im_end|>
<|im_start|>user
$message<|im_end|>
<|im_start|>assistant
''';
  }

  /// 📍 Location Revisit - กลับมาที่เดิม
  static String forLocationRevisit(
          String locationName, List<String> previousVisits) =>
      '''<|im_start|>system
$_hakuIdentity

ผู้ใช้กลับมาที่: $locationName
ประวัติการมาก่อนหน้า:
${previousVisits.join('\n')}

หน้าที่: บอกผู้ใช้ว่าเคยมาที่นี่ทำอะไร อารมณ์เป็นยังไง<|im_end|>
<|im_start|>user
ฉันกลับมาที่นี่อีกแล้ว<|im_end|>
<|im_start|>assistant
''';

  /// 🧠 Pattern Analysis - วิเคราะห์ pattern
  static String forPatternAnalysis(String patternData) => '''<|im_start|>system
$_hakuIdentity

ข้อมูล pattern ของผู้ใช้:
$patternData

หน้าที่: วิเคราะห์ pattern และให้คำแนะนำ<|im_end|>
<|im_start|>user
ช่วยวิเคราะห์ pattern ของฉันหน่อย<|im_end|>
<|im_start|>assistant
''';

  /// 🎯 Objective Extraction
  ///
  /// ใช้เมื่อต้องการให้ AI วิเคราะห์ข้อความและดึง objectives ออกมา
  static String forObjectiveExtraction(String text) => '''<|im_start|>system
วิเคราะห์ข้อความและดึงข้อมูลเป้าหมาย/นัดหมาย
ถ้าพบให้ตอบ:
[ACTION:SCHEDULE] title="ชื่อ", date=วันที่, time=เวลา

ถ้าไม่พบให้ตอบ: ไม่พบนัดหมาย<|im_end|>
<|im_start|>user
$text<|im_end|>
<|im_start|>assistant
''';
}
