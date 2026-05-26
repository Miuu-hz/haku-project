import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database_helper.dart';
import 'encryption_service.dart';

// ─── Bundle binary layout ──────────────────────────────────────────────────
// Offset  Size  Content
//      0     8  Magic "HAKUBAK\x01"
//      8    32  PBKDF2 salt
//     40    16  AES-CBC IV (for encrypted SQLCipher key)
//     56    48  Encrypted SQLCipher key (32 bytes → padded to 48 after PKCS7)
//    104     8  DB file size (big-endian uint64)
//    112     N  Raw SQLCipher-encrypted DB bytes
// ──────────────────────────────────────────────────────────────────────────

const _kMagic = 'HAKUBAK\x01';
const _kPbkdf2Iterations = 100000;

/// Data returned by [BackupService.parseBundle].
class BackupBundleData {
  final String sqlCipherKey;
  final Uint8List dbBytes;
  const BackupBundleData({required this.sqlCipherKey, required this.dbBytes});
}

class BackupService {
  /// Create an encrypted backup bundle (.hakubak) and return its file path.
  ///
  /// The [passphrase] is used to derive an AES-256 key via PBKDF2-HMAC-SHA256,
  /// which then encrypts the SQLCipher database key.  The raw DB file (already
  /// encrypted by SQLCipher) is appended verbatim — so the bundle is safe to
  /// store anywhere without additional protection.
  static Future<String> createEncryptedBackup(String passphrase) async {
    final sqlKey = await EncryptionService.getDatabaseKey();
    if (sqlKey == null) throw Exception('No database encryption key found');

    // Close the DB so SQLite flushes all pages to disk before we copy the file.
    await DatabaseHelper.instance.close();

    final Uint8List dbBytes;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbFile = File(join(docsDir.path, 'haku_encrypted.db'));
      if (!await dbFile.exists()) throw Exception('Database file not found');
      dbBytes = await dbFile.readAsBytes();
    } finally {
      // Always reopen — even if the read fails.
      await DatabaseHelper.instance.database;
    }

    // Derive AES key from passphrase in a background isolate (PBKDF2 is slow).
    final salt = _randomBytes(32);
    final aesKey = await compute(
      _computePbkdf2,
      {'password': passphrase, 'salt': salt, 'iterations': _kPbkdf2Iterations, 'keyLen': 32},
    );

    // Encrypt the SQLCipher key (plain base64 string → UTF-8 bytes).
    final keyIv = enc.IV.fromSecureRandom(16);
    final cipher = enc.AES(enc.Key(aesKey), mode: enc.AESMode.cbc);
    final encrypter = enc.Encrypter(cipher);
    final encryptedKey = encrypter.encryptBytes(utf8.encode(sqlKey), iv: keyIv).bytes;

    // Assemble bundle.
    final docsDir = await getApplicationDocumentsDirectory();
    final outPath = join(docsDir.path, 'haku_backup_${_timestamp()}.hakubak');

    final sink = File(outPath).openWrite();
    try {
      sink.add(utf8.encode(_kMagic));       // 8 bytes
      sink.add(salt);                        // 32 bytes
      sink.add(keyIv.bytes);                // 16 bytes
      sink.add(encryptedKey);               // 48 bytes (AES-CBC PKCS7 of 32B key)
      final sizeHeader = ByteData(8)..setUint64(0, dbBytes.length);
      sink.add(sizeHeader.buffer.asUint8List()); // 8 bytes
      sink.add(dbBytes);                    // N bytes
    } finally {
      await sink.flush();
      await sink.close();
    }

    return outPath;
  }

  /// Parse and decrypt a .hakubak bundle.  Throws if the passphrase is wrong
  /// or the file is corrupt.
  static Future<BackupBundleData> parseBundle(
    String filePath,
    String passphrase,
  ) async {
    final bytes = await File(filePath).readAsBytes();

    if (bytes.length < 112) throw Exception('Backup file is too small or corrupt');

    final magic = utf8.decode(bytes.sublist(0, 8));
    if (magic != _kMagic) throw Exception('Not a valid Haku backup file');

    int offset = 8;
    final salt = bytes.sublist(offset, offset + 32);
    offset += 32;
    final keyIv = enc.IV(Uint8List.fromList(bytes.sublist(offset, offset + 16)));
    offset += 16;
    final encryptedKey = Uint8List.fromList(bytes.sublist(offset, offset + 48));
    offset += 48;
    final dbSize = ByteData.sublistView(Uint8List.fromList(bytes.sublist(offset, offset + 8)))
        .getUint64(0);
    offset += 8;

    if (offset + dbSize > bytes.length) throw Exception('Backup file is truncated');
    final dbBytes = Uint8List.fromList(bytes.sublist(offset, offset + dbSize));

    // Derive AES key from passphrase.
    final aesKey = await compute(
      _computePbkdf2,
      {'password': passphrase, 'salt': Uint8List.fromList(salt), 'iterations': _kPbkdf2Iterations, 'keyLen': 32},
    );

    // Decrypt the SQLCipher key.
    final cipher = enc.AES(enc.Key(aesKey), mode: enc.AESMode.cbc);
    final encrypter = enc.Encrypter(cipher);
    final List<int> keyBytes;
    try {
      keyBytes = encrypter.decryptBytes(
        enc.Encrypted(encryptedKey),
        iv: keyIv,
      );
    } catch (_) {
      throw Exception('Wrong passphrase or corrupted backup');
    }

    final sqlCipherKey = utf8.decode(keyBytes);
    return BackupBundleData(sqlCipherKey: sqlCipherKey, dbBytes: dbBytes);
  }

  /// Share a backup file using the OS share sheet.
  static Future<void> shareBackup(String filePath) async {
    await Share.shareXFiles(
      [XFile(filePath, mimeType: 'application/octet-stream')],
      subject: 'Haku Backup',
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  static Uint8List _randomBytes(int count) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(count, (_) => rng.nextInt(256)));
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
  }
}

/// Top-level function required by [compute] — PBKDF2-HMAC-SHA256.
Uint8List _computePbkdf2(Map<String, dynamic> args) {
  final password = args['password'] as String;
  final salt = args['salt'] as Uint8List;
  final iterations = args['iterations'] as int;
  final keyLen = args['keyLen'] as int;

  final passwordBytes = utf8.encode(password);
  final hmacFactory = () => Hmac(sha256, passwordBytes);
  const hashLen = 32; // SHA-256 output length

  final numBlocks = (keyLen + hashLen - 1) ~/ hashLen;
  final output = BytesBuilder(copy: false);

  for (var block = 1; block <= numBlocks; block++) {
    final blockCounter = ByteData(4)..setUint32(0, block);
    // U1
    final u1Input = Uint8List(salt.length + 4)
      ..setAll(0, salt)
      ..setAll(salt.length, blockCounter.buffer.asUint8List());
    var u = Uint8List.fromList(hmacFactory().convert(u1Input).bytes);
    final t = Uint8List.fromList(u);

    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmacFactory().convert(u).bytes);
      for (var j = 0; j < hashLen; j++) {
        t[j] ^= u[j];
      }
    }
    output.add(t);
  }

  return Uint8List.fromList(output.toBytes().sublist(0, keyLen));
}
