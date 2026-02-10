import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'battery_aware_service.dart';

/// 📍 Unified Location Service - รวม GPS, Place, Geofence
///
/// รวมจาก 3 ไฟล์:
/// - location_service.dart (GPS, positioning)
/// - place_service.dart (place search, saved places)
/// - geofence_service.dart (geofencing, zone monitoring)
///
/// Features:
/// - 🔋 Battery optimized: Significant location change, distance filter
/// - 🗺️ Place search: Google Places + Nominatim (OSM)
/// - 📍 Geofencing: Enter/exit zone detection
/// - 💾 Saved places: With visit tracking

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final BatteryAwareService _batteryService = BatteryAwareService();

  // ============================================================================
  // CONSTANTS
  // ============================================================================
  static const int _distanceFilter = 100; // meters
  static const int _minimumAccuracy = 50; // meters
  static const double _significantDistance = 200.0; // meters
  static const double _defaultRadius = 100.0; // meters

  // Storage keys
  static const String _placesKey = 'saved_places';
  static const String _historyKey = 'place_history';
  static const String _zonesKey = 'geofence_zones';
  static const String _lastLocationKey = 'last_known_location';
  static const String _apiKeyKey = 'google_places_api_key';

  // ============================================================================
  // STATE
  // ============================================================================
  String? _googleApiKey;
  List<SavedPlace> _savedPlaces = [];
  List<PlaceVisit> _visitHistory = [];
  List<GeofenceZone> _zones = [];

  Position? _lastKnownPosition;
  String? _currentZoneId;
  Timer? _checkTimer;

  bool _isInitialized = false;
  bool _isMonitoring = false;

  // Callbacks
  void Function(GeofenceZone zone)? onEnterZone;
  void Function(GeofenceZone zone)? onExitZone;
  void Function(Position position)? onSignificantLocationChange;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadApiKey();
    await _loadSavedPlaces();
    await _loadVisitHistory();
    await _loadZones();
    await _loadLastLocation();

    _isInitialized = true;
    debugPrint('✅ Location Service initialized');
    debugPrint('   - Saved places: ${_savedPlaces.length}');
    debugPrint('   - Zones: ${_zones.length}');
    debugPrint('   - Visit history: ${_visitHistory.length}');
  }

  // ============================================================================
  // PERMISSION & BASIC LOCATION (จาก location_service.dart เดิม)
  // ============================================================================

  /// ✅ ขอ Permission
  static Future<bool> requestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  /// 📍 ดึงตำแหน่งปัจจุบัน (ครั้งเดียว)
  static Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      if (position.accuracy > _minimumAccuracy) return null;
      return position;
    } catch (e) {
      return null;
    }
  }

  /// 🏷️ Reverse Geocoding
  static Future<String?> getLocationName(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return null;

      final place = placemarks.first;
      final parts = <String>[];

      if (place.name != null && place.name!.isNotEmpty &&
          place.name != place.street && place.name != place.subLocality) {
        parts.add(place.name!);
      }
      if (place.street != null && place.street!.isNotEmpty) {
        parts.add(place.street!);
      }
      if (place.subLocality != null && place.subLocality!.isNotEmpty) {
        parts.add(place.subLocality!);
      }
      if (place.locality != null && place.locality!.isNotEmpty) {
        parts.add(place.locality!);
      }

      return parts.take(2).join(', ');
    } catch (e) {
      return null;
    }
  }

  /// 🔄 Position Stream
  static Stream<Position>? getPositionStream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: _distanceFilter,
        ),
      );

  /// 📊 คำนวณระยะห่าง (เมตร)
  static double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) => Geolocator.distanceBetween(startLat, startLng, endLat, endLng);

  /// 🛑 ตรวจสอบ GPS เปิดอยู่
  static Future<bool> isLocationEnabled() => Geolocator.isLocationServiceEnabled();

  // ============================================================================
  // PLACE SEARCH (จาก place_service.dart)
  // ============================================================================

  bool get hasApiKey => _googleApiKey != null && _googleApiKey!.isNotEmpty;

  /// 🔍 ค้นหาสถานที่
  Future<List<PlaceResult>> searchPlaces(
    String query, {
    double? nearLat,
    double? nearLng,
    int radius = 5000,
    String? type,
  }) async {
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
        return results.map((r) => PlaceResult.fromGoogleJson(r as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Google Places search error: $e');
    }

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
        if (nearLat != null && nearLng != null)
          'viewbox': '${nearLng - 0.1},${nearLat - 0.1},${nearLng + 0.1},${nearLat + 0.1}',
      };

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'HakuApp/1.0'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> results = jsonDecode(response.body) as List<dynamic>;
        return results.map((r) => PlaceResult.fromNominatimJson(r as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Nominatim search error: $e');
    }
    return [];
  }

  /// 📍 ค้นหาใกล้เคียง
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
        return results.map((r) => PlaceResult.fromGoogleJson(r as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Nearby search error: $e');
    }
    return [];
  }

  // ============================================================================
  // SAVED PLACES (จาก place_service.dart)
  // ============================================================================

  List<SavedPlace> get savedPlaces => List.unmodifiable(_savedPlaces);
  List<PlaceVisit> get visitHistory => List.unmodifiable(_visitHistory);

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
    await _savePlacesToStorage();
    debugPrint('💾 Saved place: $name');
    return place;
  }

  /// 🗑️ ลบสถานที่
  Future<void> removePlace(String placeId) async {
    _savedPlaces.removeWhere((p) => p.id == placeId);
    await _savePlacesToStorage();
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

    final placeIndex = _savedPlaces.indexWhere((p) => p.id == placeId);
    if (placeIndex >= 0) {
      _savedPlaces[placeIndex] = _savedPlaces[placeIndex].copyWith(
        visitCount: _savedPlaces[placeIndex].visitCount + 1,
        lastVisit: DateTime.now(),
      );
    }

    if (_visitHistory.length > 500) {
      _visitHistory = _visitHistory.sublist(_visitHistory.length - 500);
    }

    await _savePlacesToStorage();
  }

  /// 🎯 แนะนำสถานที่
  List<SavedPlace> getRecommendations({
    double? nearLat,
    double? nearLng,
    String? category,
    int limit = 5,
  }) {
    var places = List<SavedPlace>.from(_savedPlaces);

    if (category != null) {
      places = places.where((p) => p.category == category).toList();
    }

    places.sort((a, b) {
      final visitScore = b.visitCount.compareTo(a.visitCount);
      if (visitScore != 0) return visitScore;
      if (a.lastVisit != null && b.lastVisit != null) {
        return b.lastVisit!.compareTo(a.lastVisit!);
      }
      return 0;
    });

    if (nearLat != null && nearLng != null) {
      places = places.where((p) {
        final distance = calculateDistance(nearLat, nearLng, p.latitude, p.longitude);
        return distance < 10000; // 10km
      }).toList();

      places.sort((a, b) {
        final distA = calculateDistance(nearLat, nearLng, a.latitude, a.longitude);
        final distB = calculateDistance(nearLat, nearLng, b.latitude, b.longitude);
        return distA.compareTo(distB);
      });
    }

    return places.take(limit).toList();
  }

  /// 🕐 สถานที่ที่ไปบ่อยตามช่วงเวลา
  List<SavedPlace> getFrequentPlacesByTime(int hour) {
    final timeVisits = _visitHistory.where((v) {
      final visitHour = v.visitedAt.hour;
      return (visitHour - hour).abs() <= 2;
    }).toList();

    final frequency = <String, int>{};
    for (final visit in timeVisits) {
      frequency[visit.placeId] = (frequency[visit.placeId] ?? 0) + 1;
    }

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

  // ============================================================================
  // GEOFENCE (จาก geofence_service.dart)
  // ============================================================================

  List<GeofenceZone> get zones => List.unmodifiable(_zones);
  String? get currentZoneId => _currentZoneId;
  GeofenceZone? get currentZone => _currentZoneId != null
      ? _zones.firstWhere((z) => z.id == _currentZoneId, orElse: () => _zones.first)
      : null;
  bool get isMonitoring => _isMonitoring;

  /// ➕ เพิ่ม geofence zone
  Future<void> addZone({
    required String name,
    required double latitude,
    required double longitude,
    double radius = _defaultRadius,
    String? icon,
  }) async {
    final zone = GeofenceZone(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      latitude: latitude,
      longitude: longitude,
      radius: radius,
      icon: icon ?? '📍',
      createdAt: DateTime.now(),
    );

    _zones.add(zone);
    await _saveZonesToStorage();
    debugPrint('➕ Added geofence zone: $name');
  }

  /// ➕ เพิ่ม zone จากตำแหน่งปัจจุบัน
  Future<void> addZoneAtCurrentLocation(String name, {String? icon}) async {
    final position = await getCurrentPosition();
    if (position != null) {
      await addZone(
        name: name,
        latitude: position.latitude,
        longitude: position.longitude,
        icon: icon,
      );
    }
  }

  /// 🗑️ ลบ zone
  Future<void> removeZone(String zoneId) async {
    _zones.removeWhere((z) => z.id == zoneId);
    await _saveZonesToStorage();
  }

  /// ▶️ เริ่ม monitoring
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    final permission = await requestPermission();
    if (!permission) {
      debugPrint('⚠️ Location permission denied');
      return;
    }

    _isMonitoring = true;
    await _checkCurrentLocation();
    _startPeriodicCheck();
    debugPrint('▶️ Geofence monitoring started');
  }

  /// ⏹️ หยุด monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _checkTimer?.cancel();
    debugPrint('⏹️ Geofence monitoring stopped');
  }

  /// 🏠 Add common zones
  Future<void> addHomeZone(double lat, double lng) async {
    await addZone(name: 'บ้าน', latitude: lat, longitude: lng, radius: 150, icon: '🏠');
  }

  Future<void> addWorkZone(double lat, double lng) async {
    await addZone(name: 'ที่ทำงาน', latitude: lat, longitude: lng, radius: 200, icon: '🏢');
  }

  Future<void> addGymZone(double lat, double lng) async {
    await addZone(name: 'ฟิตเนส', latitude: lat, longitude: lng, radius: 100, icon: '💪');
  }

  // ============================================================================
  // PRIVATE METHODS
  // ============================================================================

  void _startPeriodicCheck() {
    _checkTimer?.cancel();

    final profile = _batteryService.getRecommendedProfile();
    final interval = Duration(minutes: profile.triggerIntervalMinutes);

    _checkTimer = Timer.periodic(interval, (_) async {
      if (!_isMonitoring) return;
      await _checkCurrentLocation();
    });

    debugPrint('⏱️ Geofence check interval: ${interval.inMinutes} min');
  }

  Future<void> _checkCurrentLocation() async {
    final position = await getCurrentPosition();
    if (position == null) return;

    // Check significant change
    if (_lastKnownPosition != null) {
      final distance = calculateDistance(
        _lastKnownPosition!.latitude,
        _lastKnownPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (distance > _significantDistance) {
        debugPrint('📍 Significant location change: ${distance.toInt()}m');
        onSignificantLocationChange?.call(position);
      }
    }

    // Check zone transitions
    final previousZoneId = _currentZoneId;
    _currentZoneId = _findCurrentZone(position);

    // Zone exit
    if (previousZoneId != null && _currentZoneId != previousZoneId) {
      final exitedZone = _zones.firstWhere(
        (z) => z.id == previousZoneId,
        orElse: () => _zones.first,
      );
      debugPrint('🚪 Exited zone: ${exitedZone.name}');
      onExitZone?.call(exitedZone);
    }

    // Zone enter
    if (_currentZoneId != null && _currentZoneId != previousZoneId) {
      final enteredZone = _zones.firstWhere((z) => z.id == _currentZoneId);
      debugPrint('🏠 Entered zone: ${enteredZone.name}');
      onEnterZone?.call(enteredZone);
    }

    _lastKnownPosition = position;
    await _saveLastLocation();
  }

  String? _findCurrentZone(Position position) {
    for (final zone in _zones) {
      final distance = calculateDistance(
        zone.latitude,
        zone.longitude,
        position.latitude,
        position.longitude,
      );
      if (distance <= zone.radius) return zone.id;
    }
    return null;
  }

  // ============================================================================
  // STORAGE
  // ============================================================================

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    _googleApiKey = prefs.getString(_apiKeyKey);
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key);
    _googleApiKey = key;
  }

  Future<void> _loadSavedPlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_placesKey);
      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _savedPlaces = list.map((e) => SavedPlace.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading saved places: $e');
    }
  }

  Future<void> _loadVisitHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_historyKey);
      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _visitHistory = list.map((e) => PlaceVisit.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading visit history: $e');
    }
  }

  Future<void> _savePlacesToStorage() async {
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

  Future<void> _loadZones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_zonesKey);
      if (json != null) {
        final List<dynamic> list = jsonDecode(json) as List<dynamic>;
        _zones = list.map((e) => GeofenceZone.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading geofence zones: $e');
    }
  }

  Future<void> _saveZonesToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _zonesKey,
        jsonEncode(_zones.map((z) => z.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving geofence zones: $e');
    }
  }

  Future<void> _loadLastLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_lastLocationKey);
      if (json != null) {
        final data = jsonDecode(json);
        _lastKnownPosition = Position(
          latitude: data['lat'] as double,
          longitude: data['lng'] as double,
          timestamp: DateTime.parse(data['ts'] as String),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
        _currentZoneId = data['zoneId'] as String?;
      }
    } catch (e) {
      debugPrint('⚠️ Error loading last location: $e');
    }
  }

  Future<void> _saveLastLocation() async {
    if (_lastKnownPosition == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastLocationKey,
        jsonEncode({
          'lat': _lastKnownPosition!.latitude,
          'lng': _lastKnownPosition!.longitude,
          'ts': _lastKnownPosition!.timestamp.toIso8601String(),
          'zoneId': _currentZoneId,
        }),
      );
    } catch (e) {
      debugPrint('⚠️ Error saving last location: $e');
    }
  }

  void dispose() {
    stopMonitoring();
    _isInitialized = false;
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

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
      types: List<String>.from((json['types'] as List<dynamic>?) ?? []),
      isOpen: (json['opening_hours'] as Map<String, dynamic>?)?['open_now'] as bool? ?? false,
    );
  }

  factory PlaceResult.fromNominatimJson(Map<String, dynamic> json) => PlaceResult(
        name: (json['display_name'] as String?)?.split(',').first ?? 'Unknown',
        address: json['display_name'] as String?,
        latitude: double.parse(json['lat'] as String),
        longitude: double.parse(json['lon'] as String),
        types: [json['type'] as String? ?? 'place'],
      );

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
  }) =>
      SavedPlace(
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

  factory SavedPlace.fromJson(Map<String, dynamic> json) => SavedPlace(
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

  Map<String, dynamic> toJson() => {
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

  factory PlaceVisit.fromJson(Map<String, dynamic> json) => PlaceVisit(
        id: json['id'] as String,
        placeId: json['placeId'] as String,
        placeName: json['placeName'] as String?,
        latitude: json['latitude'] as double?,
        longitude: json['longitude'] as double?,
        activity: json['activity'] as String?,
        visitedAt: DateTime.parse(json['visitedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'placeId': placeId,
        'placeName': placeName,
        'latitude': latitude,
        'longitude': longitude,
        'activity': activity,
        'visitedAt': visitedAt.toIso8601String(),
      };
}

/// 📍 Geofence Zone
class GeofenceZone {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radius; // meters
  final String icon;
  final DateTime createdAt;

  GeofenceZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.icon,
    required this.createdAt,
  });

  factory GeofenceZone.fromJson(Map<String, dynamic> json) => GeofenceZone(
        id: json['id'] as String,
        name: json['name'] as String,
        latitude: json['latitude'] as double,
        longitude: json['longitude'] as double,
        radius: json['radius'] as double,
        icon: json['icon'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
        'icon': icon,
        'createdAt': createdAt.toIso8601String(),
      };
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
