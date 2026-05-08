import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 📦 Model Manager Service
///
/// จัดการโมเดล llama.cpp (.gguf files):
/// - ค้นหาโมเดลในเครื่อง (Downloads + app docs)
/// - บันทึก/อ่าน active model path ใน SharedPreferences
/// - ดาวน์โหลดโมเดล
/// - ลบโมเดลที่ไม่ต้องการ

class ModelManagerService {
  static final ModelManagerService _instance = ModelManagerService._internal();
  factory ModelManagerService() => _instance;
  ModelManagerService._internal();

  static const String _prefModelPath = 'llama_model_path';

  // ── Path helpers ──

  /// โฟลเดอร์ app docs สำหรับเก็บโมเดลที่ดาวน์โหลดผ่าน app
  Future<Directory> get _modelsDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Active model path ──

  /// บันทึก path ของโมเดลที่เลือก
  Future<void> setActiveModelPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefModelPath, path);
    debugPrint('💾 Active model set: $path');
  }

  /// อ่าน path ของโมเดลที่เลือกไว้
  Future<String?> getActiveModelPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefModelPath);
    if (path == null) return null;
    // ตรวจว่าไฟล์ยังอยู่จริง
    if (!await File(path).exists()) {
      await prefs.remove(_prefModelPath);
      return null;
    }
    return path;
  }

  // ── Scan local models ──

  /// ค้นหาไฟล์ .gguf ใน Downloads + app docs
  Future<List<LocalModel>> getLocalModels() async {
    final models = <LocalModel>[];
    final scanDirs = await _getScanDirs();

    for (final dir in scanDirs) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File && entity.path.endsWith('.gguf')) {
          final stat = await entity.stat();
          models.add(LocalModel(
            name: entity.uri.pathSegments.last.replaceAll('.gguf', ''),
            path: entity.path,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          ));
        }
      }
    }

    return models..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
  }

  /// โฟลเดอร์ที่จะ scan หาโมเดล
  Future<List<Directory>> _getScanDirs() async {
    final dirs = <Directory>[];

    // 1. app docs/models (โมเดลที่โหลดผ่าน app)
    dirs.add(await _modelsDir);

    // 2. Downloads folder (โมเดลที่โหลดผ่าน browser)
    if (Platform.isAndroid) {
      dirs.add(Directory('/storage/emulated/0/Download'));
    }

    return dirs;
  }

  /// auto-select: หาโมเดลตัวแรก (newest) แล้วบันทึกเป็น active
  Future<String?> autoSelectModel() async {
    final models = await getLocalModels();
    if (models.isEmpty) return null;
    await setActiveModelPath(models.first.path);
    return models.first.path;
  }

  // ── Download ──

  /// ดาวน์โหลดโมเดล .gguf จาก URL
  Future<bool> downloadModel(
    String url,
    String fileName, {
    required void Function(double progress) onProgress,
  }) async {
    try {
      debugPrint('📥 Downloading model: $fileName');
      final modelsDir = await _modelsDir;
      final filePath = '${modelsDir.path}/$fileName';

      final existingFile = File(filePath);
      if (await existingFile.exists()) {
        debugPrint('⚠️ Model already exists: $filePath');
        return true;
      }

      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        debugPrint('❌ Download failed: ${response.statusCode}');
        return false;
      }

      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;
      final sink = File(filePath).openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) onProgress(receivedBytes / totalBytes);
      }

      await sink.close();
      debugPrint('✅ Downloaded: $filePath (${receivedBytes ~/ 1024 ~/ 1024} MB)');
      return true;
    } catch (e) {
      debugPrint('❌ Download error: $e');
      return false;
    }
  }

  // ── Delete ──

  Future<bool> deleteModel(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      await file.delete();
      // ถ้าลบโมเดลที่ active อยู่ ให้ clear
      final activePath = await getActiveModelPath();
      if (activePath == path) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefModelPath);
      }
      debugPrint('🗑️ Model deleted: $path');
      return true;
    } catch (e) {
      debugPrint('❌ Delete error: $e');
      return false;
    }
  }

  // ── Helpers ──

  Future<bool> hasModelAvailable() async => (await getLocalModels()).isNotEmpty;
}

/// 📋 ข้อมูลโมเดลที่แนะนำ
class ModelInfo {
  final String name;
  final String description;
  final int sizeMB;
  final String url;
  final bool recommended;

  const ModelInfo({
    required this.name,
    required this.description,
    required this.sizeMB,
    required this.url,
    this.recommended = false,
  });
}

/// 📋 โมเดลที่มีในเครื่อง
class LocalModel {
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;

  LocalModel({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  String get sizeFormatted {
    final mb = sizeBytes / 1024 / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}
