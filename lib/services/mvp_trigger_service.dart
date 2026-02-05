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
/// - Weekend: วันเสาร์-อาทิตย์ (โหมดพักผ่อน)
/// - Inactivity: ไม่มีบันทึกนานเกินไป
/// - Mood Swing: อารมณ์แย่ติดต่อกัน

class MVPTriggerService {
  static final MVPTriggerService _instance = MVPTriggerService._internal();
  factory MVPTriggerService() => _instance;
  MVPTriggerService._internal();

  Timer? _timeCheckTimer;
  StreamSubscription<Position>? _locationSubscription;
  
  bool _isInitialized = false;
  
  // เก็บ state เพื่อป้องกัน trigger ซ้ำ
  final Set<String> _triggeredToday = {};
  final Set<String> _triggeredThisWeek = {};
  DateTime? _lastTriggerDate;
  
  // เก็บประวัติการ trigger สถานที่
  final Map<String, DateTime> _lastLocationTrigger = {};
  
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

  void _checkTimeTriggers() async {
    final now = DateTime.now();
    
    // เคลียร์ state ถ้าเปลี่ยนวัน
    if (_lastTriggerDate == null || 
        !_isSameDay(_lastTriggerDate!, now)) {
      _triggeredToday.clear();
      _lastTriggerDate = now;
    }
    
    // เคลียร์ weekly state ถ้าเปลี่ยนสัปดาห์
    if (now.weekday == DateTime.monday && 
        _lastTriggerDate != null && 
        !_isSameDay(_lastTriggerDate!, now)) {
      _triggeredThisWeek.clear();
    }
    
    final hour = now.hour;
    final minute = now.minute;
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    
    // Trigger ตามช่วงเวลา (เช็คแค่ช่วงนาทีแรกของชั่วโมง)
    if (minute > 5) {
      // เช็ค Inactivity ตอน 20:00 (ไม่จำกัดนาทีแรก)
      if (hour == 20) {
        await _checkInactivityTrigger(now);
      }
      return;
    }
    
    // เช็ค Mood Swing ทุกชั่วโมง (แต่ไม่บ่อยเกินไป)
    await _checkMoodSwingTrigger(now);
    
    TriggerType? triggerType;
    String? message;
    String triggerKey = '';
    
    // 🏖️ Weekend Mode
    if (isWeekend) {
      switch (hour) {
        case 9:
          triggerType = TriggerType.weekendMorning;
          message = 'สุขสันต์วันหยุด! วันนี้มีแผนไปเที่ยวไหนไหมคะ? 🌿';
          triggerKey = 'weekend_morning_${now.year}${now.month}${now.day}';
          break;
        case 14:
          triggerType = TriggerType.weekendAfternoon;
          message = 'บ่ายๆ แบบนี้ มีอะไรสนุกๆ ทำไหมคะ? ☕';
          triggerKey = 'weekend_afternoon_${now.year}${now.month}${now.day}';
          break;
        case 20:
          triggerType = TriggerType.weekendEvening;
          message = 'วันหยุดวันนี้เป็นยังไงบ้างคะ? มาสรุปกันหน่อยไหม? 🌙';
          triggerKey = 'weekend_evening_${now.year}${now.month}${now.day}';
          break;
      }
    } else {
      // 💼 Weekday Mode
      switch (hour) {
        case 9:
          triggerType = TriggerType.morningStart;
          message = 'สวัสดีตอนเช้า! พร้อมเริ่มวันใหม่ไหมคะ? ☀️';
          triggerKey = 'morning_${now.year}${now.month}${now.day}';
          break;
        case 12:
          triggerType = TriggerType.lunchTime;
          message = 'ถึงเวลาพักเที่ยงแล้ว วันนี้กินอะไรดีนะ? 🍜';
          triggerKey = 'lunch_${now.year}${now.month}${now.day}';
          break;
        case 17:
          triggerType = TriggerType.eveningEnd;
          message = 'เลิกงานแล้ว! วันนี้เป็นยังไงบ้างคะ? 🌆';
          triggerKey = 'evening_${now.year}${now.month}${now.day}';
          break;
        case 22:
          triggerType = TriggerType.bedtime;
          message = 'ก่อนนอนอย่าลืมสรุปวันนี้สักหน่อยนะคะ 🌙';
          triggerKey = 'bedtime_${now.year}${now.month}${now.day}';
          break;
      }
    }
    
    // Deduplication: ตรวจสอบว่า trigger นี้ยิงไปแล้วหรือยัง
    if (triggerType != null && !_triggeredToday.contains(triggerKey)) {
      _triggeredToday.add(triggerKey);
      _fireTrigger(triggerType, message: message);
    }
  }

