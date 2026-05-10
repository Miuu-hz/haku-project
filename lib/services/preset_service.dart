import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/preset.dart';
import 'location_service.dart';

/// 🎭 Preset Service - จัดการ Preset และ Auto-Switch
///
/// หน้าที่หลัก:
/// 1. เก็บและจัดการ Presets ทั้งหมด
/// 2. ตรวจจับ Trigger conditions
/// 3. Auto-switch preset ตามเงื่อนไข
/// 4. ให้ AI สามารถสั่ง switch preset ได้

class PresetService {
  static final PresetService _instance = PresetService._internal();
  factory PresetService() => _instance;
  PresetService._internal();

  static const String _prefsKey = 'haku_presets';
  static const String _currentPresetKey = 'haku_current_preset';
  static const String _savedLocationsKey = 'haku_saved_locations';

  // Presets ทั้งหมด
  List<Preset> _presets = [];
  List<Preset> get presets => List.unmodifiable(_presets);

  // Preset ปัจจุบัน
  Preset? _currentPreset;
  Preset? get currentPreset => _currentPreset;

  // Saved locations (home, office, etc.)
  Map<String, SavedLocation> _savedLocations = {};
  Map<String, SavedLocation> get savedLocations =>
      Map.unmodifiable(_savedLocations);

  // Auto-switch timer
  Timer? _autoSwitchTimer;
  StreamSubscription<Position>? _locationSubscription;

  // Callbacks
  void Function(Preset oldPreset, Preset newPreset)? onPresetChanged;
  void Function(PresetAction action)? onActionTriggered;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 🚀 เริ่มต้น service
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadPresets();
    await _loadSavedLocations();
    await _loadCurrentPreset();

    // เริ่ม auto-switch (เช็คทุก 5 นาที - battery optimized)
    _startAutoSwitch();

