import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database_helper.dart';

/// 📤 Export Service - ส่งออกข้อมูลบันทึก
/// 
/// รองรับ:
/// - JSON (สำหรับโปรแกรมอื่น)
/// - Markdown (อ่านง่าย)
/// - CSV (สำหรับ Excel/Sheets)
/// - Raw Backup (ไฟล์ .db)

class ExportService {
  /// 📝 Export เป็น JSON
  static Future<String> exportToJson() async {
    final entries = await DatabaseHelper.instance.exportAllToJson();
    final jsonData = jsonEncode({
      'app': 'Haku - AI Life Logger',
      'version': '0.1.0',
      'exportDate': DateTime.now().toIso8601String(),
      'entries': entries,
    });

    final directory = await getApplicationDocumentsDirectory();
    final filePath = join(directory.path, 'haku_export_${_timestamp()}.json');
    
    final file = File(filePath);
    await file.writeAsString(jsonData);
    
    return filePath;
  }

  /// 📝 Export เป็น Markdown
  static Future<String> exportToMarkdown() async {
    final entries = await DatabaseHelper.instance.getAllEntries();
    final buffer = StringBuffer();
    
    buffer.writeln('# 📝 Haku Journal Export');
    buffer.writeln();
    buffer.writeln('Exported: ${DateTime.now()}');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();

    for (final entry in entries) {
      buffer.writeln('## ${entry.createdAt}');
      buffer.writeln();
      buffer.writeln(entry.content);
      
      if (entry.mood != null) {
        final moodInfo = ['😢', '😕', '😐', '🙂', '😄'][entry.mood! - 1];
        buffer.writeln();
        buffer.writeln('**Mood:** $moodInfo (${entry.mood}/5)');
      }
      
      if (entry.locationName != null) {
        buffer.writeln();
        buffer.writeln('**Location:** ${entry.locationName}');
      }
      
      if (entry.tags.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('**Tags:** ${entry.tags.map((t) => '#$t').join(' ')}');
      }
      
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
    }

    final directory = await getApplicationDocumentsDirectory();
    final filePath = join(directory.path, 'haku_export_${_timestamp()}.md');
    
    final file = File(filePath);
    await file.writeAsString(buffer.toString());
    
    return filePath;
  }

  /// 📊 Export เป็น CSV
  static Future<String> exportToCsv() async {
    final entries = await DatabaseHelper.instance.getAllEntries();
    final buffer = StringBuffer();
    
    // Header
    buffer.writeln('id,date,content,mood,location,tags');
    
    for (final entry in entries) {
      final content = entry.content.replaceAll('"', '""').replaceAll('\n', ' ');
      final location = entry.locationName?.replaceAll('"', '""') ?? '';
      final tags = entry.tags.join(',');
      final mood = entry.mood?.toString() ?? '';
      
      buffer.writeln('${entry.id},"${entry.createdAt}","$content","$mood","$location","$tags"');
    }

    final directory = await getApplicationDocumentsDirectory();
    final filePath = join(directory.path, 'haku_export_${_timestamp()}.csv');
    
    final file = File(filePath);
    await file.writeAsString(buffer.toString());
    
    return filePath;
  }

  /// 💾 สร้าง Backup ไฟล์ดิบ (.db)
  static Future<String> createRawBackup() async {
    final directory = await getApplicationDocumentsDirectory();
    final dbPath = join(directory.path, 'haku_encrypted.db');
    
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('Database file not found');
    }
    
    final backupPath = join(directory.path, 'haku_backup_${_timestamp()}.db');
    await dbFile.copy(backupPath);
    
    return backupPath;
  }

  /// 📤 แชร์ไฟล์
  static Future<void> shareFile(String filePath) async {
    await Share.shareXFiles([XFile(filePath)]);
  }

  /// 🕐 สร้าง timestamp string
  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }
}
