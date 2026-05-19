import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'battery_aware_service.dart';
import 'location_service.dart';
import 'place_service.dart';

/// 🏠 Dwell Tracker - ติดตามว่าผู้ใช้อยู่ที่ไหนและนานแค่ไหน
///
/// รับ Position จาก GeofenceService ทุกครั้งที่มีการ poll GPS
/// ตรวจจับว่าผู้ใช้ "dwell" (อยู่นิ่ง) นานกว่า [_minDwellDuration]
/// แล้วยิง onDwellComplete เมื่อผู้ใช้ออกจากบริเวณนั้น
///
/// ไม่ import GeofenceService เพื่อหลีกเลี่ยง circular dependency
/// GeofenceService จะ push known zones มาให้ผ่าน updateKnownZones()

class DwellTracker {
  static final DwellTracker _instance = DwellTracker._internal();
  factory DwellTracker() => _instance;
  DwellTracker._internal();

  static const double _dwellRadiusMeters = 150.0;
  static const Duration _minDwellDuration = Duration(minutes: 15);

  // Known zones (set by GeofenceService เมื่อเริ่ม monitoring)
  List<ZoneSnapshot> _knownZones = [];

  // Dwell state ปัจจุบัน
  double? _anchorLat;
  double? _anchorLng;
  DateTime? _anchorStart;
  String? _anchorName;       // จาก reverse geocoding
  String? _anchorPlaceId;    // SavedPlace.id ถ้าตรงกัน
  bool _isRoutineZone = false; // true = บ้าน/ที่ทำงาน → ไม่ถาม feedback

  // Callback: ยิงเมื่อ dwell session เสร็จสมบูรณ์
  void Function(DwellSession session)? onDwellComplete;

  /// 🔄 อัพเดต zone list จาก GeofenceService (เรียกตอน startMonitoring)
  void updateKnownZones(List<ZoneSnapshot> zones) {
    _knownZones = zones;
  }

  /// 📍 รับ Position ใหม่จาก GeofenceService
  ///
  /// เรียกทุกครั้งที่ GeofenceService._checkCurrentLocation() poll GPS
  Future<void> onPosition(double lat, double lng) async {
    // ตรวจ battery profile — ถ้าปิด location tracking ให้ skip
    final profile = BatteryAwareService().getRecommendedProfile();
    if (!profile.enableLocationTracking) return;

    // ยังไม่มี anchor → เริ่ม dwell ใหม่
    if (_anchorLat == null) {
      await _startDwell(lat, lng);
      return;
    }

    // คำนวณระยะห่างจาก anchor
    final dist = Geolocator.distanceBetween(
      _anchorLat!,
      _anchorLng!,
      lat,
      lng,
    );

    if (dist <= _dwellRadiusMeters) {
      // ยังอยู่ใน zone เดิม — no-op
      return;
    }

    // ย้ายออกไปแล้ว — ตรวจว่า dwell นานพอไหม
    final now = DateTime.now();
    final dwellDuration = now.difference(_anchorStart!);

    if (dwellDuration >= _minDwellDuration) {
      // Dwell สำเร็จ → ยิง callback
      final session = DwellSession(
        lat: _anchorLat!,
        lng: _anchorLng!,
        name: _anchorName,
        placeId: _anchorPlaceId,
        arrivedAt: _anchorStart!,
        leftAt: now,
        isRoutineZone: _isRoutineZone,
      );
      debugPrint(
        '🏁 Dwell complete: ${session.displayName} '
        '(${session.duration.inMinutes} min)',
      );
      onDwellComplete?.call(session);
    }

    // เริ่ม dwell ใหม่ที่ตำแหน่งปัจจุบัน
    await _startDwell(lat, lng);
  }

