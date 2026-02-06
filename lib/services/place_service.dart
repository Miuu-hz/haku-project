import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 🗺️ Place Service - จัดการสถานที่ด้วย OSM + Google Places
///
/// Features:
/// - ค้นหาสถานที่ผ่าน Google Places API
/// - แสดงแผนที่ด้วย OpenStreetMap (ฟรี)
/// - เก็บ cache สถานที่ที่เคยไป
/// - แนะนำสถานที่จาก history

class PlaceService {
  static final PlaceService _instance = PlaceService._internal();
  factory PlaceService() => _instance;
  PlaceService._internal();

  static const String _placesKey = 'saved_places';
  static const String _historyKey = 'place_history';
  static const String _apiKeyKey = 'google_places_api_key';

  // Google Places API (ใส่ key ใน settings)
  String? _googleApiKey;

  // Cached data
  List<SavedPlace> _savedPlaces = [];
  List<PlaceVisit> _visitHistory = [];

  bool _isInitialized = false;

  // Getters
  List<SavedPlace> get savedPlaces => List.unmodifiable(_savedPlaces);
  List<PlaceVisit> get visitHistory => List.unmodifiable(_visitHistory);
  bool get hasApiKey => _googleApiKey != null && _googleApiKey!.isNotEmpty;

  /// 🚀 Initialize service
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadApiKey();
    await _loadSavedPlaces();
    await _loadVisitHistory();

