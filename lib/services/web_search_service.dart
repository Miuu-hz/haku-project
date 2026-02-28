import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 🔍 Web Search Service - ค้นหาเว็บให้ AI ฉลาดขึ้น
///
/// Features:
/// - ค้นหาผ่าน SearXNG JSON API (primary, ไม่โดน block, ไม่ต้อง key)
/// - Fallback ไป Google scraping
/// - อ่านเนื้อหาผ่าน Jina AI Reader (r.jina.ai) — clean markdown
/// - Cache ผลลัพธ์เพื่อประหยัด requests

class WebSearchService {
  static final WebSearchService _instance = WebSearchService._internal();
  factory WebSearchService() => _instance;
  WebSearchService._internal();

  static const String _cacheKey = 'web_search_cache';
  static const Duration cacheDuration = Duration(hours: 6);

  /// SearXNG public instances — ลองทีละอันจนสำเร็จ
  static const List<String> _searxInstances = [
    'search.bus-hit.me',
    'searx.be',
    'paulgo.io',
    'searxng.org',
  ];

  // Cache
  Map<String, CachedSearch> _cache = {};

  // Rate limiting
  DateTime? _lastSearchTime;
  static const Duration minSearchInterval = Duration(seconds: 2);

  // User agent rotation
  final List<String> _userAgents = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15',
  ];

  int _userAgentIndex = 0;

  bool _isInitialized = false;

  /// 🚀 Initialize service
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadCache();

    _isInitialized = true;
    debugPrint('✅ Web Search Service initialized');
    debugPrint('   - Cached searches: ${_cache.length}');
  }

  /// 📥 Load cache
  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);

      if (json != null) {
        final Map<String, dynamic> data = jsonDecode(json) as Map<String, dynamic>;
        _cache = data.map((key, value) =>
            MapEntry(key, CachedSearch.fromJson(value as Map<String, dynamic>)));

        // Clean expired cache
        _cache.removeWhere((_, v) => v.isExpired);
      }
    } catch (e) {
      debugPrint('⚠️ Error loading search cache: $e');
    }
  }

  /// 💾 Save cache
  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(_cache.map((k, v) => MapEntry(k, v.toJson()))),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving search cache: $e');
    }
  }

  /// 🔄 Get rotating user agent
  String get _currentUserAgent {
    final agent = _userAgents[_userAgentIndex];
    _userAgentIndex = (_userAgentIndex + 1) % _userAgents.length;
    return agent;
  }

  // ============================================================
  // 🔍 SEARCH METHODS
  // ============================================================

  /// 🔍 ค้นหาเว็บ (main method)
  Future<SearchResult> search(
    String query, {
    int maxResults = 5,
    String? language,
    bool forceRefresh = false,
  }) async {
    // Check cache
    final cacheKey = '${query}_$maxResults';
    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (!cached.isExpired) {
        debugPrint('📦 Using cached search: $query');
        return cached.result;
      }
    }

    // Rate limiting
    if (_lastSearchTime != null) {
      final elapsed = DateTime.now().difference(_lastSearchTime!);
      if (elapsed < minSearchInterval) {
        await Future<void>.delayed(minSearchInterval - elapsed);
      }
    }
    _lastSearchTime = DateTime.now();

    debugPrint('🔍 Searching: $query');

    // ลอง SearXNG ก่อน (JSON API, ไม่โดน block)
    var result = await _searchSearXNG(query, maxResults: maxResults);

    // Fallback to Google if SearXNG fails
    if (result.items.isEmpty) {
      debugPrint('⚠️ SearXNG failed, trying Google...');
      result = await _searchGoogle(query, maxResults: maxResults);
    }

    // Cache result
    if (result.items.isNotEmpty) {
      _cache[cacheKey] = CachedSearch(
        result: result,
        cachedAt: DateTime.now(),
      );
      await _saveCache();
    }

    return result;
  }

  /// 🔍 ค้นหาผ่าน SearXNG JSON API (ลอง instance ทีละตัว)
  Future<SearchResult> _searchSearXNG(
    String query, {
    int maxResults = 5,
  }) async {
    for (final instance in _searxInstances) {
      try {
        final uri = Uri.https(instance, '/search', {
          'q': query,
          'format': 'json',
          'language': 'th',
          'categories': 'general',
        });

        final response = await http.get(
          uri,
          headers: {
            'User-Agent': _currentUserAgent,
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final rawResults = (data['results'] as List?) ?? [];

          final items = rawResults
              .take(maxResults)
              .map((r) {
                final m = r as Map<String, dynamic>;
                return SearchItem(
                  title: (m['title'] as String?) ?? '',
                  url: (m['url'] as String?) ?? '',
                  snippet: (m['content'] as String?) ?? '',
                  source: 'SearXNG',
                );
              })
              .where((i) => i.title.isNotEmpty && i.url.isNotEmpty)
              .toList();

          if (items.isNotEmpty) {
            debugPrint('✅ SearXNG ($instance): ${items.length} results');
            return SearchResult(query: query, items: items, source: 'searxng');
          }
        }
      } catch (e) {
        debugPrint('⚠️ SearXNG ($instance) failed: $e');
      }
    }

    return SearchResult(query: query, items: [], source: 'searxng');
  }

  /// 🔍 ค้นหาผ่าน Google (scraping)
  Future<SearchResult> _searchGoogle(
    String query, {
    int maxResults = 5,
  }) async {
    try {
      final uri = Uri.https('www.google.com', '/search', {
        'q': query,
        'hl': 'th',
        'num': maxResults.toString(),
      });

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': _currentUserAgent,
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'th,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return _parseGoogleHtml(response.body, maxResults);
      } else if (response.statusCode == 429) {
        debugPrint('⚠️ Google rate limited (429)');
      }
    } catch (e) {
      debugPrint('⚠️ Google search error: $e');
    }

    return SearchResult(query: query, items: [], source: 'google');
  }

  /// 📝 Parse Google HTML
  SearchResult _parseGoogleHtml(String html, int maxResults) {
    final items = <SearchItem>[];

    try {
      final document = html_parser.parse(html);

      // Try different selectors (Google changes these frequently)
      final selectors = [
        '.g',
        'div[data-hveid]',
        '.tF2Cxc',
      ];

      for (final selector in selectors) {
        final results = document.querySelectorAll(selector);
        if (results.isEmpty) continue;

        for (final result in results.take(maxResults)) {
          final linkElement = result.querySelector('a[href^="http"]');
          final titleElement = result.querySelector('h3');
          final snippetElement = result.querySelector('.VwiC3b, .st, span');

          if (linkElement != null && titleElement != null) {
            final url = linkElement.attributes['href'] ?? '';
            final title = titleElement.text.trim();
            final snippet = snippetElement?.text.trim() ?? '';

            // Filter out Google's own links
            if (url.isNotEmpty &&
                !url.contains('google.com') &&
                title.isNotEmpty) {
              items.add(SearchItem(
                title: title,
                url: url,
                snippet: snippet,
                source: 'Google',
              ));
            }
          }
        }

        if (items.isNotEmpty) break;
      }
    } catch (e) {
      debugPrint('⚠️ Error parsing Google HTML: $e');
    }

    return SearchResult(
      query: '',
      items: items,
      source: 'google',
    );
  }

  // ============================================================
  // 📄 PAGE CONTENT
  // ============================================================

  /// 📄 อ่านเนื้อหาหน้าเว็บผ่าน Jina AI Reader — ได้ clean markdown โดยตรง
  ///
  /// GET https://r.jina.ai/{url} → markdown text (ไม่ต้อง parse HTML เอง)
  Future<PageContent?> fetchPageContent(
    String url, {
    int maxLength = 2000,
  }) async {
    try {
      final jinaUri = Uri.parse('https://r.jina.ai/$url');

      final response = await http.get(
        jinaUri,
        headers: {
          'Accept': 'text/plain',
          'X-Return-Format': 'text',
          'User-Agent': _currentUserAgent,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        var body = response.body.trim();

        // Jina ส่ง "Title: ..." มาที่บรรทัดแรก
        String title = url;
        final lines = body.split('\n');
        if (lines.isNotEmpty && lines[0].startsWith('Title:')) {
          title = lines[0].replaceFirst('Title:', '').trim();
          body = lines.skip(1).join('\n').trim();
        }

        if (body.length > maxLength) {
          body = '${body.substring(0, maxLength)}...';
        }

        debugPrint('📄 Jina fetched: $title (${body.length} chars)');
        return PageContent(
          url: url,
          title: title,
          description: '',
          content: body,
          fetchedAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Jina reader failed for $url: $e');
    }

    return null;
  }

  // ============================================================
  // 🤖 AI INTEGRATION
  // ============================================================

  /// 🤖 ค้นหาและสรุปสำหรับ AI
  Future<String> searchForAI(String query) async {
    final result = await search(query, maxResults: 3);

    if (result.items.isEmpty) {
      return 'ไม่พบผลการค้นหาสำหรับ "$query"';
    }

    final buffer = StringBuffer();
    buffer.writeln('🔍 ผลการค้นหา "$query":');
    buffer.writeln();

    for (int i = 0; i < result.items.length; i++) {
      final item = result.items[i];
      buffer.writeln('${i + 1}. ${item.title}');
      if (item.snippet.isNotEmpty) {
        buffer.writeln('   ${item.snippet}');
      }
      buffer.writeln('   🔗 ${item.url}');
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// 🤖 ค้นหาพร้อมอ่านเนื้อหา (สำหรับคำถามที่ต้องการรายละเอียด)
  Future<String> searchAndReadForAI(String query) async {
    final result = await search(query, maxResults: 2);

    if (result.items.isEmpty) {
      return 'ไม่พบผลการค้นหาสำหรับ "$query"';
    }

    final buffer = StringBuffer();
    buffer.writeln('🔍 ค้นหา "$query":');
    buffer.writeln();

    // Read content from top results
    for (int i = 0; i < result.items.length && i < 2; i++) {
      final item = result.items[i];
      buffer.writeln('📄 ${item.title}');
      buffer.writeln('🔗 ${item.url}');

      final content = await fetchPageContent(item.url, maxLength: 1000);
      if (content != null && content.content.isNotEmpty) {
        buffer.writeln('เนื้อหา: ${content.content}');
      } else {
        buffer.writeln('เนื้อหา: ${item.snippet}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// 🗑️ Clear cache
  Future<void> clearCache() async {
    _cache.clear();
    await _saveCache();
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// 🔍 ผลการค้นหา
class SearchResult {
  final String query;
  final List<SearchItem> items;
  final String source;
  final DateTime searchedAt;

  SearchResult({
    required this.query,
    required this.items,
    required this.source,
    DateTime? searchedAt,
  }) : searchedAt = searchedAt ?? DateTime.now();

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
}

/// 📋 รายการผลค้นหา
class SearchItem {
  final String title;
  final String url;
  final String snippet;
  final String source;

  SearchItem({
    required this.title,
    required this.url,
    required this.snippet,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'snippet': snippet,
        'source': source,
      };

  factory SearchItem.fromJson(Map<String, dynamic> json) => SearchItem(
        title: json['title'] as String,
        url: json['url'] as String,
        snippet: json['snippet'] as String,
        source: json['source'] as String,
      );
}

/// 📄 เนื้อหาหน้าเว็บ
class PageContent {
  final String url;
  final String title;
  final String description;
  final String content;
  final DateTime fetchedAt;

  PageContent({
    required this.url,
    required this.title,
    required this.description,
    required this.content,
    required this.fetchedAt,
  });
}

/// 📦 Cached search
class CachedSearch {
  final SearchResult result;
  final DateTime cachedAt;

  CachedSearch({
    required this.result,
    required this.cachedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > WebSearchService.cacheDuration;

  Map<String, dynamic> toJson() => {
        'result': {
          'query': result.query,
          'items': result.items.map((i) => i.toJson()).toList(),
          'source': result.source,
        },
        'cachedAt': cachedAt.toIso8601String(),
      };

  factory CachedSearch.fromJson(Map<String, dynamic> json) {
    final resultJson = json['result'] as Map<String, dynamic>;
    return CachedSearch(
      result: SearchResult(
        query: resultJson['query'] as String,
        items: (resultJson['items'] as List)
            .map((i) => SearchItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        source: resultJson['source'] as String,
      ),
      cachedAt: DateTime.parse(json['cachedAt'] as String),
    );
  }
}
