import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'context_retriever.dart';
import 'database_helper.dart';
import 'location_service.dart';

/// ⚡ MVP Trigger Service - ตัวกระตุ้นอัตโนมัติตามบริบท
/// 
/// Trigger types:
/// - GPS: ถึงที่ทำงาน / ออกจากที่ทำงาน / ถึงบ้าน
/// - Time: 09:00 (เริ่มงาน), 12:00 (พักเที่ยง), 17:00 (เลิกงาน), 22:00 (ก่อนนอน)
/// - Pattern: วันที่ไม่มีบันทึกนานเกินไป

class MVPTriggerService {
  static final MVPTriggerService _instance = MVPTriggerService._internal();
  factory MVPTriggerService() => _instance;
  MVPTriggerService._internal();

  Timer? _timeCheckTimer;
  StreamSubscription<Position>? _locationSubscription;
  
  bool _isInitialized = false;
  
  // เก็บ state เพื่อป้องกัน trigger ซ้ำ
  final Set<String> _triggeredToday = {};
  DateTime? _lastTriggerDate;
  
  // Callback เมื่อมี Trigger
  void Function(TriggerEvent)? onTrigger;

  /// 🚀 เริ่มต้น service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // เริ่ม Time-based triggers
    _startTimeChecker();
    
    // เริ่ม Location-based triggers
    await _startLocationMonitor();
    