  /// 🔄 เริ่ม dwell session ใหม่
  Future<void> _startDwell(double lat, double lng) async {
    _anchorLat = lat;
    _anchorLng = lng;
    _anchorStart = DateTime.now();
    _anchorName = null;
    _anchorPlaceId = null;
    _isRoutineZone = false;

    debugPrint(
      '📍 Dwell started at '
      '(${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})',
    );

    // Async: reverse geocoding + match known places (ไม่ block)
    _resolveLocation(lat, lng);
  }

  /// 🔍 Resolve location name + routine zone check แบบ async
  Future<void> _resolveLocation(double lat, double lng) async {
    // 1. Reverse geocoding
    try {
      final name = await LocationService.getLocationName(lat, lng);
      _anchorName = name;
      debugPrint('🏷️ Dwell location: $name');
    } catch (e) {
      debugPrint('⚠️ DwellTracker geocoding failed: $e');
    }

    // 2. ตรวจ known zones (จาก GeofenceService) — routine zone = บ้าน/ที่ทำงาน
    for (final zone in _knownZones) {
      final dist = Geolocator.distanceBetween(lat, lng, zone.lat, zone.lng);
      if (dist <= zone.radius) {
        if (zone.isRoutine) {
          _isRoutineZone = true;
          debugPrint('🏠 Dwell: routine zone (${zone.name})');
        }
        break;
      }
    }

    // 3. ตรวจ SavedPlaces ใกล้เคียง <= 100m
    final places = PlaceService().savedPlaces;
    for (final place in places) {
      final dist = Geolocator.distanceBetween(lat, lng, place.latitude, place.longitude);
      if (dist <= 100) {
        _anchorPlaceId = place.id;
        if (place.category == PlaceCategories.home ||
            place.category == PlaceCategories.work) {
          _isRoutineZone = true;
        }
        debugPrint('💾 Dwell: matched SavedPlace "${place.name}"');
        break;
      }
    }
  }

  /// 🧹 Reset state
  void reset() {
    _anchorLat = null;
    _anchorLng = null;
    _anchorStart = null;
    _anchorName = null;
    _anchorPlaceId = null;
    _isRoutineZone = false;
  }
}

/// 📌 ข้อมูล Zone แบบ flat (ไม่ import GeofenceZone เพื่อหลีกเลี่ยง circular)
class ZoneSnapshot {
  final double lat;
  final double lng;
  final double radius;
  final String name;
  final bool isRoutine; // true = บ้าน/ที่ทำงาน

  ZoneSnapshot({
    required this.lat,
    required this.lng,
    required this.radius,
    required this.name,
    required this.isRoutine,
  });
}

/// 📌 ข้อมูล Dwell Session ที่เสร็จสมบูรณ์
class DwellSession {
  final double lat;
  final double lng;
  final String? name;         // ชื่อสถานที่จาก reverse geocoding
  final String? placeId;      // SavedPlace.id ถ้าตรงกัน
  final DateTime arrivedAt;
  final DateTime leftAt;
  final bool isRoutineZone;   // true = บ้าน/ที่ทำงาน

  DwellSession({
    required this.lat,
    required this.lng,
    this.name,
    this.placeId,
    required this.arrivedAt,
    required this.leftAt,
    required this.isRoutineZone,
  });

  Duration get duration => leftAt.difference(arrivedAt);

  /// ชื่อแสดงผล (fallback ถ้าไม่มีชื่อ)
  String get displayName =>
      name ?? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
}

/// Factory function สร้าง ZoneSnapshot (เรียกจาก GeofenceService)
ZoneSnapshot dwellZoneSnapshot({
  required double lat,
  required double lng,
  required double radius,
  required String name,
}) {
  final nameLower = name.toLowerCase();
  final isRoutine = nameLower.contains('บ้าน') ||
      nameLower.contains('ที่ทำงาน') ||
      nameLower.contains('home') ||
      nameLower.contains('work') ||
      nameLower.contains('office');
  return ZoneSnapshot(
    lat: lat,
    lng: lng,
    radius: radius,
    name: name,
    isRoutine: isRoutine,
  );
}
