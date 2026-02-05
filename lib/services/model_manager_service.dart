import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';


import 'mediapipe_llm_service.dart';

/// 📦 Model Manager Service
/// 
/// จัดการโมเดล MediaPipe (.task files):
/// - ดาวน์โหลดโมเดลจาก URL
/// - ตรวจสอบความถูกต้องของไฟล์
/// - ลบโมเดลที่ไม่ต้องการ
/// - แสดงรายการโมเดลที่มี

class ModelManagerService {
  static final ModelManagerService _instance = ModelManagerService._internal();
  factory ModelManagerService() => _instance;
  ModelManagerService._internal();

  /// 📁 โฟลเดอร์สำหรับเก็บโมเดล
  Future<Directory> get _modelsDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  /// 📋 รายการโมเดลที่แนะนำ
  static const Map<String, ModelInfo> recommendedModels = {
    'gemma-3-270m-it': ModelInfo(
      name: 'Gemma 3 270M IT',
      description: 'Google Gemma 3 270M (Instruct) - เร็วที่สุด',
      sizeMB: 180,
      url: 'https://storage.googleapis.com/mediapipe-models/gemma-3-270m-it/task.task',
      recommended: true,
    ),
    'gemma-3-4b-it': ModelInfo(
      name: 'Gemma 3 4B IT',
      description: 'Google Gemma 3 4B (Instruct) - คุณภาพสูง',
      sizeMB: 2800,
      url: 'https://storage.googleapis.com/mediapipe-models/gemma-3-4b-it/task.task',
      recommended: false,
    ),
  };

  /// 📋 ดึงรายการโมเดลที่มีในเครื่อง
  Future<List<LocalModel>> getLocalModels() async {
    final modelsDir = await _modelsDir;
    final models = <LocalModel>[];

    if (await modelsDir.exists()) {
      await for (final entity in modelsDir.list()) {
        if (entity is File && entity.path.endsWith('.task')) {
          final stat = await entity.stat();
          final fileName = entity.uri.pathSegments.last;
          
          models.add(LocalModel(
            name: fileName.replaceAll('.task', ''),
            path: entity.path,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          ));
        }
      }
    }

    return models..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
  }

  /// 📥 ดาวน์โหลดโมเดล
  /// 
  /// @param url URL ของไฟล์ .task
  /// @param fileName ชื่อไฟล์ที่จะบันทึก
  /// @param onProgress callback แจ้งความคืบหน้า (0.0 - 1.0)
  Future<bool> downloadModel(
    String url,
    String fileName, {
    required void Function(double progress) onProgress,
  }) async {
    try {
      debugPrint('📥 Downloading model from: $url');
      
      final modelsDir = await _modelsDir;
      final filePath = '${modelsDir.path}/$fileName.task';
      
      // ตรวจสอบว่ามีไฟล์อยู่แล้วหรือไม่
      final existingFile = File(filePath);
      if (await existingFile.exists()) {
        debugPrint('⚠️ Model already exists: $filePath');
        return true;
      }

      // ดาวน์โหลด
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);
      
      if (response.statusCode != 200) {
        debugPrint('❌ Download failed: ${response.statusCode}');
        return false;
      }

      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;
      
      final file = File(filePath);
      final sink = file.openWrite();
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        
        if (totalBytes > 0) {
          onProgress(receivedBytes / totalBytes);
        }
      }
      
      await sink.close();
      
      debugPrint('✅ Model downloaded: $filePath (${receivedBytes ~/ 1024 ~/ 1024} MB)');
      return true;
      
    } catch (e, stackTrace) {
      debugPrint('❌ Download error: $e');
      debugPrint('Stack: $stackTrace');
      return false;
    }
  }

  /// 📥 ดาวน์โหลดโมเดลที่แนะนำ
  Future<bool> downloadRecommendedModel(String modelKey) async {
    final model = recommendedModels[modelKey];
    if (model == null) {
      debugPrint('❌ Unknown model: $modelKey');
      return false;
    }

    return downloadModel(
      model.url,
      modelKey,
      onProgress: (progress) {
        debugPrint('📥 Download progress: ${(progress * 100).toStringAsFixed(1)}%');
      },
    );
  }

  /// 🗑️ ลบโมเดล
  Future<bool> deleteModel(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        
        // ถ้าลบโมเดลที่กำลังใช้งานอยู่ ให้ clear custom path
        final currentPath = await MediaPipeLLMService().getCustomModelPath();
        if (currentPath == path) {
          await MediaPipeLLMService().setCustomModelPath(null);
        }
        
        debugPrint('🗑️ Model deleted: $path');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Delete error: $e');
      return false;
    }
  }

  /// ✅ ตรวจสอบว่ามีโมเดลพร้อมใช้งานหรือไม่
  Future<bool> hasModelAvailable() async {
    final models = await getLocalModels();
    return models.isNotEmpty;
  }

  /// 🔍 หาโมเดลที่มีขนาดเล็กที่สุด (สำหรับ auto-select)
  Future<LocalModel?> getSmallestModel() async {
    final models = await getLocalModels();
    if (models.isEmpty) return null;
    
    return models.reduce((a, b) => a.sizeBytes < b.sizeBytes ? a : b);
  }
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