    _isInitialized = true;
    debugPrint('✅ MVP Trigger Service initialized');
  }

  /// ⏰ Time-based triggers
  void _startTimeChecker() {
    // เช็คทุก 1 นาที
    _timeCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkTimeTriggers();
    });
    
    // เช็คครั้งแรกทันที
    _checkTimeTriggers();
  }

  void _checkTimeTriggers() {
    final now = DateTime.now();
    
    // เคลียร์ state ถ้าเปลี่ยนวัน
    if (_lastTriggerDate == null || 
        !_isSameDay(_lastTriggerDate!, now)) {
      _triggeredToday.clear();
      _lastTriggerDate = now;
    }
    
    final hour = now.hour;
    final minute = now.minute;
    
    // Trigger ตามช่วงเวลา (เช็คแค่ช่วงนาทีแรกของชั่วโมง)
    if (minute > 5) return; // ไม่ trigger ถ้าเลยช่วงนาทีแรกไปแล้ว
    
    TriggerType? triggerType;
    String? message;
    String triggerKey = '';
    
    switch (hour) {
      case 9:
        triggerType = TriggerType.morningStart;
        message = 'สวัสดีตอนเช้า! พร้อมเริ่มวันใหม่ไหมคะ?';
        triggerKey = 'morning_${now.year}${now.month}${now.day}';
        break;
      case 12:
        triggerType = TriggerType.lunchTime;
        message = 'ถึงเวลาพักเที่ยงแล้ว วันนี้กินอะไรดีนะ?';
        triggerKey = 'lunch_${now.year}${now.month}${now.day}';
        break;
      case 17:
        triggerType = TriggerType.eveningEnd;
        message = 'เลิกงานแล้ว! วันนี้เป็นยังไงบ้างคะ?';
        triggerKey = 'evening_${now.year}${now.month}${now.day}';
        break;
      case 22:
        triggerType = TriggerType.bedtime;
        message = 'ก่อนนอนอย่าลืมสรุปวันนี้สักหน่อยนะคะ';
        triggerKey = 'bedtime_${now.year}${now.month}${now.day}';
        break;
    }
    
    // Deduplication: ตรวจสอบว่า trigger นี้ยิงไปแล้วหรือยัง
    if (triggerType != null && !_triggeredToday.contains(triggerKey)) {
      _triggeredToday.add(triggerKey);
      _fireTrigger(triggerType, message: message);
    }
  }

  /// 📅 ตรวจสอบว่าเป็นวันเดียวกัน
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 📍 Location-based triggers
  Future<void> _startLocationMonitor() async {
    // ขอ permission ก่อน
    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) {
      debugPrint('⚠️ Location permission denied, skipping location triggers');
      return;
    }
    
    // ตรวจจับการเปลี่ยนแปลงสถานที่
    final positionStream = LocationService.getPositionStream();
    if (positionStream == null) return;
    
    _locationSubscription = positionStream.listen(
      (Position position) async {
        await _checkLocationTriggers(position.latitude, position.longitude);
      },
      onError: (Object error) {
        debugPrint('⚠️ Location stream error: $error');
        // ไม่ throw error ออกไป ให้ทำงานต่อโดยไม่มี location trigger
      },
    );
  }

  Future<void> _checkLocationTriggers(double lat, double lng) async {
    // ดึงบันทึกที่มีพิกัดใกล้เคียง (รัศมี ~100 เมตร)
    final entries = await DatabaseHelper.instance.getAllEntries();
    if (entries.isEmpty) return;
    
    // หาบันทึกที่มีพิกัดใกล้เคียง
    final nearbyEntries = entries.where((e) {
      if (e.latitude == null || e.longitude == null) return false;
      return _calculateDistance(lat, lng, e.latitude!, e.longitude!) <= 0.1; // 0.1 km = 100m
    }).toList();
    
    if (nearbyEntries.isEmpty) return;
    
    // หาสถานที่ที่เคยมาบ่อยที่สุดในบริเวณนี้
    final locationCounts = <String, int>{};
    for (final entry in nearbyEntries) {
      if (entry.locationName != null) {
        locationCounts[entry.locationName!] = (locationCounts[entry.locationName!] ?? 0) + 1;
      }
    }
    
    if (locationCounts.isEmpty) return;
    
    // หาสถานที่ที่มี count สูงสุด
    final mostFrequentLocation = locationCounts.entries
      .reduce((a, b) => a.value > b.value ? a : b)
      .key;
    
    // ตรวจสอบว่าเคย trigger ที่นี่วันนี้หรือยัง
    final now = DateTime.now();
    final triggerKey = 'location_${mostFrequentLocation}_${now.year}${now.month}${now.day}';
    
    if (_triggeredToday.contains(triggerKey)) return;
    
    // ตรวจสอบว่าไม่ได้อยู่ที่นี่นานเกินไป (เว้นอย่างน้อย 2 ชั่วโมง)
    final recentVisit = nearbyEntries
      .where((e) => e.locationName == mostFrequentLocation)
      .map((e) => e.createdAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
    
    final timeSinceLastVisit = now.difference(recentVisit);
    if (timeSinceLastVisit.inHours < 2) return; // ยังอยู่ที่นี่หรือเพิ่งออกไป
    
    // Trigger
    _triggeredToday.add(triggerKey);
    _fireTrigger(
      TriggerType.locationRevisit,
      location: mostFrequentLocation,
      message: 'คุณมาที่ $mostFrequentLocation อีกแล้ว! ครั้งที่แล้วทำอะไรไว้นะ?',
    );
  }

  /// 📏 คำนวณระยะทางระหว่างพิกัด (Haversine formula) คืนค่าเป็น km
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371; // รัศมีโลก km
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final radLat1 = _toRadians(lat1);
    final radLat2 = _toRadians(lat2);
    
    final a = 
      sin(dLat / 2) * sin(dLat / 2) +
      cos(radLat1) * cos(radLat2) *
      sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degree) => degree * pi / 180;

  /// 🔥 ส่ง Trigger Event
  Future<void> _fireTrigger(
    TriggerType type, {
    String? message,
    String? location,
  }) async {
    // ดึง Context สำหรับ trigger นี้
    final context = await ContextRetriever().retrieveFullContext(
      currentTime: DateTime.now(),
      currentLocation: location,
    );
    
    final event = TriggerEvent(
      type: type,
      timestamp: DateTime.now(),
      suggestedMessage: message,
      context: context,
    );
    
    // เรียก callback
    onTrigger?.call(event);
    
    debugPrint('🔔 Trigger fired: ${type.name} - $message');
  }

  /// 🎯 สร้าง Prompt จาก Trigger
  String buildTriggerPrompt(TriggerEvent event) {
    final buffer = StringBuffer();
    
    // ใส่ context
    final contextString = ContextRetriever().buildContextString(event.context);
    buffer.writeln(contextString);
    
    // ใส่คำถาม/คำแนะนำ
    buffer.writeln('## สถานการณ์ปัจจุบัน');
    buffer.writeln(event.suggestedMessage ?? 'คุณอยู่ในบริบทใหม่');
    buffer.writeln();
    
    // คำสั่งให้ AI
    buffer.writeln('## คำขอ');
    buffer.writeln('ให้ตอบกลับแบบกระชับ เป็นกันเอง ใช้อิโมจิ 1-2 ตัว');
    buffer.writeln('ถ้ามีข้อมูลบันทึกเก่าที่เกี่ยวข้อง ให้อ้างอิงด้วย');
    
    return buffer.toString();
  }

  /// 🧹 Dispose
  void dispose() {
    _timeCheckTimer?.cancel();
    _locationSubscription?.cancel();
    _isInitialized = false;
  }
}

/// 🔔 Trigger Types
enum TriggerType {
  morningStart,    // 09:00 - เริ่มวัน
  lunchTime,       // 12:00 - พักเที่ยง
  eveningEnd,      // 17:00 - เลิกงาน
  bedtime,         // 22:00 - ก่อนนอน
  locationRevisit, // กลับมาที่เดิม
  noEntryReminder, // ไม่มีบันทึกนานเกินไป
}

/// 📦 Trigger Event
class TriggerEvent {
  final TriggerType type;
  final DateTime timestamp;
  final String? suggestedMessage;
  final ContextData context;

  TriggerEvent({
    required this.type,
    required this.timestamp,
    this.suggestedMessage,
    required this.context,
  });

  String get displayTitle {
    switch (type) {
      case TriggerType.morningStart:
        return 'สวัสดีตอนเช้า ☀️';
      case TriggerType.lunchTime:
        return 'พักเที่ยง 🍜';
      case TriggerType.eveningEnd:
        return 'เลิกงานแล้ว 🌆';
      case TriggerType.bedtime:
        return 'ก่อนนอน 🌙';
      case TriggerType.locationRevisit:
        return 'มาที่เดิมอีกแล้ว 📍';
      case TriggerType.noEntryReminder:
        return 'อย่าลืมบันทึก 📝';
    }
  }
}
