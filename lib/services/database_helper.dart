import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/entry.dart';
import 'encryption_service.dart';

/// 🗄️ Database Helper - จัดการฐานข้อมูล SQLite + SQLCipher
/// 
/// คลาสนี้เป็น Singleton (มี instance เดียวตลอดทั้งแอพ)
/// รับผิดชอบ:
/// - สร้าง/อัพเดท database schema
/// - เข้ารหัส database ด้วย SQLCipher
/// - จัดการ CRUD operations สำหรับ entries

class DatabaseHelper {
  // 🎯 ค่าคงที่สำหรับ Database
  static const String _databaseName = 'haku_encrypted.db';
  static const int _databaseVersion = 2;  // เพิ่มเวอร์ชันเมื่อเพิ่มการเข้ารหัส
  
  // 📋 ชื่อตารางและคอลัมน์
  static const String tableEntries = 'entries';
  static const String columnId = 'id';
  static const String columnContent = 'content';
  static const String columnCreatedAt = 'created_at';
  static const String columnLatitude = 'latitude';
  static const String columnLongitude = 'longitude';
  static const String columnLocationName = 'location_name';
  static const String columnMediaPath = 'media_path';
  static const String columnMediaType = 'media_type';
  static const String columnMood = 'mood';
  static const String columnTags = 'tags';

  // 🔄 Singleton Pattern
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  /// 📱 ดึง instance ของ Database (สร้างถ้ายังไม่มี)
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// ⚙️ เริ่มต้น Database (สร้างไฟล์และตารางพร้อม encryption)
  Future<Database> _initDatabase() async {
    // หา path สำหรับเก็บไฟล์ database
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);

    // 🔐 ดึง encryption key
    final String password = await EncryptionService.getOrCreateDatabaseKey();

    try {
      return await openDatabase(
        path,
        version: _databaseVersion,
        password: password,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      // ไฟล์เดิมเป็น plain SQLite (ไม่ได้ encrypt) → ลบแล้วสร้าง encrypted ใหม่
      debugPrint('⚠️ DB open failed, migrating to encrypted DB: $e');
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ Deleted old unencrypted DB, creating new encrypted DB');
      }
      return openDatabase(
        path,
        version: _databaseVersion,
        password: password,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  /// 🏗️ สร้างตารางเมื่อเปิดครั้งแรก
  Future<void> _onCreate(Database db, int version) async {
    // สร้างตาราง entries
    await db.execute('''
      CREATE TABLE $tableEntries (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnContent TEXT NOT NULL,
        $columnCreatedAt TEXT NOT NULL,
        $columnLatitude REAL,
        $columnLongitude REAL,
        $columnLocationName TEXT,
        $columnMediaPath TEXT,
        $columnMediaType INTEGER DEFAULT 0,
        $columnMood INTEGER,
        $columnTags TEXT DEFAULT ''
      )
    ''');

    // 🔍 สร้าง Index สำหรับการค้นหาที่เร็วขึ้น
    await db.execute('''
      CREATE INDEX idx_created_at ON $tableEntries($columnCreatedAt DESC)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_tags ON $tableEntries($columnTags)
    ''');
  }

  /// ⬆️ อัพเกรด Database เมื่อเปลี่ยนเวอร์ชัน
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Migration สำหรับเวอร์ชันใหม่
      // ในอนาคตถ้าต้องการเพิ่มตาราง/คอลัมน์ จะทำที่นี่
    }
  }