    _isInitialized = true;
    debugPrint('✅ Place Service initialized');
    debugPrint('   - Saved places: ${_savedPlaces.length}');
    debugPrint('   - Visit history: ${_visitHistory.length}');
    debugPrint('   - Google API: ${hasApiKey ? "configured" : "not set"}');
  }

  /// 🔑 Load/Save API Key
  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    _googleApiKey = prefs.getString(_apiKeyKey);
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key);
    _googleApiKey = key;
  }

  /// 📥 Load saved places
  Future<void> _loadSavedPlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_placesKey);
      if (json != null) {
        final List<dynamic> list = jsonDecode(json);
        _savedPlaces = list.map((e) => SavedPlace.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading saved places: $e');
    }
  }

  /// 📥 Load visit history
  Future<void> _loadVisitHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_historyKey);
      if (json != null) {
        final List<dynamic> list = jsonDecode(json);
        _visitHistory = list.map((e) => PlaceVisit.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading visit history: $e');
    }
  }

  /// 💾 Save to storage
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _placesKey,
        jsonEncode(_savedPlaces.map((p) => p.toJson()).toList()),
      );
      await prefs.setString(
        _historyKey,
        jsonEncode(_visitHistory.map((v) => v.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving places: $e');
    }
  }

  // ============================================================
  // 🔍 SEARCH PLACES
  // ============================================================

  /// 🔍 ค้นหาสถานที่ (Google Places API)
  Future<List<PlaceResult>> searchPlaces(
    String query, {
    double? nearLat,
    double? nearLng,
    int radius = 5000, // meters
    String? type, // restaurant, cafe, etc.
  }) async {
    // ถ้าไม่มี API key ใช้ Nominatim (OSM) แทน
    if (!hasApiKey) {
      return _searchWithNominatim(query, nearLat: nearLat, nearLng: nearLng);
    }

    try {
      final params = {
        'query': query,
        'key': _googleApiKey!,
        if (nearLat != null && nearLng != null)
          'location': '$nearLat,$nearLng',
        'radius': radius.toString(),
        if (type != null) 'type': type,
        'language': 'th',
      };

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/textsearch/json',
        params,
      );

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;

        return results.map((r) => PlaceResult.fromGoogleJson(r)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Google Places search error: $e');
    }

    // Fallback to Nominatim
    return _searchWithNominatim(query, nearLat: nearLat, nearLng: nearLng);
  }

  /// 🔍 ค้นหาด้วย Nominatim (OSM - ฟรี)
  Future<List<PlaceResult>> _searchWithNominatim(
    String query, {
    double? nearLat,
    double? nearLng,
  }) async {
    try {
      final params = {
        'q': query,
        'format': 'json',
        'addressdetails': '1',
        'limit': '10',
        'accept-language': 'th',
        if (nearLat != null && nearLng != null) 'viewbox': _getViewbox(nearLat, nearLng, 0.1),
      };

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);

      final response = await http.get(
        uri,
        headers: {'User-Agent': 'HakuApp/1.0'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> results = jsonDecode(response.body);
        return results.map((r) => PlaceResult.fromNominatimJson(r)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Nominatim search error: $e');
    }

    return [];
  }

  String _getViewbox(double lat, double lng, double delta) {
    return '${lng - delta},${lat - delta},${lng + delta},${lat + delta}';
  }

  /// 📍 ค้นหาสถานที่ใกล้เคียง
  Future<List<PlaceResult>> searchNearby({
    required double lat,
    required double lng,
    String? type,
    int radius = 1000,
  }) async {
    if (!hasApiKey) {
      return _searchWithNominatim(type ?? 'place', nearLat: lat, nearLng: lng);
    }

    try {
      final params = {
        'location': '$lat,$lng',
        'radius': radius.toString(),
        'key': _googleApiKey!,
        if (type != null) 'type': type,
        'language': 'th',
      };

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/nearbysearch/json',
        params,
      );

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;
        return results.map((r) => PlaceResult.fromGoogleJson(r)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Nearby search error: $e');
    }

    return [];
  }

  /// 📄 ดึงรายละเอียดสถานที่
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    if (!hasApiKey) return null;

    try {
      final params = {
        'place_id': placeId,
        'key': _googleApiKey!,
        'language': 'th',
        'fields': 'name,formatted_address,geometry,rating,reviews,'
            'opening_hours,photos,types,website,formatted_phone_number',
      };

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        params,
      );

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null) {
          return PlaceDetails.fromJson(data['result']);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Place details error: $e');
    }

    return null;
  }

  // ============================================================
  // 💾 SAVE & MANAGE PLACES
  // ============================================================

  /// ➕ บันทึกสถานที่
  Future<SavedPlace> savePlace({
    required String name,
    required double lat,
    required double lng,
    String? address,
    String? placeId,
    String? category,
    String? icon,
    String? notes,
  }) async {
    final place = SavedPlace(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      latitude: lat,
      longitude: lng,
      address: address,
      placeId: placeId,
      category: category ?? 'other',
      icon: icon ?? '📍',
      notes: notes,
      createdAt: DateTime.now(),
      visitCount: 0,
    );

    _savedPlaces.add(place);
    await _saveToStorage();

    debugPrint('💾 Saved place: $name');
    return place;
  }

  /// 🗑️ ลบสถานที่
  Future<void> removePlace(String placeId) async {
    _savedPlaces.removeWhere((p) => p.id == placeId);
    await _saveToStorage();
  }

  /// 📝 บันทึกการเยี่ยมชม
  Future<void> recordVisit({
    required String placeId,
    String? placeName,
    double? lat,
    double? lng,
    String? activity,
  }) async {
    final visit = PlaceVisit(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      placeId: placeId,
      placeName: placeName,
      latitude: lat,
      longitude: lng,
      activity: activity,
      visitedAt: DateTime.now(),
    );

    _visitHistory.add(visit);

    // อัพเดต visit count
    final placeIndex = _savedPlaces.indexWhere((p) => p.id == placeId);
    if (placeIndex >= 0) {
      _savedPlaces[placeIndex] = _savedPlaces[placeIndex].copyWith(
        visitCount: _savedPlaces[placeIndex].visitCount + 1,
        lastVisit: DateTime.now(),
      );
    }

    // เก็บ history ไม่เกิน 500 รายการ
    if (_visitHistory.length > 500) {
      _visitHistory = _visitHistory.sublist(_visitHistory.length - 500);
    }

    await _saveToStorage();
  }

  // ============================================================
  // 🎯 RECOMMENDATIONS
  // ============================================================

  /// 🎯 แนะนำสถานที่จาก history
  List<SavedPlace> getRecommendations({
    double? nearLat,
    double? nearLng,
    String? category,
    int limit = 5,
  }) {
    var places = List<SavedPlace>.from(_savedPlaces);

    // Filter by category
    if (category != null) {
      places = places.where((p) => p.category == category).toList();
    }

    // Sort by relevance
    places.sort((a, b) {
      // Factor 1: Visit count
      final visitScore = b.visitCount.compareTo(a.visitCount);
      if (visitScore != 0) return visitScore;

      // Factor 2: Recency
      if (a.lastVisit != null && b.lastVisit != null) {
        return b.lastVisit!.compareTo(a.lastVisit!);
      }

      return 0;
    });

    // Filter by distance if location provided
    if (nearLat != null && nearLng != null) {
      places = places.where((p) {
        final distance = Geolocator.distanceBetween(
          nearLat,
          nearLng,
          p.latitude,
          p.longitude,
        );
        return distance < 10000; // within 10km
      }).toList();

      // Re-sort by distance
      places.sort((a, b) {
        final distA = Geolocator.distanceBetween(
          nearLat,
          nearLng,
          a.latitude,
          a.longitude,
        );
        final distB = Geolocator.distanceBetween(
          nearLat,
          nearLng,
          b.latitude,
          b.longitude,
        );
        return distA.compareTo(distB);
      });
    }

    return places.take(limit).toList();
  }

  /// 🕐 ดึงสถานที่ที่ไปบ่อยตามช่วงเวลา
  List<SavedPlace> getFrequentPlacesByTime(int hour) {
    // วิเคราะห์ว่าช่วงเวลานี้มักไปที่ไหน
    final timeVisits = _visitHistory.where((v) {
      final visitHour = v.visitedAt.hour;
      return (visitHour - hour).abs() <= 2; // ±2 ชั่วโมง
    }).toList();

    // นับความถี่
    final frequency = <String, int>{};
    for (final visit in timeVisits) {
      frequency[visit.placeId] = (frequency[visit.placeId] ?? 0) + 1;
    }

    // เรียงตามความถี่
    final sortedIds = frequency.keys.toList()
      ..sort((a, b) => frequency[b]!.compareTo(frequency[a]!));

    return sortedIds
        .take(3)
        .map((id) => _savedPlaces.firstWhere(
              (p) => p.id == id,
              orElse: () => _savedPlaces.first,
            ))
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

  /// 📊 ดึงสถิติสถานที่
  Map<String, dynamic> getPlaceStats() {
    final categoryCount = <String, int>{};
    for (final place in _savedPlaces) {
      categoryCount[place.category] =
          (categoryCount[place.category] ?? 0) + 1;
    }

    final totalVisits = _visitHistory.length;
    final uniquePlaces = _visitHistory.map((v) => v.placeId).toSet().length;

    return {
      'totalPlaces': _savedPlaces.length,
      'totalVisits': totalVisits,
      'uniquePlacesVisited': uniquePlaces,
      'categoryCounts': categoryCount,
      'mostVisited': _savedPlaces.isNotEmpty
          ? (_savedPlaces.toList()
                ..sort((a, b) => b.visitCount.compareTo(a.visitCount)))
              .first
          : null,
    };
  }

  /// 📍 Get current position
  Future<Position?> getCurrentPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
    } catch (e) {
      debugPrint('⚠️ Error getting position: $e');
      return null;
    }
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// 🔍 ผลการค้นหาสถานที่
class PlaceResult {
  final String? placeId;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final double? rating;
  final int? userRatingsTotal;
  final List<String> types;
  final bool isOpen;

  PlaceResult({
    this.placeId,
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    this.rating,
    this.userRatingsTotal,
    this.types = const [],
    this.isOpen = false,
  });

  factory PlaceResult.fromGoogleJson(Map<String, dynamic> json) {
    final location = json['geometry']['location'];
    return PlaceResult(
      placeId: json['place_id'] as String?,
      name: json['name'] as String,
      address: json['formatted_address'] as String?,
      latitude: location['lat'] as double,
      longitude: location['lng'] as double,
      rating: (json['rating'] as num?)?.toDouble(),
      userRatingsTotal: json['user_ratings_total'] as int?,
      types: List<String>.from(json['types'] ?? []),
      isOpen: json['opening_hours']?['open_now'] ?? false,
    );
  }

  factory PlaceResult.fromNominatimJson(Map<String, dynamic> json) {
    return PlaceResult(
      name: json['display_name']?.split(',').first ?? 'Unknown',
      address: json['display_name'] as String?,
      latitude: double.parse(json['lat'] as String),
      longitude: double.parse(json['lon'] as String),
      types: [json['type'] as String? ?? 'place'],
    );
  }

  String get displayRating => rating != null ? '${rating!.toStringAsFixed(1)}⭐' : '';

  String get typeIcon {
    if (types.contains('restaurant')) return '🍽️';
    if (types.contains('cafe')) return '☕';
    if (types.contains('bar')) return '🍺';
    if (types.contains('store') || types.contains('shopping_mall')) return '🛍️';
    if (types.contains('gym')) return '💪';
    if (types.contains('hospital') || types.contains('doctor')) return '🏥';
    if (types.contains('school') || types.contains('university')) return '🎓';
    if (types.contains('park')) return '🌳';
    if (types.contains('hotel') || types.contains('lodging')) return '🏨';
    return '📍';
  }
}

/// 📄 รายละเอียดสถานที่
class PlaceDetails {
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final double? rating;
  final List<PlaceReview> reviews;
  final List<String> openingHours;
  final String? website;
  final String? phone;
  final List<String> photoRefs;

  PlaceDetails({
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    this.rating,
    this.reviews = const [],
    this.openingHours = const [],
    this.website,
    this.phone,
    this.photoRefs = const [],
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final location = json['geometry']['location'];
    final reviews = (json['reviews'] as List?)
            ?.map((r) => PlaceReview.fromJson(r))
            .toList() ??
        [];

    return PlaceDetails(
      name: json['name'] as String,
      address: json['formatted_address'] as String?,
      latitude: location['lat'] as double,
      longitude: location['lng'] as double,
      rating: (json['rating'] as num?)?.toDouble(),
      reviews: reviews,
      openingHours: List<String>.from(
        json['opening_hours']?['weekday_text'] ?? [],
      ),
      website: json['website'] as String?,
      phone: json['formatted_phone_number'] as String?,
      photoRefs: (json['photos'] as List?)
              ?.map((p) => p['photo_reference'] as String)
              .toList() ??
          [],
    );
  }
}

/// ⭐ รีวิวสถานที่
class PlaceReview {
  final String authorName;
  final double rating;
  final String text;
  final DateTime time;

  PlaceReview({
    required this.authorName,
    required this.rating,
    required this.text,
    required this.time,
  });

  factory PlaceReview.fromJson(Map<String, dynamic> json) {
    return PlaceReview(
      authorName: json['author_name'] as String,
      rating: (json['rating'] as num).toDouble(),
      text: json['text'] as String,
      time: DateTime.fromMillisecondsSinceEpoch(
        (json['time'] as int) * 1000,
      ),
    );
  }
}

/// 💾 สถานที่ที่บันทึก
class SavedPlace {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;
  final String? placeId;
  final String category;
  final String icon;
  final String? notes;
  final DateTime createdAt;
  final int visitCount;
  final DateTime? lastVisit;

  SavedPlace({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
    this.placeId,
    required this.category,
    required this.icon,
    this.notes,
    required this.createdAt,
    required this.visitCount,
    this.lastVisit,
  });

  SavedPlace copyWith({
    int? visitCount,
    DateTime? lastVisit,
    String? notes,
  }) {
    return SavedPlace(
      id: id,
      name: name,
      latitude: latitude,
      longitude: longitude,
      address: address,
      placeId: placeId,
      category: category,
      icon: icon,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      visitCount: visitCount ?? this.visitCount,
      lastVisit: lastVisit ?? this.lastVisit,
    );
  }

  factory SavedPlace.fromJson(Map<String, dynamic> json) {
    return SavedPlace(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      address: json['address'] as String?,
      placeId: json['placeId'] as String?,
      category: json['category'] as String,
      icon: json['icon'] as String,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      visitCount: json['visitCount'] as int,
      lastVisit: json['lastVisit'] != null
          ? DateTime.parse(json['lastVisit'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'placeId': placeId,
      'category': category,
      'icon': icon,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'visitCount': visitCount,
      'lastVisit': lastVisit?.toIso8601String(),
    };
  }
}

/// 📍 การเยี่ยมชมสถานที่
class PlaceVisit {
  final String id;
  final String placeId;
  final String? placeName;
  final double? latitude;
  final double? longitude;
  final String? activity;
  final DateTime visitedAt;

  PlaceVisit({
    required this.id,
    required this.placeId,
    this.placeName,
    this.latitude,
    this.longitude,
    this.activity,
    required this.visitedAt,
  });

  factory PlaceVisit.fromJson(Map<String, dynamic> json) {
    return PlaceVisit(
      id: json['id'] as String,
      placeId: json['placeId'] as String,
      placeName: json['placeName'] as String?,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      activity: json['activity'] as String?,
      visitedAt: DateTime.parse(json['visitedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'placeId': placeId,
      'placeName': placeName,
      'latitude': latitude,
      'longitude': longitude,
      'activity': activity,
      'visitedAt': visitedAt.toIso8601String(),
    };
  }
}

/// 📂 Place categories
class PlaceCategories {
  static const String restaurant = 'restaurant';
  static const String cafe = 'cafe';
  static const String work = 'work';
  static const String home = 'home';
  static const String gym = 'gym';
  static const String shopping = 'shopping';
  static const String entertainment = 'entertainment';
  static const String health = 'health';
  static const String education = 'education';
  static const String other = 'other';

  static String getIcon(String category) {
    switch (category) {
      case restaurant:
        return '🍽️';
      case cafe:
        return '☕';
      case work:
        return '🏢';
      case home:
        return '🏠';
      case gym:
        return '💪';
      case shopping:
        return '🛍️';
      case entertainment:
        return '🎬';
      case health:
        return '🏥';
      case education:
        return '🎓';
      default:
        return '📍';
    }
  }

  static String getLabel(String category) {
    switch (category) {
      case restaurant:
        return 'ร้านอาหาร';
      case cafe:
        return 'คาเฟ่';
      case work:
        return 'ที่ทำงาน';
      case home:
        return 'บ้าน';
      case gym:
        return 'ฟิตเนส';
      case shopping:
        return 'ช้อปปิ้ง';
      case entertainment:
        return 'บันเทิง';
      case health:
        return 'สุขภาพ';
      case education:
        return 'การศึกษา';
      default:
        return 'อื่นๆ';
    }
  }
}
