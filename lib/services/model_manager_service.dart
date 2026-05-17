import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// 📦 Model Manager Service
///
/// จัดการโมเดล LiteRT (.litertlm / .task / .tflite):
/// - ค้นหาโมเดลในเครื่อง (Downloads + app docs)
/// - บันทึก/อ่าน active model path ใน SharedPreferences
/// - copy ไฟล์จาก file_picker cache → permanent models dir อัตโนมัติ
/// - ดาวน์โหลดโมเดล
/// - ลบโมเดลที่ไม่ต้องการ

class ModelManagerService {
  static final ModelManagerService _instance = ModelManagerService._internal();
  factory ModelManagerService() => _instance;
  ModelManagerService._internal();

  // ใช้ key เดียวกับ LLMService เพื่อให้ sync กัน
  static const String _prefModelPath = StorageKeys.customLlmModelPath;

  static const List<String> _supportedExtensions = ['.litertlm', '.task', '.tflite'];

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
  /// ถ้าไฟล์อยู่นอก models dir (เช่น file_picker cache) → copy ไปที่ถาวรก่อน
  Future<void> setActiveModelPath(String path) async {
    final modelsDir = await _modelsDir;
    String permanentPath = path;

    if (!path.startsWith(modelsDir.path)) {
      final fileName = path.split('/').last;
      permanentPath = '${modelsDir.path}/$fileName';
      final dest = File(permanentPath);
      if (!await dest.exists()) {
        debugPrint('📋 Copying model to permanent storage: $fileName');
        await File(path).copy(permanentPath);
        debugPrint('✅ Model copied: $permanentPath');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefModelPath, permanentPath);
    debugPrint('💾 Active model set: $permanentPath');
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

  /// ค้นหาไฟล์โมเดล LiteRT ใน Downloads + app docs
  Future<List<LocalModel>> getLocalModels() async {
    final models = <LocalModel>[];
    final scanDirs = await _getScanDirs();

    for (final dir in scanDirs) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: false)) {
        if (entity is! File) continue;
        final hasSupported = _supportedExtensions.any((ext) => entity.path.endsWith(ext));
        if (!hasSupported) continue;
        final stat = await entity.stat();
        final fileName = entity.uri.pathSegments.last;
        final displayName = _supportedExtensions.fold(fileName, (n, ext) => n.replaceAll(ext, ''));
        models.add(LocalModel(
          name: displayName,
          path: entity.path,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
        ));
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

  final Map<String, http.Client> _activeClients = {};

  /// ดาวน์โหลดโมเดลจาก URL พร้อม progress callback + cancel support
  /// 
  /// รองรับ:
  /// - HuggingFace (ต้องมี hfToken)
  /// - Google Drive direct link (ไม่ต้อง login)
  /// - ลิงก์ตรงทั่วไป
  Future<bool> downloadModel(
    String url,
    String fileName, {
    required void Function(double progress) onProgress,
    String? hfToken,
  }) async {
    try {
      debugPrint('📥 Downloading model: $fileName');
      final modelsDir = await _modelsDir;
      final filePath = '${modelsDir.path}/$fileName';
      final tmpPath = '$filePath.tmp';

      if (await File(filePath).exists()) {
        debugPrint('⚠️ Model already exists: $filePath');
        return true;
      }

      final client = http.Client();
      _activeClients[fileName] = client;

      // 🔧 แปลง Google Drive share link → direct download link
      var downloadUrl = url;
      String? gdriveFileId;
      if (url.contains('drive.google.com/file/d/')) {
        gdriveFileId = RegExp(r'/d/([a-zA-Z0-9_-]+)').firstMatch(url)?.group(1);
        if (gdriveFileId != null) {
          // ใช้ endpoint ใหม่ที่ reliable กว่าสำหรับไฟล์ใหญ่
          downloadUrl = 'https://drive.usercontent.google.com/download?id=$gdriveFileId&export=download&confirm=t';
          debugPrint('🔧 Converted to Google Drive direct link: $downloadUrl');
        }
      }

      final request = http.Request('GET', Uri.parse(downloadUrl));
      if (hfToken != null && hfToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $hfToken';
      }
      // Google Drive ต้องการ User-Agent ที่เหมือน browser ถึงจะไม่ส่ง virus scan
      request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';

      var response = await client.send(request);

      // 🔧 Google Drive อาจส่ง 302 redirect → follow ไปจนกว่าจะได้ไฟล์จริง
      if (downloadUrl.contains('drive.google.com') || downloadUrl.contains('drive.usercontent.google.com')) {
        var redirectCount = 0;
        while ((response.statusCode == 302 || response.statusCode == 307) && redirectCount < 5) {
          final location = response.headers['location'];
          if (location != null) {
            debugPrint('🔧 Following redirect #$redirectCount: $location');
            final redirectReq = http.Request('GET', Uri.parse(location));
            redirectReq.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';
            response = await client.send(redirectReq);
          }
          redirectCount++;
        }
        // ถ้าเจอ virus scan page (สำหรับไฟล์ใหญ่) → ดึง confirm token แล้วขอใหม่
        if (response.statusCode == 200) {
          final contentLen = response.contentLength;
          if (contentLen != null && contentLen < 1024 * 1024) {
            debugPrint('🔧 Possible virus scan page (size=$contentLen), checking for confirm token...');
            final bodyBytes = await response.stream.toBytes();
            final body = String.fromCharCodes(bodyBytes);
            final confirmMatch = RegExp(r'confirm=([a-zA-Z0-9_-]+)').firstMatch(body);
            if (confirmMatch != null && gdriveFileId != null) {
              final confirmUrl = 'https://drive.usercontent.google.com/download?id=$gdriveFileId&export=download&confirm=${confirmMatch.group(1)}';
              debugPrint('🔧 Confirming Google Drive download with token...');
              final confirmReq = http.Request('GET', Uri.parse(confirmUrl));
              confirmReq.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';
              response = await client.send(confirmReq);
            }
          }
        }
      }

      if (response.statusCode == 401) {
        debugPrint('❌ HF auth required — ใส่ Token ใน Settings');
        _activeClients.remove(fileName);
        return false;
      }
      if (response.statusCode != 200) {
        debugPrint('❌ Download failed: ${response.statusCode}');
        _activeClients.remove(fileName);
        return false;
      }

      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;
      final sink = File(tmpPath).openWrite();

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) onProgress(receivedBytes / totalBytes);
        }
        await sink.close();
        await File(tmpPath).rename(filePath);
        debugPrint('✅ Downloaded: $filePath (${receivedBytes ~/ 1024 ~/ 1024} MB)');
        return true;
      } catch (_) {
        await sink.close();
        final tmp = File(tmpPath);
        if (await tmp.exists()) await tmp.delete();
        return false;
      }
    } catch (e) {
      debugPrint('❌ Download error: $e');
      return false;
    } finally {
      _activeClients.remove(fileName);
    }
  }

  /// ยกเลิกการดาวน์โหลด
  void cancelDownload(String fileName) {
    _activeClients[fileName]?.close();
    _activeClients.remove(fileName);
    debugPrint('🚫 Cancelled: $fileName');
  }

  /// ตรวจว่าไฟล์โมเดลมีในเครื่องแล้วหรือยัง
  Future<bool> hasFile(String fileName) async {
    final modelsDir = await _modelsDir;
    return File('${modelsDir.path}/$fileName').exists();
  }

  /// path ของโมเดลใน app models dir
  Future<String> modelPath(String fileName) async {
    final modelsDir = await _modelsDir;
    return '${modelsDir.path}/$fileName';
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