  /// 🔓 เปิด database ด้วยรหัสผ่านที่กำหนด (สำหรับกรณีพิเศษ)
  Future<Database> openWithPassword(String password) async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);

    return openDatabase(
      path,
      password: password,
      version: _databaseVersion,
    );
  }

  /// 🔄 เปลี่ยนรหัสผ่าน database
  Future<void> changePassword(String newPassword) async {
    final db = await database;
    await db.execute("PRAGMA rekey = '$newPassword'");
    
    // บันทึก key ใหม่
    // Note: ต้อง implement การ update key ใน EncryptionService ด้วย
  }

  // ==================== CRUD Operations ====================

  /// ➕ สร้าง Entry ใหม่
  Future<int> createEntry(Entry entry) async {
    final Database db = await database;
    
    // ดึง hashtag จาก content ก่อนบันทึก
    final tags = Entry.extractTags(entry.content);
    final entryWithTags = entry.copyWith(tags: tags);
    
    return db.insert(
      tableEntries,
      entryWithTags.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 📖 อ่าน Entry ตาม id
  Future<Entry?> getEntryById(int id) async {
    final Database db = await database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      tableEntries,
      where: '$columnId = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return Entry.fromMap(maps.first);
    }
    return null;
  }

  /// 📚 อ่าน Entries ทั้งหมด (เรียงจากใหม่ → เก่า)
  Future<List<Entry>> getAllEntries({int? limit, int? offset}) async {
    final Database db = await database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      tableEntries,
      orderBy: '$columnCreatedAt DESC',
      limit: limit,
      offset: offset,
    );

    return List.generate(maps.length, (i) => Entry.fromMap(maps[i]));
  }

  /// 🔍 ค้นหา Entries ตาม keyword (ค้นหาใน content กับ tags)
  Future<List<Entry>> searchEntries(String query) async {
    final Database db = await database;
    final String searchPattern = '%$query%';
    
    final List<Map<String, dynamic>> maps = await db.query(
      tableEntries,
      where: '$columnContent LIKE ? OR $columnTags LIKE ?',
      whereArgs: [searchPattern, searchPattern],
      orderBy: '$columnCreatedAt DESC',
    );

    return List.generate(maps.length, (i) => Entry.fromMap(maps[i]));
  }

  /// 🏷️ ค้นหา Entries ตามแท็ก
  Future<List<Entry>> getEntriesByTag(String tag) async {
    final Database db = await database;
    final String tagPattern = '%$tag%';
    
    final List<Map<String, dynamic>> maps = await db.query(
      tableEntries,
      where: '$columnTags LIKE ?',
      whereArgs: [tagPattern],
      orderBy: '$columnCreatedAt DESC',
    );

    return List.generate(maps.length, (i) => Entry.fromMap(maps[i]));
  }

  /// ✏️ อัพเดท Entry
  Future<int> updateEntry(Entry entry) async {
    final Database db = await database;
    
    if (entry.id == null) {
      throw ArgumentError('Cannot update entry without id');
    }
    
    // อัพเดท tags ใหม่จาก content
    final tags = Entry.extractTags(entry.content);
    final entryWithTags = entry.copyWith(tags: tags);

    return db.update(
      tableEntries,
      entryWithTags.toMap(),
      where: '$columnId = ?',
      whereArgs: [entry.id],
    );
  }

  /// 🗑️ ลบ Entry
  Future<int> deleteEntry(int id) async {
    final Database db = await database;
    
    return db.delete(
      tableEntries,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  /// 📊 นับจำนวน Entries ทั้งหมด
  Future<int> getEntryCount() async {
    final Database db = await database;
    
    final result = await db.rawQuery('SELECT COUNT(*) FROM $tableEntries');
    return firstIntValue(result) ?? 0;
  }

  /// 📤 Export ทั้งหมดเป็น JSON (สำหรับ backup)
  Future<List<Map<String, dynamic>>> exportAllToJson() async {
    final Database db = await database;
    return db.query(tableEntries);
  }

  /// 🧹 ลบ Database ทั้งหมด (ใช้ระวัง!)
  Future<void> deleteDatabaseFile() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);
    
    await database.then((db) => db.close());
    _database = null;
    
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    
    // ลบ encryption key ด้วย
    await EncryptionService.clearAllKeys();
  }

  /// 🔒 ปิดการเชื่อมต่อ Database
  Future<void> close() async {
    final Database db = await database;
    await db.close();
    _database = null;
  }
}

/// Helper function to get first int value from query result
int? firstIntValue(List<Map<String, dynamic>> list) {
  if (list.isEmpty) return null;
  final Map<String, dynamic> map = list.first;
  if (map.isEmpty) return null;
  return map.values.first as int?;
}
