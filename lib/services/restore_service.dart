import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'backup_service.dart';
import 'database_helper.dart';
import 'encryption_service.dart';
import 'rag_service.dart';

enum RestorePhase { parsing, writing, reopening, rebuildingIndex, done }

class RestoreResult {
  final bool success;
  final String? error;
  final int entriesRestored;
  const RestoreResult({
    required this.success,
    this.error,
    this.entriesRestored = 0,
  });
}

class RestoreService {
  /// Restore from a .hakubak bundle file.
  ///
  /// [onPhase] is called with (phase, progress 0–1) at each stage so the UI
  /// can display meaningful progress.  Returns a [RestoreResult] — never throws.
  static Future<RestoreResult> restoreFromBundle({
    required String filePath,
    required String passphrase,
    void Function(RestorePhase phase, double progress)? onPhase,
  }) async {
    try {
      // 1. Parse & decrypt the bundle (PBKDF2 runs in a compute isolate).
      onPhase?.call(RestorePhase.parsing, 0.1);
      final BackupBundleData bundle;
      try {
        bundle = await BackupService.parseBundle(filePath, passphrase);
      } catch (e) {
        return RestoreResult(success: false, error: e.toString());
      }

      // 2. Tear down vector search so we can safely delete its DB file.
      onPhase?.call(RestorePhase.writing, 0.3);
      await RAGService().dispose();

      // 3. Close main DB connection so the file is not locked.
      await DatabaseHelper.instance.close();

      // 4. Overwrite haku_encrypted.db with the restored bytes.
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(docsDir.path, 'haku_encrypted.db');
      await File(dbPath).writeAsBytes(bundle.dbBytes, flush: true);

      // 5. Persist the restored SQLCipher key.
      await EncryptionService.writeDatabaseKey(bundle.sqlCipherKey);

      // 6. Delete the stale vector index so it is rebuilt fresh.
      final vectorDbPath = join(await getDatabasesPath(), 'haku_hybrid_vectors.db');
      final vectorDbFile = File(vectorDbPath);
      if (await vectorDbFile.exists()) {
        await vectorDbFile.delete();
      }

      // 7. Re-open the main DB — validates the restored key and schema.
      onPhase?.call(RestorePhase.reopening, 0.55);
      try {
        await DatabaseHelper.instance.database;
      } catch (e) {
        return RestoreResult(
          success: false,
          error: 'Database could not be opened after restore — '
              'the backup may be corrupt or passphrase is wrong. ($e)',
        );
      }

      final entries = await DatabaseHelper.instance.getAllEntries();

      // 8. Rebuild the vector index from the restored entries.
      onPhase?.call(RestorePhase.rebuildingIndex, 0.65);
      try {
        await RAGService().initialize();
      } catch (e) {
        // Non-fatal — the app works fine without the vector index.
        debugPrint('⚠️ Vector index rebuild failed after restore: $e');
      }

      onPhase?.call(RestorePhase.done, 1.0);
      return RestoreResult(success: true, entriesRestored: entries.length);
    } catch (e) {
      return RestoreResult(success: false, error: e.toString());
    }
  }
}