  /// 🕸️ Check Inactivity (ไม่มีบันทึกนาน)
  Future<void> _checkInactivityTrigger(DateTime now) async {
    final triggerKey = 'inactivity_${now.year}${now.month}${now.day}';
    if (_triggeredToday.contains(triggerKey)) return;
    
    try {
      final entries = await DatabaseHelper.instance.getAllEntries();
      if (entries.isEmpty) return;
      
      // หาบันทึกล่าสุด
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final lastEntry = entries.first;
      
      final daysDiff = now.difference(lastEntry.createdAt).inDays;
      
      if (daysDiff >= 3) {
        _triggeredToday.add(triggerKey);
        
        String message;
        if (daysDiff >= 7) {
          message = 'ไม่ได้เจอกันเป็นสัปดาห์แล้ว คิดถึงนะ... วันนี้มีอะไรเล่าให้ฟังไหม? 🥺';
        } else if (daysDiff >= 5) {
          message = 'หายไปหลายวันเลย เป็นห่วงนะคะ วันนี้เป็นยังไงบ้าง? 💭';
        } else {
          message = 'ไม่ได้เจอกันนานเลย คิดถึงนะ... วันนี้มีอะไรเล่าให้ฟังไหม? 📝';
        }
        
        _fireTrigger(
          TriggerType.inactivityReminder,
          message: message,
          extraData: {'daysSinceLastEntry': daysDiff},
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error checking inactivity: $e');
    }
  }

  /// 🎭 Check Mood Swing (อารมณ์แย่ติดต่อกัน)
  Future<void> _checkMoodSwingTrigger(DateTime now) async {
    final triggerKey = 'moodswing_${now.year}${now.month}${now.day}';
    if (_triggeredToday.contains(triggerKey)) return;
    
    try {
      final entries = await DatabaseHelper.instance.getAllEntries();
      if (entries.length < 3) return;
      
      // เรียงล่าสุดก่อน
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      // เช็ค 3 บันทึกล่าสุด
      final recent3 = entries.take(3).toList();
      final allHaveMood = recent3.every((e) => e.mood != null);
      
      if (!allHaveMood) return;
      
      final moods = recent3.map((e) => e.mood!).toList();
      final allLowMood = moods.every((m) => m <= 2);
      
      if (allLowMood) {
        _triggeredToday.add(triggerKey);
        
        _fireTrigger(
          TriggerType.moodSwingSupport,
          message: 'เห็นว่าช่วงนี้อารมณ์ไม่ค่อยดี... อยากให้รู้ว่าฮาคุอยู่ตรงนี้นะคะ 💜 อยากเล่าอะไรให้ฟังไหม?',
          extraData: {'moods': moods},
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error checking mood swing: $e');
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
      },
    );
  }

  Future<void> _checkLocationTriggers(double lat, double lng) async {
    // ดึงบันทึกที่มีพิกัดใกล้เคียง (รัศมี ~100 เมตร)
    final entries = await DatabaseHelper.instance.getAllEntries();
    
    // หาสถานที่ใกล้เคียง
    final nearbyEntries = entries.where((e) {
      if (e.latitude == null || e.longitude == null) return false;
      final distance = _calculateDistance(lat, lng, e.latitude!, e.longitude!);
      return distance < 100; // 100 เมตร
    }).toList();
    
    if (nearbyEntries.isEmpty) return;
    
    // หาชื่อสถานที่ที่พบบ่อยที่สุด
    final locationNames = nearbyEntries
        .where((e) => e.locationName != null)
        .map((e) => e.locationName!)
        .toList();
    
    if (locationNames.isEmpty) return;
    
    // นับความถี่
    final frequency = <String, int>{};
    for (final name in locationNames) {
      frequency[name] = (frequency[name] ?? 0) + 1;
    }
    
    final mostFrequent = frequency.entries
        .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    
    final locationName = mostFrequent.first.key;
    
    // 🏠 Smart Location: Ignore Home/Work (แจ้งเตือนแค่สัปดาห์ละครั้ง)
    final isCommonPlace = _isCommonPlace(locationName);
    final now = DateTime.now();
    final weekKey = '${locationName}_${now.year}_W${now.day ~/ 7}';
    
    if (isCommonPlace && _triggeredThisWeek.contains(weekKey)) {
      return; // ข้ามถ้าเคยแจ้งเตือนไปแล้ว this week
    }
    
    // เช็คว่าเคย trigger ที่นี่ไปแล้วยัง (ภายใน 2 ชั่วโมง)
    final lastTrigger = _lastLocationTrigger[locationName];
    if (lastTrigger != null) {
      final diff = DateTime.now().difference(lastTrigger);
      if (diff.inHours < 2) return;
    }
    
    // บันทึกเวลา trigger
    _lastLocationTrigger[locationName] = DateTime.now();
    if (isCommonPlace) {
      _triggeredThisWeek.add(weekKey);
    }
    
    // Fire trigger
    _fireTrigger(
      TriggerType.locationRevisit,
      message: 'คุณมาที่ $locationName อีกแล้ว! มีอะไรใหม่ๆ เกิดขึ้นที่นี่ไหมคะ? 📍',
      location: locationName,
    );
  }

  /// 🏠 ตรวจสอบว่าเป็นสถานที่ทั่วไป (บ้าน/ที่ทำงาน) หรือไม่
  bool _isCommonPlace(String locationName) {
    final commonNames = [
      'home', 'บ้าน', 'ที่บ้าน', 'my home',
      'work', 'office', 'ที่ทำงาน', 'ออฟฟิศ', 'office',
      'school', 'โรงเรียน', 'มหาลัย', 'university',
    ];
    
    final lowerName = locationName.toLowerCase();
    return commonNames.any((common) => lowerName.contains(common));
  }

  /// 📐 คำนวณระยะทาง (Haversine formula)
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000; // Earth's radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
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
    Map<String, dynamic>? extraData,
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
      extraData: extraData,
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
  morningStart,       // 09:00 วันธรรดา - เริ่มวัน
  lunchTime,          // 12:00 วันธรรดา - พักเที่ยง
  eveningEnd,         // 17:00 วันธรรดา - เลิกงาน
  bedtime,            // 22:00 - ก่อนนอน
  weekendMorning,     // 09:00 วันหยุด - สุขสันต์วันหยุด
  weekendAfternoon,   // 14:00 วันหยุด - บ่ายวันหยุด
  weekendEvening,     // 20:00 วันหยุด - เย็นวันหยุด
  locationRevisit,    // กลับมาที่เดิม
  inactivityReminder, // ไม่มีบันทึกนานเกินไป
  moodSwingSupport,   // อารมณ์แย่ติดต่อกัน
}

/// 📦 Trigger Event
class TriggerEvent {
  final TriggerType type;
  final DateTime timestamp;
  final String? suggestedMessage;
  final ContextData context;
  final Map<String, dynamic>? extraData;

  TriggerEvent({
    required this.type,
    required this.timestamp,
    this.suggestedMessage,
    required this.context,
    this.extraData,
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
      case TriggerType.weekendMorning:
        return 'สุขสันต์วันหยุด 🌿';
      case TriggerType.weekendAfternoon:
        return 'บ่ายวันหยุด ☕';
      case TriggerType.weekendEvening:
        return 'เย็นวันหยุด 🌅';
      case TriggerType.locationRevisit:
        return 'มาที่เดิมอีกแล้ว 📍';
      case TriggerType.inactivityReminder:
        return 'คิดถึงนะ 🥺';
      case TriggerType.moodSwingSupport:
        return 'อยู่ตรงนี้นะ 💜';
    }
  }

  /// รองรับ Quick Reply หรือไม่
  bool get supportsQuickReply => true;

  /// ข้อความเริ่มต้นสำหรับ Quick Reply
  List<String> get quickReplyOptions {
    switch (type) {
      case TriggerType.morningStart:
      case TriggerType.weekendMorning:
        return ['พร้อมเลย!', 'ยังง่วงอยู่ 😴', 'วันนี้มีแผนอะไรดี?'];
      case TriggerType.lunchTime:
        return ['กำลังหิวเลย', 'กินอะไรดีนะ?', 'ข้าวเที่ยงวันนี้ 🍱'];
      case TriggerType.eveningEnd:
      case TriggerType.weekendEvening:
        return ['วันนี้เหนื่อยมาก', 'สบายดีค่ะ', 'เล่าเรื่องวันนี้หน่อย'];
      case TriggerType.bedtime:
        return ['สรุปวันนี้หน่อย', 'วันนี้ดีมาก', 'นอนหลับฝันดีนะ'];
      case TriggerType.locationRevisit:
        return ['ที่นี่เหมือนเดิมเลย', 'มีอะไรใหม่ที่นี่', 'มาทำธุระค่ะ'];
      case TriggerType.inactivityReminder:
        return ['คิดถึงเหมือนกัน!', 'ช่วงนี้ยุ่งมาก', 'วันนี้มีเรื่องเล่าเยอะเลย'];
      case TriggerType.moodSwingSupport:
        return ['ขอบคุณนะ...', 'อยากเล่าให้ฟัง', 'ช่วงนี้เหนื่อยจริงๆ'];
      default:
        return ['ตอบกลับ...', '👍', '💬'];
    }
  }
}
