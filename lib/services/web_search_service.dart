import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'nominatim_service.dart';

/// 🔍 Web Search Service - ค้นหาเว็บให้ AI ฉลาดขึ้น
///
/// Search priority:
/// 1. Wikipedia REST API  — free, 200 req/s, clean JSON, ไม่ต้อง key
/// 2. SearXNG (parallel)  — realtime / news ที่ Wiki ไม่มี
/// 3. Google scraping     — fallback สุดท้าย

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
  ///
  /// Priority: Wikipedia → SearXNG (parallel) → Google scraping
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

    // 1. Wikipedia (encyclopedic, reliable, free, no DNS issues)
    var result = await _searchWikipedia(query, maxResults: maxResults);

    // 2. SearXNG parallel (realtime: news, prices, current events)
    if (result.items.isEmpty) {
      debugPrint('📖 Wiki empty, trying SearXNG...');
      result = await _searchSearXNGParallel(query, maxResults: maxResults);
    }

    // 3. Google scraping (final fallback)
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

  /// 📖 Wikipedia REST API — free, 200 req/s, clean JSON
  ///
  /// ลอง th.wikipedia ก่อน (ถ้า query มีภาษาไทย) แล้ว en.wikipedia
  /// Summary endpoint ให้ clean text ~500 chars ต่อบทความ
  Future<SearchResult> _searchWikipedia(
    String query, {
    int maxResults = 3,
  }) async {
    final isThai = _detectQueryLanguage(query) == 'th';
    // ลำดับภาษา: Thai query → th ก่อน, อื่น → en ก่อน
    final langs = isThai ? ['th', 'en'] : ['en', 'th'];

    for (final lang in langs) {
      try {
        final searchUri = Uri.https(
          '$lang.wikipedia.org',
          '/api/rest_v1/search/page',
          {'q': query, 'limit': '$maxResults'},
        );

        final searchResp = await http.get(
          searchUri,
          headers: {'User-Agent': 'HakuApp/1.0 (haikihake@gmail.com)'},
        ).timeout(const Duration(seconds: 6));

        if (searchResp.statusCode != 200) continue;

        final data = jsonDecode(searchResp.body) as Map<String, dynamic>;
        final pages = (data['pages'] as List?) ?? [];
        if (pages.isEmpty) continue;

        // ดึง summary ของแต่ละหน้าแบบ parallel
        final summaryFutures = pages.take(maxResults).map((p) {
          final key = (p as Map<String, dynamic>)['key'] as String? ?? '';
          final title = p['title'] as String? ?? key;
          final excerpt = (p['excerpt'] as String? ?? '')
              .replaceAll(RegExp(r'<[^>]+>'), ''); // strip HTML tags
          final url = 'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(key)}';
          // ถ้า excerpt ยาวพอแล้ว ไม่ต้อง fetch summary อีก
          if (excerpt.length >= 80) {
            return Future.value(SearchItem(
              title: title,
              url: url,
              snippet: excerpt,
              source: 'Wikipedia ($lang)',
            ));
          }
          // ดึง summary เพิ่มจาก summary endpoint
          return _fetchWikiSummary(lang, key, title, url);
        });

        final items = (await Future.wait(summaryFutures))
            .whereType<SearchItem>()
            .toList();

        if (items.isNotEmpty) {
          debugPrint('📖 Wikipedia ($lang): ${items.length} results');
          return SearchResult(query: query, items: items, source: 'wikipedia');
        }
      } catch (e) {
        debugPrint('⚠️ Wikipedia ($lang) failed: $e');
      }
    }

    return SearchResult(query: query, items: [], source: 'wikipedia');
  }

  /// ดึง summary จาก Wikipedia summary endpoint (clean text ~500 chars)
  Future<SearchItem?> _fetchWikiSummary(
      String lang, String key, String title, String url) async {
    try {
      final uri = Uri.https(
          '$lang.wikipedia.org', '/api/rest_v1/page/summary/$key');
      final resp = await http
          .get(uri, headers: {'User-Agent': 'HakuApp/1.0'})
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body) as Map<String, dynamic>;
        final extract = (d['extract'] as String? ?? '').trim();
        if (extract.isNotEmpty) {
          return SearchItem(
            title: title,
            url: url,
            snippet: extract.length > 600
                ? '${extract.substring(0, 600)}...'
                : extract,
            source: 'Wikipedia ($lang)',
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// 🔍 SearXNG parallel — ยิงทุก instance พร้อมกัน เอาตัวแรกที่ตอบ
  Future<SearchResult> _searchSearXNGParallel(
    String query, {
    int maxResults = 5,
  }) async {
    final futures = _searxInstances.map((instance) async {
      try {
        final uri = Uri.https(instance, '/search', {
          'q': query,
          'format': 'json',
          'language': _detectQueryLanguage(query),
          'categories': 'general',
        });
        final resp = await http.get(
          uri,
          headers: {'User-Agent': _currentUserAgent, 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 5));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final raw = (data['results'] as List?) ?? [];
          final items = raw.take(maxResults).map((r) {
            final m = r as Map<String, dynamic>;
            return SearchItem(
              title: (m['title'] as String?) ?? '',
              url: (m['url'] as String?) ?? '',
              snippet: (m['content'] as String?) ?? '',
              source: 'SearXNG',
            );
          }).where((i) => i.title.isNotEmpty && i.url.isNotEmpty).toList();
          if (items.isNotEmpty) return SearchResult(query: query, items: items, source: 'searxng');
        }
      } catch (_) {}
      return SearchResult(query: query, items: [], source: 'searxng');
    });

    // เอาตัวแรกที่มีผล (race)
    final results = await Future.wait(futures);
    final first = results.firstWhere((r) => r.items.isNotEmpty,
        orElse: () => SearchResult(query: query, items: [], source: 'searxng'));
    if (first.items.isNotEmpty) {
      debugPrint('✅ SearXNG parallel: ${first.items.length} results');
    }
    return first;
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
        return _parseGoogleHtml(response.body, query, maxResults);
      } else if (response.statusCode == 429) {
        debugPrint('⚠️ Google rate limited (429)');
      }
    } catch (e) {
      debugPrint('⚠️ Google search error: $e');
    }

    return SearchResult(query: query, items: [], source: 'google');
  }

  /// 📝 Parse Google HTML
  SearchResult _parseGoogleHtml(String html, String query, int maxResults) {
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
      query: query,
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

  /// 🗺️ ค้นหาสถานที่ใกล้เคียงผ่าน Google Places API
  Future<SearchResult> _searchGooglePlaces(
    String query, {
    required double lat,
    required double lng,
    required String apiKey,
    int maxResults = 5,
    int radiusMeters = 3000,
  }) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/place/textsearch/json', {
        'query': query,
        'location': '$lat,$lng',
        'radius': radiusMeters.toString(),
        'key': apiKey,
        'language': 'th',
      });

      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawResults = (data['results'] as List?) ?? [];

        final items = rawResults.take(maxResults).map((r) {
          final m = r as Map<String, dynamic>;
          final loc = (m['geometry'] as Map?)?['location'] as Map?;
          final lat2 = (loc?['lat'] as num?)?.toDouble();
          final lng2 = (loc?['lng'] as num?)?.toDouble();
          // คำนวณระยะห่าง
          String distStr = '';
          if (lat2 != null && lng2 != null) {
            final dist = _haversineMeters(lat, lng, lat2, lng2);
            distStr = dist < 1000
                ? ' (${dist.round()} ม.)'
                : ' (${(dist / 1000).toStringAsFixed(1)} กม.)';
          }
          final address = (m['formatted_address'] as String?) ?? '';
          final rating = m['rating'] != null ? ' ⭐${m['rating']}' : '';
          return SearchItem(
            title: '${(m['name'] as String?) ?? ''}$rating$distStr',
            url: 'https://maps.google.com/?q=${Uri.encodeComponent((m['name'] as String?) ?? '')}',
            snippet: address,
            source: 'Google Places',
          );
        }).toList();

        if (items.isNotEmpty) {
          debugPrint('✅ Google Places: ${items.length} results near ($lat,$lng)');
          return SearchResult(query: query, items: items, source: 'google_places');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Google Places error: $e');
    }
    return SearchResult(query: query, items: [], source: 'google_places');
  }

  /// 🌐 ตรวจภาษาของ query — ถ้ามีอักษรไทย → 'th', ไม่งั้น → 'auto'
  String _detectQueryLanguage(String query) {
    return query.codeUnits.any((c) => c >= 0x0E00 && c <= 0x0E7F) ? 'th' : 'auto';
  }

  /// 📐 Haversine distance (เมตร) ระหว่าง 2 จุด
  double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final dPhi = (lat2 - lat1) * math.pi / 180;
    final dLambda = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) * math.cos(phi2) *
        math.sin(dLambda / 2) * math.sin(dLambda / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// 🤖 ค้นหาและสรุปสำหรับ AI
  /// Returns: ผลการค้นหาเป็น string, หรือ '' เมื่อไม่พบผล (ให้ caller handle)
  Future<String> searchForAI(
    String query, {
    double? lat,
    double? lng,
    String? googlePlacesKey,
  }) async {
    SearchResult result;

    // ถ้ามี GPS + Google Places key → ใช้ Places API แทน SearXNG
    if (lat != null && lng != null && googlePlacesKey != null && googlePlacesKey.isNotEmpty) {
      result = await _searchGooglePlaces(
        query,
        lat: lat,
        lng: lng,
        apiKey: googlePlacesKey,
        maxResults: 5,
      );
      // fallback to SearXNG ถ้า Places ไม่มีผล
      if (result.items.isEmpty) {
        debugPrint('⚠️ Google Places no results, falling back to SearXNG...');
        result = await search(query, maxResults: 3);
      }
    } else if (lat != null && lng != null) {
      // มี GPS แต่ไม่มี Google key → Nominatim + web search
      result = await searchNearby(query, lat: lat, lng: lng, maxResults: 5);
    } else {
      result = await search(query, maxResults: 3);
    }

    if (result.items.isEmpty) {
      return ''; // ไม่พบผล → ให้ chat_screen แสดงข้อความแจ้งแทน
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

  /// 📍 ค้นหาสถานที่ใกล้เคียงโดยไม่ต้องใช้ Google Places API
  ///
  /// Flow: GPS → Nominatim reverse → ชื่อพื้นที่ → WebSearch "$amenity $suburb $county"
  /// GPS ออกนอกเครื่องแค่ครั้งเดียว (Nominatim) หลังจากนั้น query เป็นแค่ชื่อพื้นที่
  ///
  /// [amenity] เช่น "คาเฟ่", "ร้านอาหาร", "ปั๊มน้ำมัน"
  /// [lat], [lng] ตำแหน่งปัจจุบัน
  Future<SearchResult> searchNearby(
    String amenity, {
    required double lat,
    required double lng,
    int maxResults = 5,
  }) async {
    final address = await NominatimService().reverseGeocode(lat, lng);

    final locationSuffix = address?.toSearchSuffix() ?? '';
    final query = locationSuffix.isNotEmpty
        ? '$amenity $locationSuffix'
        : amenity;

    debugPrint('📍 searchNearby: "$query"');
    return search(query, maxResults: maxResults);
  }

  /// 🤖 searchNearby สำหรับ AI — คืน string พร้อม context ที่อยู่
  Future<String> searchNearbyForAI(
    String amenity, {
    required double lat,
    required double lng,
  }) async {
    final address = await NominatimService().reverseGeocode(lat, lng);
    final locationSuffix = address?.toSearchSuffix() ?? '';
    final query = locationSuffix.isNotEmpty ? '$amenity $locationSuffix' : amenity;

    final result = await search(query, maxResults: 5);
    if (result.items.isEmpty) return '';

    final buffer = StringBuffer();
    if (locationSuffix.isNotEmpty) {
      buffer.writeln('📍 $amenity ใกล้ $locationSuffix:');
    } else {
      buffer.writeln('📍 $amenity ใกล้คุณ:');
    }
    buffer.writeln();
    for (int i = 0; i < result.items.length; i++) {
      final item = result.items[i];
      buffer.writeln('${i + 1}. ${item.title}');
      if (item.snippet.isNotEmpty) buffer.writeln('   ${item.snippet}');
      buffer.writeln('   🔗 ${item.url}');
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