    _isInitialized = true;
    debugPrint('✅ Preset Service initialized');
    debugPrint('   - Presets: ${_presets.length}');
    debugPrint('   - Current: ${_currentPreset?.name ?? 'None'}');
  }

  /// 📦 โหลด presets จาก storage
  Future<void> _loadPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);

      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
        _presets = jsonList
            .map((j) => Preset.fromJson(j as Map<String, dynamic>))
            .toList();
      }

      // เพิ่ม default presets ถ้ายังไม่มี
      if (_presets.isEmpty) {
        _presets = List.from(DefaultPresets.all);
        await _savePresets();
      }
    } catch (e) {
      debugPrint('⚠️ Load presets failed: $e');
      _presets = List.from(DefaultPresets.all);
    }
  }

  /// 💾 บันทึก presets
  Future<void> _savePresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_presets.map((p) => p.toJson()).toList());
      await prefs.setString(_prefsKey, jsonStr);
    } catch (e) {
      debugPrint('⚠️ Save presets failed: $e');
    }
  }

  /// 📍 โหลด saved locations
  Future<void> _loadSavedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_savedLocationsKey);

      if (jsonStr != null) {
        final Map<String, dynamic> jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
        _savedLocations = jsonMap.map(
          (k, v) => MapEntry(k, SavedLocation.fromJson(v as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Load saved locations failed: $e');
    }
  }

  /// 💾 บันทึก saved locations
  Future<void> _saveSavedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(
        _savedLocations.map((k, v) => MapEntry(k, v.toJson())),
      );
      await prefs.setString(_savedLocationsKey, jsonStr);
    } catch (e) {
      debugPrint('⚠️ Save saved locations failed: $e');
    }
  }

  /// 🗑️ ลบ saved location
  Future<void> removeLocation(String type) async {
    _savedLocations.remove(type);
    await _saveSavedLocations();
    debugPrint('🗑️ Removed location: $type');
  }

  /// 🏠 บันทึกตำแหน่ง (home, office, etc.)
  Future<void> saveLocation(String type, SavedLocation location) async {
    _savedLocations[type] = location;
    await _saveSavedLocations();
    debugPrint('📍 Saved location: $type → ${location.name}');
  }

  /// 📍 ดึงตำแหน่งปัจจุบันและบันทึกเป็น type ที่กำหนด
  Future<bool> saveCurrentLocationAs(String type) async {
    final position = await LocationService.getCurrentPosition();
    if (position == null) return false;

    final name = await LocationService.getLocationName(
      position.latitude,
      position.longitude,
    );

    final location = SavedLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      name: name ?? type,
      type: type,
    );

    await saveLocation(type, location);
    return true;
  }

  /// 🎭 โหลด current preset
  Future<void> _loadCurrentPreset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final presetId = prefs.getString(_currentPresetKey);

      if (presetId != null) {
        _currentPreset = _presets.firstWhere(
          (p) => p.id == presetId,
          orElse: () => _presets.first,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Load current preset failed: $e');
    }
  }

  /// 🔄 เปลี่ยน Preset
  Future<void> switchPreset(String presetId, {bool runActions = true}) async {
    final newPreset = _presets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => throw ArgumentError('Preset not found: $presetId'),
    );

    final oldPreset = _currentPreset;
    _currentPreset = newPreset;

    // บันทึก
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentPresetKey, presetId);

    debugPrint('🎭 Switched preset: ${oldPreset?.name} → ${newPreset.name}');

    // เรียก callback
    if (oldPreset != null) {
      onPresetChanged?.call(oldPreset, newPreset);
    }

    // รัน onActivate actions
    if (runActions) {
      for (final action in newPreset.onActivate) {
        onActionTriggered?.call(action);
      }
    }
  }

  /// ➕ เพิ่ม Preset ใหม่
  Future<void> addPreset(Preset preset) async {
    _presets.add(preset);
    await _savePresets();
    debugPrint('➕ Added preset: ${preset.name}');
  }

  /// ✏️ แก้ไข Preset
  Future<void> updatePreset(Preset preset) async {
    final index = _presets.indexWhere((p) => p.id == preset.id);
    if (index == -1) return;

    _presets[index] = preset;
    await _savePresets();
    debugPrint('✏️ Updated preset: ${preset.name}');
  }

  /// 🗑️ ลบ Preset
  Future<void> deletePreset(String presetId) async {
    _presets.removeWhere((p) => p.id == presetId);
    await _savePresets();
    debugPrint('🗑️ Deleted preset: $presetId');
  }

  /// ⏰ เริ่ม Auto-Switch
  void _startAutoSwitch() {
    // เช็คทุก 5 นาที (battery optimized)
    _autoSwitchTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkTriggers();
    });

    // เช็คครั้งแรกทันที
    _checkTriggers();
  }

  /// 🔍 ตรวจสอบ Triggers
  Future<void> _checkTriggers() async {
    final now = DateTime.now();
    final currentHour = now.hour;
    final currentMinute = now.minute;
    final currentDay = now.weekday; // 1=จันทร์, 7=อาทิตย์

    // หา preset ที่ match trigger conditions
    Preset? bestMatch;
    int bestPriority = -1;

    for (final preset in _presets) {
      if (!preset.isEnabled) continue;
      if (preset.trigger.manualOnly) continue;

      bool matches = true;

      // เช็ค time trigger
      if (preset.trigger.hasTimeTrigger) {
        final startParts = preset.trigger.timeStart!.split(':');
        final endParts = preset.trigger.timeEnd!.split(':');

        final startHour = int.parse(startParts[0]);
        final startMinute = int.parse(startParts[1]);
        final endHour = int.parse(endParts[0]);
        final endMinute = int.parse(endParts[1]);

        final currentTimeMinutes = currentHour * 60 + currentMinute;
        final startTimeMinutes = startHour * 60 + startMinute;
        final endTimeMinutes = endHour * 60 + endMinute;

        if (currentTimeMinutes < startTimeMinutes ||
            currentTimeMinutes > endTimeMinutes) {
          matches = false;
        }
      }

      // เช็ค day trigger
      if (matches && preset.trigger.hasDayTrigger) {
        if (!preset.trigger.daysOfWeek!.contains(currentDay)) {
          matches = false;
        }
      }

      // เช็ค location trigger (async)
      if (matches && preset.trigger.locationType != null) {
        final locationMatch =
            await _checkLocationTrigger(preset.trigger.locationType!);
        if (!locationMatch) {
          matches = false;
        }
      }

      // เก็บ best match
      if (matches && preset.priority > bestPriority) {
        bestMatch = preset;
        bestPriority = preset.priority;
      }
    }

    // Switch ถ้าพบ match และต่างจาก current
    if (bestMatch != null && bestMatch.id != _currentPreset?.id) {
      await switchPreset(bestMatch.id);
    }
  }

  /// 📍 เช็ค location trigger
  Future<bool> _checkLocationTrigger(String locationType) async {
    // ถ้าเป็น new_place ต้องเช็คว่าไม่ใช่ที่ที่เคยบันทึก
    if (locationType == 'new_place') {
      final position = await LocationService.getCurrentPosition();
      if (position == null) return false;

      // เช็คว่าไม่ใช่ที่บันทึกไว้
      for (final saved in _savedLocations.values) {
        final distance = LocationService.calculateDistance(
          position.latitude,
          position.longitude,
          saved.latitude,
          saved.longitude,
        );
        if (distance < 500) return false; // อยู่ใน 500m จากที่บันทึก
      }
      return true;
    }

    // เช็ค home/office
    final savedLocation = _savedLocations[locationType];
    if (savedLocation == null) return false;

    final position = await LocationService.getCurrentPosition();
    if (position == null) return false;

    final distance = LocationService.calculateDistance(
      position.latitude,
      position.longitude,
      savedLocation.latitude,
      savedLocation.longitude,
    );

    // อยู่ใน radius (default 300m)
    return distance < 300;
  }

  /// 🤖 AI สั่ง switch preset
  Future<bool> aiSwitchPreset(String presetId) async {
    try {
      await switchPreset(presetId);
      return true;
    } catch (e) {
      debugPrint('⚠️ AI switch preset failed: $e');
      return false;
    }
  }

  /// 🧹 Dispose
  void dispose() {
    _autoSwitchTimer?.cancel();
    _locationSubscription?.cancel();
    _isInitialized = false;
  }
}

/// 📍 Saved Location Model
class SavedLocation {
  final double latitude;
  final double longitude;
  final String name;
  final String type; // home, office, etc.

  const SavedLocation({
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'name': name,
        'type': type,
      };

  factory SavedLocation.fromJson(Map<String, dynamic> json) => SavedLocation(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        name: json['name'] as String,
        type: json['type'] as String,
      );
}
