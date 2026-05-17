// Wiki Service — LLM Wiki / Living Knowledge System
//
// แนวคิด: Karpathy LLM Wiki + Mem0 AI pattern
// แทนที่จะแค่ "ค้นหาแล้วลืม" → AI สร้าง "หน้าความรู้" ต่อ entity
// ที่อัปเดตตัวเองได้ เชื่อมโยงกัน และตรวจจับข้อมูลขัดแย้ง

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/entry.dart';
import 'database_helper.dart';
import 'llm_provider_manager.dart';
import 'rag_service.dart';
import 'unified_vector_service.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class KnowledgePage {
  final String id;           // "person:บอส", "place:ออฟฟิศ", "topic:สุขภาพ"
  final String entityType;   // person | place | topic | goal | habit
  final String title;
  final String summary;      // LLM-generated ~100 tokens
  final List<Map<String, dynamic>> rawFacts;
  final List<Map<String, dynamic>> contradictions;
  final String? supersededBy;
  final double confidence;
  final DateTime lastUpdated;
  final int accessCount;

  const KnowledgePage({
    required this.id,
    required this.entityType,
    required this.title,
    required this.summary,
    required this.rawFacts,
    required this.contradictions,
    this.supersededBy,
    required this.confidence,
    required this.lastUpdated,
    required this.accessCount,
  });

  factory KnowledgePage.fromMap(Map<String, dynamic> m) => KnowledgePage(
        id: m['id'] as String,
        entityType: m['entity_type'] as String,
        title: m['title'] as String,
        summary: (m['summary'] as String?) ?? '',
        rawFacts: _parseJsonList(m['raw_facts']),
        contradictions: _parseJsonList(m['contradictions']),
        supersededBy: m['superseded_by'] as String?,
        confidence: (m['confidence'] as num?)?.toDouble() ?? 1.0,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(
            (m['last_updated'] as int?) ?? 0),
        accessCount: (m['access_count'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'entity_type': entityType,
        'title': title,
        'summary': summary,
        'raw_facts': jsonEncode(rawFacts),
        'contradictions': jsonEncode(contradictions),
        'superseded_by': supersededBy,
        'confidence': confidence,
        'last_updated': lastUpdated.millisecondsSinceEpoch,
        'access_count': accessCount,
      };

  KnowledgePage copyWith({
    String? summary,
    List<Map<String, dynamic>>? rawFacts,
    List<Map<String, dynamic>>? contradictions,
    String? supersededBy,
    double? confidence,
    DateTime? lastUpdated,
    int? accessCount,
  }) =>
      KnowledgePage(
        id: id,
        entityType: entityType,
        title: title,
        summary: summary ?? this.summary,
        rawFacts: rawFacts ?? this.rawFacts,
        contradictions: contradictions ?? this.contradictions,
        supersededBy: supersededBy ?? this.supersededBy,
        confidence: confidence ?? this.confidence,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        accessCount: accessCount ?? this.accessCount,
      );

  static List<Map<String, dynamic>> _parseJsonList(dynamic raw) {
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw as String) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}

// ── WikiService ───────────────────────────────────────────────────────────────

class WikiService {
  static final WikiService _instance = WikiService._();
  WikiService._();
  factory WikiService() => _instance;

  final _db = DatabaseHelper.instance;
  final _vectors = UnifiedVectorService();

  // ── Read ─────────────────────────────────────────────────────────────────

  /// ดึง knowledge page ตาม id (null ถ้ายังไม่มี)
  Future<KnowledgePage?> get(String pageId) async {
    final rows = await (await _db.database).query(
      DatabaseHelper.tableKnowledgePages,
      where: 'id = ?',
      whereArgs: [pageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    _bumpAccess(pageId);
    return KnowledgePage.fromMap(rows.first);
  }

  /// ดึงหรือสร้าง page ใหม่
  Future<KnowledgePage> getOrCreate(
    String pageId, {
    required String entityType,
    required String title,
  }) async {
    final existing = await get(pageId);
    if (existing != null) return existing;

    final page = KnowledgePage(
      id: pageId,
      entityType: entityType,
      title: title,
      summary: '',
      rawFacts: [],
      contradictions: [],
      confidence: 1.0,
      lastUpdated: DateTime.now(),
      accessCount: 0,
    );
    await _upsert(page);
    return page;
  }

  /// Query: ค้นหา pages ที่เกี่ยวข้องกับ message + 1-hop graph expansion
  ///
  /// GraphRAG local mode: direct match → expand via knowledge_links → richer context
  Future<List<KnowledgePage>> query(String message, {int limit = 3}) async {
    if (message.isEmpty) return [];
    try {
      await _vectors.initialize();
      final results = _vectors.search(message, limit: 10, type: VectorType.fact);

      final directIds = <String>{};
      for (final r in results) {
        final cat = r.item.metadata?['category'] as String?;
        final key = r.item.metadata?['key'] as String?;
        if (cat != null && key != null) directIds.add('$cat:$key');
      }

      // เพิ่ม title-match สำหรับ keyword ใน message
      final titleMatches = await _titleSearch(message);
      directIds.addAll(titleMatches);

      if (directIds.isEmpty) return [];

      // โหลด direct pages
      final seen = <String>{};
      final pages = <KnowledgePage>[];
      for (final eid in directIds.take(limit)) {
        final p = await get(eid);
        if (p != null && p.summary.isNotEmpty) {
          pages.add(p);
          seen.add(p.id);
        }
      }

      // 1-hop expansion ผ่าน knowledge_links (Karpathy wiki-link + GraphRAG local)
      final linkedIds = await _getLinkedIds(seen);
      for (final lid in linkedIds) {
        if (seen.contains(lid)) continue;
        if (pages.length >= limit + 2) break; // ขยายได้อีก 2 slots
        final p = await get(lid);
        if (p != null && p.summary.isNotEmpty) {
          pages.add(p);
          seen.add(p.id);
        }
      }

      return pages.take(limit + 2).toList();
    } catch (e) {
      debugPrint('⚠️ WikiService.query failed: $e');
      return [];
    }
  }

  /// Format pages เป็น context string สำหรับ inject ใน LLM prompt
  String formatForContext(List<KnowledgePage> pages) {
    if (pages.isEmpty) return '';
    return pages.map((p) {
      final conf = p.confidence < 0.7 ? ' (uncertain)' : '';
      return '[WIKI:${p.title}]$conf ${p.summary}';
    }).join('\n');
  }

  // ── Write ────────────────────────────────────────────────────────────────

  /// เพิ่ม fact ใหม่เข้า page — ตรวจ contradiction + rule-based links + update summary
  Future<void> onNewFact({
    required String category,
    required String key,
    required String content,
    bool runLLM = false, // true เฉพาะตอนชาร์จ (background)
  }) async {
    try {
      final pageId = '$category:$key';
      final page = await getOrCreate(pageId, entityType: category, title: key);

      final newFact = {'text': content, 'addedAt': DateTime.now().toIso8601String()};
      final updatedFacts = [...page.rawFacts, newFact];

      final updatedContradictions = List<Map<String, dynamic>>.from(page.contradictions);
      var updatedConfidence = page.confidence;

      if (page.summary.isNotEmpty && runLLM) {
        final contradiction = await _detectContradiction(page.summary, content);
        if (contradiction != null) {
          updatedContradictions.add({
            'old_text': page.summary,
            'new_text': content,
            'resolved': false,
            'detectedAt': DateTime.now().toIso8601String(),
          });
          updatedConfidence = (page.confidence - 0.2).clamp(0.1, 1.0);
          debugPrint('⚠️ Wiki contradiction detected for $pageId');
        } else {
          updatedConfidence = (page.confidence + 0.1).clamp(0.0, 1.0);
        }
      }

      // Rule-based links: scan content for existing page titles (0 LLM)
      // แนวคิด GraphRAG: หา co-occurring entities → สร้าง edge
      unawaited(_ruleBasedLinks(pageId, content));

      String updatedSummary;
      if (runLLM) {
        // LLM path: สร้าง summary + extract typed links ในครั้งเดียว (Karpathy pattern)
        final result = await _generateSummaryWithLinks(key, updatedFacts);
        updatedSummary = result.$1 ?? page.summary;
        for (final link in result.$2) {
          await _writeLink(pageId, link.toId, link.relation);
        }
      } else if (page.summary.isEmpty) {
        updatedSummary = content; // placeholder จนกว่าจะ run LLM ตอนชาร์จ
      } else {
        updatedSummary = page.summary;
      }

      await _upsert(page.copyWith(
        summary: updatedSummary,
        rawFacts: updatedFacts,
        contradictions: updatedContradictions,
        confidence: updatedConfidence,
        lastUpdated: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('⚠️ WikiService.onNewFact failed: $e');
    }
  }

  /// Bulk update summaries + links สำหรับ pages ที่ยังไม่มี summary (charging-only)
  Future<void> updatePendingSummaries({int batchSize = 5}) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        DatabaseHelper.tableKnowledgePages,
        where: "summary = '' OR summary IS NULL",
        orderBy: 'access_count DESC',
        limit: batchSize,
      );
      if (rows.isEmpty) return;

      debugPrint('📚 WikiService: updating ${rows.length} pending summaries');
      for (final row in rows) {
        final page = KnowledgePage.fromMap(row);
        if (page.rawFacts.isEmpty) continue;
        final result = await _generateSummaryWithLinks(page.title, page.rawFacts);
        if (result.$1 != null) {
          await _upsert(page.copyWith(summary: result.$1, lastUpdated: DateTime.now()));
          for (final link in result.$2) {
            await _writeLink(page.id, link.toId, link.relation);
          }
          // Index summary เข้า RAGService เพื่อให้ semantic search เจอ Wiki knowledge
          unawaited(_indexSummaryIntoRag(page.title, page.entityType, result.$1!));
        }
      }
    } catch (e) {
      debugPrint('⚠️ WikiService.updatePendingSummaries failed: $e');
    }
  }

  // ── Graph (knowledge_links) ───────────────────────────────────────────────

  /// เขียน edge ใน knowledge_links (from → to, relation)
  Future<void> _writeLink(String fromId, String toId, String relation) async {
    if (fromId == toId) return;
    try {
      final db = await _db.database;
      await db.insert(
        DatabaseHelper.tableKnowledgeLinks,
        {'from_id': fromId, 'to_id': toId, 'relation': relation},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('🔗 Wiki link: $fromId →[$relation]→ $toId');
    } catch (e) {
      debugPrint('⚠️ WikiService._writeLink failed: $e');
    }
  }

  /// ดึง page IDs ที่ link ออกจาก / เข้าหา pages ใน [fromIds] (1-hop)
  Future<List<String>> _getLinkedIds(Set<String> fromIds) async {
    if (fromIds.isEmpty) return [];
    try {
      final db = await _db.database;
      final placeholders = fromIds.map((_) => '?').join(',');
      final rows = await db.rawQuery(
        'SELECT DISTINCT to_id FROM ${DatabaseHelper.tableKnowledgeLinks} '
        'WHERE from_id IN ($placeholders) '
        'ORDER BY rowid DESC LIMIT 10',
        fromIds.toList(),
      );
      return rows.map((r) => r['to_id'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  /// Rule-based link detection (0 LLM) — Mem0 co-occurrence pattern
  /// ถ้า content กล่าวถึง title ของ page ที่มีอยู่ → สร้าง related_to edge
  Future<void> _ruleBasedLinks(String fromId, String content) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        DatabaseHelper.tableKnowledgePages,
        columns: ['id', 'title'],
        where: 'id != ?',
        whereArgs: [fromId],
      );
      final lower = content.toLowerCase();
      for (final row in rows) {
        final title = (row['title'] as String).toLowerCase();
        if (title.length >= 3 && lower.contains(title)) {
          await _writeLink(fromId, row['id'] as String, 'related_to');
        }
      }
    } catch (_) {}
  }

  /// Title keyword search — เสริม vector search สำหรับ exact name match
  Future<Set<String>> _titleSearch(String message) async {
    final ids = <String>{};
    try {
      final db = await _db.database;
      final rows = await db.query(
        DatabaseHelper.tableKnowledgePages,
        columns: ['id', 'title'],
      );
      final lower = message.toLowerCase();
      for (final row in rows) {
        final title = (row['title'] as String).toLowerCase();
        if (title.length >= 3 && lower.contains(title)) {
          ids.add(row['id'] as String);
        }
      }
    } catch (_) {}
    return ids;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// Index Wiki summary เข้า RAGService เพื่อให้ semantic search เจอได้
  Future<void> _indexSummaryIntoRag(String title, String entityType, String summary) async {
    try {
      final entry = Entry(
        content: '[WIKI:$title] $summary',
        createdAt: DateTime.now(),
        tags: [entityType, title],
      );
      final entryId = await DatabaseHelper.instance.createEntry(entry);
      final rag = RAGService();
      await rag.initialize();
      await rag.indexEntry(entry.copyWith(id: entryId));
      debugPrint('📚 Wiki "$title" indexed into RAG');
    } catch (e) {
      debugPrint('⚠️ WikiService RAG index failed (non-fatal): $e');
    }
  }

  Future<void> _upsert(KnowledgePage page) async {
    final db = await _db.database;
    await db.insert(
      DatabaseHelper.tableKnowledgePages,
      page.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  void _bumpAccess(String pageId) {
    _db.database.then((db) => db.rawUpdate(
          'UPDATE ${DatabaseHelper.tableKnowledgePages} '
          'SET access_count = access_count + 1 WHERE id = ?',
          [pageId],
        ));
  }

  /// LLM: ตรวจ contradiction
  Future<String?> _detectContradiction(String existingSummary, String newText) async {
    try {
      final llm = LLMProviderManager().provider;
      if (!llm.isInitialized) return null;
      final prompt = 'Does this new fact contradict the existing summary? '
          'Reply YES or NO only.\nExisting: $existingSummary\nNew: $newText';
      final result = await llm.generate(prompt);
      return result.trim().toUpperCase().startsWith('YES') ? newText : null;
    } catch (_) {
      return null;
    }
  }

  /// LLM: สร้าง summary + extract links ในครั้งเดียว (Karpathy wiki-link pattern)
  ///
  /// Return: (summary, links) — ถ้า LLM ไม่พร้อม return (null, [])
  Future<(String?, List<_WikiLink>)> _generateSummaryWithLinks(
      String title, List<Map<String, dynamic>> facts) async {
    try {
      final llm = LLMProviderManager().provider;
      if (!llm.isInitialized) return (null, <_WikiLink>[]);

      final factTexts = facts.take(8).map((f) => f['text'] as String? ?? '').join('. ');
      final prompt = '''Summarize facts about "$title" in 1-2 sentences.
Also list any other entities mentioned (people, places, topics).
Reply JSON only: {"summary":"...","links":[{"to_type":"place","to_key":"Office","relation":"works_at"}]}
Relations: knows|works_at|visited|has_goal|related_to
Facts: $factTexts''';

      final raw = await llm.generate(prompt);
      return _parseSummaryLinks(raw);
    } catch (_) {
      return (null, <_WikiLink>[]);
    }
  }

  /// Parse JSON response จาก _generateSummaryWithLinks
  (String?, List<_WikiLink>) _parseSummaryLinks(String raw) {
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (jsonMatch == null) {
      final cleaned = raw.trim();
      return (cleaned.isNotEmpty ? cleaned : null, <_WikiLink>[]);
    }
    try {
      final data = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      final summary = data['summary'] as String?;
      final linkList = (data['links'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((l) {
            final toType = l['to_type'] as String?;
            final toKey = l['to_key'] as String?;
            final rel = l['relation'] as String? ?? 'related_to';
            if (toType == null || toKey == null) return null;
            return _WikiLink(toId: '$toType:$toKey', relation: rel);
          })
          .whereType<_WikiLink>()
          .toList();
      return (summary?.trim().isNotEmpty == true ? summary : null, linkList);
    } catch (_) {
      return (raw.trim().isNotEmpty ? raw.trim() : null, <_WikiLink>[]);
    }
  }
}

// ── Internal link model ────────────────────────────────────────────────────────

class _WikiLink {
  final String toId;
  final String relation;
  const _WikiLink({required this.toId, required this.relation});
}

// sqflite ConflictAlgorithm re-export convenience
// (imported via database_helper which imports sqflite)
