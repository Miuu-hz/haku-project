// Memory Bundle Service — A2A Foundation
//
// Export/import memory bundles สำหรับ Agent-to-Agent Protocol (Phase 5)
// Bundle = facts + knowledge pages ที่เลือก → encrypt → share กับ Haku อื่น
//
// Phase 5 จะเพิ่ม: AgentIdentity keypair + NaCl encryption
// ตอนนี้: plaintext JSON bundle พร้อม structure ที่ถูกต้อง

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'database_helper.dart';
import 'unified_vector_service.dart';
import 'wiki_service.dart';

class MemoryBundleService {
  static final MemoryBundleService _instance = MemoryBundleService._();
  MemoryBundleService._();
  factory MemoryBundleService() => _instance;

  final _db = DatabaseHelper.instance;
  final _vectors = UnifiedVectorService();

  // ── Export ────────────────────────────────────────────────────────────────

  /// Export memory bundle เป็น JSON string
  ///
  /// [categories] กำหนดว่าจะ export fact categories ไหน
  /// เช่น ['goal', 'preference', 'schedule'] สำหรับ A2A meeting negotiation
  Future<String> exportBundle({
    required List<String> categories,
    bool includeWikiPages = true,
  }) async {
    await _vectors.initialize();

    // ── 1. Facts ตาม category ─────────────────────────────────────────────
    final allFacts = _vectors.facts;
    final filteredFacts = categories.contains('*')
        ? allFacts
        : allFacts.where((f) {
            final cat = f.metadata?['category'] as String? ?? '';
            return categories.contains(cat);
          }).toList();

    final factsJson = filteredFacts
        .map((f) => {
              'id': f.id,
              'category': f.metadata?['category'] ?? '',
              'content': f.content,
              'confidence': 1.0,
              'createdAt': f.createdAt.toIso8601String(),
            })
        .toList();

    // ── 2. Knowledge pages ที่เกี่ยวข้อง ─────────────────────────────────
    final pagesJson = <Map<String, dynamic>>[];
    if (includeWikiPages) {
      final db = await _db.database;
      for (final cat in categories) {
        if (cat == '*') {
          final rows = await db.query(
            DatabaseHelper.tableKnowledgePages,
            where: 'confidence >= 0.5',
            orderBy: 'access_count DESC',
            limit: 10,
          );
          pagesJson.addAll(rows.map(_pageRowToBundle));
        } else {
          final rows = await db.query(
            DatabaseHelper.tableKnowledgePages,
            where: 'entity_type = ? AND confidence >= 0.5',
            whereArgs: [cat],
            orderBy: 'access_count DESC',
            limit: 5,
          );
          pagesJson.addAll(rows.map(_pageRowToBundle));
        }
      }
    }

    final bundle = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'categories': categories,
      'facts': factsJson,
      'knowledgePages': pagesJson,
      // Phase 5: เพิ่ม 'senderPublicKey' + 'signature' ที่นี่
    };

    final json = jsonEncode(bundle);
    debugPrint(
        '📦 Bundle exported: ${factsJson.length} facts, ${pagesJson.length} pages');
    return json;
  }

  // ── Import ────────────────────────────────────────────────────────────────

  /// Import bundle จาก Haku อื่น — merge เข้า local memory
  ///
  /// ป้องกัน duplicate: ตรวจ content similarity ก่อน insert
  /// Contradiction: flag ไว้ ไม่ลบของเก่า (Supersession pattern)
  Future<BundleImportResult> importBundle(String bundleJson) async {
    int factsAdded = 0;
    int pagesAdded = 0;
    int duplicates = 0;
    final conflicts = <String>[];

    try {
      final bundle = jsonDecode(bundleJson) as Map<String, dynamic>;
      final version = bundle['version'] as int? ?? 0;
      if (version < 1) {
        return BundleImportResult(
            error: 'Unsupported bundle version: $version');
      }

      await _vectors.initialize();

      // ── Import facts ────────────────────────────────────────────────────
      final facts = (bundle['facts'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      for (final f in facts) {
        final content = f['content'] as String? ?? '';
        final category = f['category'] as String? ?? 'imported';
        if (content.isEmpty) continue;

        // dedup: ตรวจ exact match ใน existing facts
        final existing = _vectors.facts
            .where((e) => e.content.trim() == content.trim())
            .toList();

        if (existing.isNotEmpty) {
          duplicates++;
          continue;
        }

        await _vectors.addFact(
          category: category,
          content: content,
          metadata: {
            'source': 'a2a_import',
            'importedAt': DateTime.now().toIso8601String(),
            'originalConfidence': f['confidence'] ?? 1.0,
          },
        );
        factsAdded++;
      }

      // ── Import knowledge pages ────────────────────────────────────────
      final pages = (bundle['knowledgePages'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      for (final p in pages) {
        final pageId = p['id'] as String?;
        final summary = p['summary'] as String? ?? '';
        if (pageId == null || summary.isEmpty) continue;

        final existing = await WikiService().get(pageId);
        if (existing != null) {
          // conflict check: summary ต่างกัน → flag
          if (existing.summary.trim() != summary.trim()) {
            conflicts.add('$pageId: local="${existing.summary.substring(0, existing.summary.length.clamp(0, 40))}…" vs imported="${summary.substring(0, summary.length.clamp(0, 40))}…"');
          }
          duplicates++;
          continue;
        }

        // insert หน้าใหม่จากต่างเครื่อง
        final newPage = KnowledgePage(
          id: pageId,
          entityType: p['entityType'] as String? ?? 'imported',
          title: p['title'] as String? ?? pageId,
          summary: summary,
          rawFacts: [],
          contradictions: [],
          confidence: (p['confidence'] as num?)?.toDouble() ?? 0.8,
          lastUpdated: DateTime.now(),
          accessCount: 0,
        );
        await (await _db.database).insert(
          DatabaseHelper.tableKnowledgePages,
          newPage.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        pagesAdded++;
      }

      debugPrint(
          '📥 Bundle imported: +$factsAdded facts, +$pagesAdded pages, $duplicates dupes, ${conflicts.length} conflicts');

      return BundleImportResult(
        factsAdded: factsAdded,
        pagesAdded: pagesAdded,
        duplicates: duplicates,
        conflicts: conflicts,
      );
    } catch (e) {
      debugPrint('⚠️ MemoryBundleService.importBundle failed: $e');
      return BundleImportResult(error: e.toString());
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _pageRowToBundle(Map<String, dynamic> row) => {
        'id': row['id'],
        'entityType': row['entity_type'],
        'title': row['title'],
        'summary': row['summary'] ?? '',
        'confidence': row['confidence'] ?? 1.0,
      };
}

// ── Result model ──────────────────────────────────────────────────────────────

class BundleImportResult {
  final int factsAdded;
  final int pagesAdded;
  final int duplicates;
  final List<String> conflicts;
  final String? error;

  const BundleImportResult({
    this.factsAdded = 0,
    this.pagesAdded = 0,
    this.duplicates = 0,
    this.conflicts = const [],
    this.error,
  });

  bool get hasError => error != null;
  bool get hasConflicts => conflicts.isNotEmpty;
}
