import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'battery_aware_service.dart';

/// 📍 Geofence Service - ใช้ geofencing แทน GPS streaming
///
/// Features:
/// - ลงทะเบียน geofence zones (บ้าน, ที่ทำงาน, etc.)
/// - ตรวจจับ enter/exit โดยไม่ต้อง stream GPS ตลอด
/// - ใช้ significant location change แทน continuous tracking
/// - ประหยัดแบตกว่า GPS streaming มาก

class GeofenceService {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  final BatteryAwareService _batteryService = BatteryAwareService();

  static const String _zonesKey = 'geofence_zones';
  static const String _lastLocationKey = 'last_known_location';

  // Geofence zones
  List<GeofenceZone> _zones = [];

  // Current state
  Position? _lastKnownPosition;
  String? _currentZoneId;
  Timer? _checkTimer;

  bool _isInitialized = false;
  bool _isMonitoring = false;

  // Callbacks
  void Function(GeofenceZone zone)? onEnterZone;
  void Function(GeofenceZone zone)? onExitZone;
  void Function(Position position)? onSignificantLocationChange;

  // Settings
  static const double defaultRadius = 100.0; // meters
  static const double significantDistance = 200.0; // meters
  static const Duration checkInterval = Duration(minutes: 5);

  // Getters
  List<GeofenceZone> get zones => List.unmodifiable(_zones);
  String? get currentZoneId => _currentZoneId;
  GeofenceZone? get currentZone =>
      _currentZoneId != null ? _zones.firstWhere((z) => z.id == _currentZoneId, orElse: () => _zones.first) : null;
  bool get isMonitoring => _isMonitoring;

  /// 🚀 Initialize service
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadZones();
    await _loadLastLocation();

    _isInitialized = true;
    debugPrint('✅ Geofence Service initialized');
    debugPrint('   - Zones: ${_zones.length}');
  }

  /// 📥 Load zones from storage
  Future<void> _loadZones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_zonesKey);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json);
        _zones = list.map((e) => GeofenceZone.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading geofence zones: $e');
    }
  }

  /// 💾 Save zones to storage
  Future<void> _saveZones() async {
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

  /// 📍 Load last known location
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

  /// 💾 Save last known location
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

  /// ➕ เพิ่ม geofence zone
  Future<void> addZone({
    required String name,
    required double latitude,
    required double longitude,
    double radius = defaultRadius,
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
    await _saveZones();

    debugPrint('➕ Added geofence zone: $name');
  }

  /// ➕ เพิ่ม zone จากตำแหน่งปัจจุบัน
  Future<void> addZoneAtCurrentLocation(String name, {String? icon}) async {
    final position = await _getCurrentPosition();
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
    await _saveZones();
  }

  /// ▶️ เริ่ม monitoring
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    // ตรวจสอบ permission
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final newPermission = await Geolocator.requestPermission();
      if (newPermission == LocationPermission.denied ||
          newPermission == LocationPermission.deniedForever) {
        debugPrint('⚠️ Location permission denied');
        return;
      }
    }

    _isMonitoring = true;

    // Check ทันที
    await _checkCurrentLocation();

    // ตั้ง periodic check (ตาม battery level)
    _startPeriodicCheck();

    debugPrint('▶️ Geofence monitoring started');
  }

  /// ⏹️ หยุด monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _checkTimer?.cancel();
    debugPrint('⏹️ Geofence monitoring stopped');
  }

  /// ⏱️ Start periodic check
  void _startPeriodicCheck() {
    _checkTimer?.cancel();

    // ปรับ interval ตาม battery
    final profile = _batteryService.getRecommendedProfile();
    final interval = Duration(minutes: profile.triggerIntervalMinutes);

    _checkTimer = Timer.periodic(interval, (_) async {
      if (!_isMonitoring) return;
      await _checkCurrentLocation();
    });

    debugPrint('⏱️ Geofence check interval: ${interval.inMinutes} min');
  }

  /// 📍 Check current location
  Future<void> _checkCurrentLocation() async {
    final position = await _getCurrentPosition();
    if (position == null) return;

    // Check significant change
    if (_lastKnownPosition != null) {
      final distance = _calculateDistance(
        _lastKnownPosition!.latitude,
        _lastKnownPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (distance > significantDistance) {
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

  /// 🔍 Find current zone
  String? _findCurrentZone(Position position) {
    for (final zone in _zones) {
      final distance = _calculateDistance(
        zone.latitude,
        zone.longitude,
        position.latitude,
        position.longitude,
      );

      if (distance <= zone.radius) {
        return zone.id;
      }
    }
    return null;
  }

  /// 📍 Get current position (low power)
  Future<Position?> _getCurrentPosition() async {
    try {
      // ใช้ low accuracy เพื่อประหยัดแบต
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('⚠️ Error getting position: $e');
      return null;
    }
  }

  /// 📐 Calculate distance between two points (Haversine formula)
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // meters

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  /// 🏠 Add common zones
  Future<void> addHomeZone(double lat, double lng) async {
    await addZone(
      name: 'บ้าน',
      latitude: lat,
      longitude: lng,
      radius: 150,
      icon: '🏠',
    );
  }

  Future<void> addWorkZone(double lat, double lng) async {
    await addZone(
      name: 'ที่ทำงาน',
      latitude: lat,
      longitude: lng,
      radius: 200,
      icon: '🏢',
    );
  }

  Future<void> addGymZone(double lat, double lng) async {
    await addZone(
      name: 'ฟิตเนส',
      latitude: lat,
      longitude: lng,
      radius: 100,
      icon: '💪',
    );
  }

  /// 🧹 Dispose
  void dispose() {
    stopMonitoring();
    _isInitialized = false;
  }
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

  factory GeofenceZone.fromJson(Map<String, dynamic> json) {
    return GeofenceZone(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      radius: json['radius'] as double,
      icon: json['icon'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'icon': icon,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
