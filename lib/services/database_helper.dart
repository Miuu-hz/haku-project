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
  static const int _databaseVersion = 4;
  
  // 📋 ชื่อตารางและคอลัมน์
  static const String tableEntries = 'entries';
  static const String tableChatLog = 'secret_chat_log';
  static const String tableKnowledgePages = 'knowledge_pages';
  static const String tableKnowledgeLinks = 'knowledge_links';
  static const String tableDeviceCommandLog = 'device_command_log';
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
      // ไฟล์เดิมเป็น plain SQLite (ไม่ได้ encrypt) → backup ก่อนแล้วสร้าง encrypted ใหม่
      debugPrint('⚠️ DB open failed, migrating to encrypted DB: $e');
      final file = File(path);
      if (await file.exists()) {
        final backupPath = '$path.bak.${DateTime.now().millisecondsSinceEpoch}';
        try {
          await file.copy(backupPath);
          debugPrint('🗄️ DB backed up to: $backupPath');
        } catch (backupErr) {
          debugPrint('⚠️ DB backup failed: $backupErr');
        }
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

    await _createChatLogTables(db);
    await _createKnowledgeTables(db);
    await _createDeviceCommandLogTable(db);
  }

  Future<void> _createChatLogTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableChatLog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        summary_en TEXT NOT NULL,
        intent TEXT NOT NULL DEFAULT 'chat',
        tags TEXT DEFAULT '',
        location TEXT,
        mood INTEGER,
        consolidated INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_log_timestamp
        ON $tableChatLog(timestamp DESC)
    ''');

    // FTS5 virtual table — content table mirrors secret_chat_log
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS chat_fts USING fts5(
        summary_en, tags, location,
        content='$tableChatLog',
        content_rowid='id'
      )
    ''');

    // Triggers to keep FTS5 in sync
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS chat_fts_ai AFTER INSERT ON $tableChatLog BEGIN
        INSERT INTO chat_fts(rowid, summary_en, tags, location)
        VALUES (new.id, new.summary_en, COALESCE(new.tags,''), COALESCE(new.location,''));
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS chat_fts_bd BEFORE DELETE ON $tableChatLog BEGIN
        INSERT INTO chat_fts(chat_fts, rowid, summary_en, tags, location)
        VALUES ('delete', old.id, old.summary_en, COALESCE(old.tags,''), COALESCE(old.location,''));
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS chat_fts_au AFTER UPDATE ON $tableChatLog BEGIN
        INSERT INTO chat_fts(chat_fts, rowid, summary_en, tags, location)
        VALUES ('delete', old.id, old.summary_en, COALESCE(old.tags,''), COALESCE(old.location,''));
        INSERT INTO chat_fts(rowid, summary_en, tags, location)
        VALUES (new.id, new.summary_en, COALESCE(new.tags,''), COALESCE(new.location,''));
      END
    ''');
  }

  Future<void> _createKnowledgeTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableKnowledgePages (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        title TEXT NOT NULL,
        summary TEXT DEFAULT '',
        raw_facts TEXT DEFAULT '[]',
        contradictions TEXT DEFAULT '[]',
        superseded_by TEXT,
        confidence REAL DEFAULT 1.0,
        last_updated INTEGER NOT NULL,
        access_count INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableKnowledgeLinks (
        from_id TEXT NOT NULL,
        to_id TEXT NOT NULL,
        relation TEXT NOT NULL,
        PRIMARY KEY (from_id, to_id)
      )
    ''');
  }

  /// ⬆️ อัพเกรด Database เมื่อเปลี่ยนเวอร์ชัน
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await _createChatLogTables(db);
      await _createKnowledgeTables(db);
    }
    if (oldVersion < 4) {
      await _createDeviceCommandLogTable(db);
    }
  }

  Future<void> _createDeviceCommandLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableDeviceCommandLog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        command TEXT NOT NULL,
        params TEXT DEFAULT '{}',
        success INTEGER DEFAULT 1,
        error TEXT,
        source TEXT DEFAULT 'user_chat',
        tier TEXT DEFAULT 'auto'
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_device_cmd_timestamp
        ON $tableDeviceCommandLog(timestamp DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_device_cmd_source
        ON $tableDeviceCommandLog(source)
    ''');
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
    // SQLCipher ไม่รองรับ parameterized query สำหรับ PRAGMA rekey
    // ต้อง escape single quote เพื่อป้องกัน SQL injection
    final safePassword = newPassword.replaceAll("'", "''");
    await db.execute("PRAGMA rekey = '$safePassword'");

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

  /// 🔗 ค้นหา Entries ที่เกี่ยวข้อง (tag overlap หรือ location match)
  ///
  /// ใช้สำหรับ Tag Context Linker — ดึง past entries ที่ match keywords/location
  Future<List<Entry>> findRelatedEntries({
    required List<String> tags,
    String? location,
    int limit = 5,
  }) async {
    if (tags.isEmpty && (location == null || location.isEmpty)) return [];

    final db = await database;
    final conditions = <String>[];
    final args = <String>[];

    // tag overlap (ใช้แค่ 3 tags แรก ป้องกัน query ใหญ่เกินไป)
    for (final tag in tags.take(3)) {
      if (tag.length < 2) continue;
      conditions.add('$columnTags LIKE ?');
      args.add('%$tag%');
      // ค้นใน content ด้วย เพื่อ catch entries ที่ยังไม่ได้ tag ด้วย AI
      conditions.add('$columnContent LIKE ?');
      args.add('%$tag%');
    }

    // location match
    if (location != null && location.length >= 2) {
      conditions.add('$columnLocationName LIKE ?');
      args.add('%$location%');
    }

    if (conditions.isEmpty) return [];

    final maps = await db.query(
      tableEntries,
      where: conditions.join(' OR '),
      whereArgs: args,
      orderBy: '$columnCreatedAt DESC',
      limit: limit,
    );
    return maps.map(Entry.fromMap).toList();
  }

  /// 🏷️ Merge AI-extracted tags + location เข้ากับ Entry ที่มีอยู่แล้ว
  ///
  /// ไม่ทับ hashtag tags เดิม — รวมกัน (union)
  Future<void> mergeEntryTagsAndLocation(
    int id,
    List<String> aiTags,
    String? location,
  ) async {
    if (aiTags.isEmpty && location == null) return;

    final db = await database;
    final entry = await getEntryById(id);
    if (entry == null) return;

    // รวม existing + AI tags (ไม่ซ้ำ)
    final merged = <String>{...entry.tags, ...aiTags}
        .where((t) => t.isNotEmpty)
        .toList();

    await db.update(
      tableEntries,
      {
        columnTags: merged.join(','),
        // อัพเดท location เฉพาะเมื่อยังไม่มีค่า
        if (location != null &&
            location.isNotEmpty &&
            entry.locationName == null)
          columnLocationName: location,
      },
      where: '$columnId = ?',
      whereArgs: [id],
    );
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

  // ==================== Chat Log (Episodic Memory) ====================

  /// ➕ บันทึก English log entry ลง SQLite
  Future<int> insertChatLog({
    required String summaryEn,
    required String intent,
    required List<String> tags,
    String? location,
    int? mood,
  }) async {
    final db = await database;
    return db.insert(tableChatLog, {
      'timestamp': DateTime.now().toIso8601String(),
      'summary_en': summaryEn,
      'intent': intent,
      'tags': tags.join(','),
      'location': location,
      'mood': mood,
      'consolidated': 0,
    });
  }

  /// 🔍 Full-text search บน chat log ด้วย BM25 ranking
  ///
  /// คืน rows ที่ match เรียงจาก relevance สูงสุด (bm25 score ต่ำสุด = ดีที่สุด)
  Future<List<Map<String, dynamic>>> searchChatFTS(String query,
      {int limit = 5}) async {
    if (query.trim().isEmpty) return [];
    final db = await database;
    // escape ตัวพิเศษที่ FTS5 ไม่ชอบ
    final safe = query.replaceAll(RegExp(r'["\*\(\)\[\]]'), ' ').trim();
    if (safe.isEmpty) return [];
    try {
      return db.rawQuery(
        '''
        SELECT s.*, bm25(chat_fts) AS rank
        FROM chat_fts
        JOIN $tableChatLog s ON s.id = chat_fts.rowid
        WHERE chat_fts MATCH ?
        ORDER BY rank
        LIMIT ?
        ''',
        [safe, limit],
      );
    } catch (e) {
      debugPrint('⚠️ searchChatFTS error: $e');
      return [];
    }
  }

  /// 📚 ดึง chat log ล่าสุด N รายการ
  Future<List<Map<String, dynamic>>> getRecentChatLog({int limit = 20}) async {
    final db = await database;
    return db.query(
      tableChatLog,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  /// 🏳️ mark entries ว่า consolidated แล้ว (สำหรับ TASK-4)
  Future<void> markChatLogsConsolidated(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = ids.map((_) => '?').join(',');
    await db.rawUpdate(
      'UPDATE $tableChatLog SET consolidated = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  /// 🗑️ prune episodic entries อายุ > N วัน ที่ consolidated แล้ว
  Future<int> pruneOldChatLogs({int olderThanDays = 30}) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .toIso8601String();
    return db.delete(
      tableChatLog,
      where: 'consolidated = 1 AND timestamp < ?',
      whereArgs: [cutoff],
    );
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
