import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 🔐 Encryption Service - เข้ารหัสข้อมูลสำคัญ
/// 
/// จัดการ:
/// - สร้าง/เก็บ encryption key
/// - เข้ารหัส/ถอดรหัสข้อมูล
/// - SQLCipher key management

class EncryptionService {
  // ใช้ encryptedSharedPreferences: false เพื่อหลีกเลี่ยง AEADBadTagException
  // เมื่อ Keystore key ถูก invalidate หลัง reinstall debug build
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: false,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _dbKeyName = 'haku_db_encryption_key';
  static const String _masterKeyName = 'haku_master_key';

  /// อ่าน key จาก storage พร้อม fallback reset เมื่อ Keystore เสีย
  static Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // Keystore เสียหาย — ล้าง storage แล้ว generate key ใหม่
      try { await _storage.deleteAll(); } catch (_) {}
      return null;
    }
  }

  static Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      try { await _storage.deleteAll(); } catch (_) {}
      await _storage.write(key: key, value: value);
    }
  }

  /// 🔑 สร้าง encryption key สำหรับ database (SQLCipher)
  static Future<String> getOrCreateDatabaseKey() async {
    String? key = await _safeRead(_dbKeyName);

    if (key == null) {
      final random = Random.secure();
      final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
      key = base64Encode(keyBytes);
      await _safeWrite(_dbKeyName, key);
    }

    return key;
  }

  /// 🗝️ ดึง key สำหรับเปิด database
  static Future<String?> getDatabaseKey() async => _safeRead(_dbKeyName);

  /// 🔄 สร้าง key ใหม่ (ใช้ตอน reset/change password)
  static Future<String> rotateDatabaseKey() async {
    await _storage.delete(key: _dbKeyName);
    return getOrCreateDatabaseKey();
  }

  /// 🔒 เข้ารหัสข้อความ (สำหรับ sensitive data)
  static Future<String> encryptText(String plainText) async {
    final masterKey = await _getMasterKey();
    final key = encrypt.Key.fromBase64(masterKey);
    final iv = encrypt.IV.fromSecureRandom(16);
    
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc),
    );
    
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    
    // รวม IV + encrypted data
    final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combined.setRange(0, 16, iv.bytes);
    combined.setRange(16, combined.length, encrypted.bytes);
    
    return base64Encode(combined);
  }

  /// 🔓 ถอดรหัสข้อความ
  static Future<String> decryptText(String encryptedText) async {
    final masterKey = await _getMasterKey();
    final key = encrypt.Key.fromBase64(masterKey);
    
    final combined = base64Decode(encryptedText);
    final iv = encrypt.IV(Uint8List.fromList(combined.sublist(0, 16)));
    final encrypted = encrypt.Encrypted(
      Uint8List.fromList(combined.sublist(16)),
    );
    
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc),
    );
    
    return encrypter.decrypt(encrypted, iv: iv);
  }

  /// 🗝️ ดึง master key (หรือสร้างใหม่)
  static Future<String> _getMasterKey() async {
    String? key = await _safeRead(_masterKeyName);

    if (key == null) {
      final random = Random.secure();
      final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
      key = base64Encode(keyBytes);
      await _safeWrite(_masterKeyName, key);
    }

    return key;
  }

  /// 🧹 ลบ key ทั้งหมด (ใช้ตอน logout/reset)
  static Future<void> clearAllKeys() async {
    try {
      await _storage.delete(key: _dbKeyName);
      await _storage.delete(key: _masterKeyName);
    } catch (_) {
      try { await _storage.deleteAll(); } catch (_) {}
    }
  }

  /// ✅ ตรวจสอบว่ามี key อยู่หรือไม่
  static Future<bool> hasEncryptionKey() async {
    final key = await _storage.read(key: _dbKeyName);
    return key != null;
  }

  /// 📝 Write a specific database key (used during backup restore)
  static Future<void> writeDatabaseKey(String key) async {
    await _safeWrite(_dbKeyName, key);
  }
}
