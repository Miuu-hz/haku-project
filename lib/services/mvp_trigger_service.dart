import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'context_retriever.dart';
import 'database_helper.dart';
import 'location_service.dart';
import 'scheduler_service.dart';
import 'workers/calendar_worker.dart';

/// ⚡ MVP Trigger Service - ตัวกระตุ้นอัตโนมัติตามบริบท
///
/// 🔋 Battery Optimization (Phase 2.1):
/// - Time check interval: 5 นาที (จาก 1 นาที)
/// - Location: ใช้ significant change เท่านั้น (ไม่ใช่ realtime)
/// - สามารถปิด location tracking ได้เพื่อประหยัดแบตเตอรี่
///
/// Trigger types:
/// - GPS: ถึงที่ทำงาน / ออกจากที่ทำงาน / ถึงบ้าน
/// - Time: 09:00 (เริ่มงาน), 12:00 (พักเที่ยง), 17:00 (เลิกงาน), 22:00 (ก่อนนอน)
/// - Pattern: วันที่ไม่มีบันทึกนานเกินไป

class MVPTriggerService {
  static final MVPTriggerService _instance = MVPTriggerService._internal();
  factory MVPTriggerService() => _instance;
  MVPTriggerService._internal();

  /// 🔋 Battery settings
  static const int timeCheckIntervalMinutes = 5; // เพิ่มจาก 1 นาที เป็น 5 นาที
  static const int locationDistanceFilter = 200; // เมตร - ต้องเดิน 200m ถึงจะ update

  Timer? _timeCheckTimer;
  StreamSubscription<Position>? _locationSubscription;

  bool _isInitialized = false;
  bool _locationTrackingEnabled = true; // สามารถปิดได้เพื่อประหยัดแบต

  // เก็บ state เพื่อป้องกัน trigger ซ้ำ
  final Set<String> _triggeredToday = {};
  DateTime? _lastTriggerDate;

  // Callback เมื่อมี Trigger (legacy — ใช้ triggerStream แทนถ้าต้องการ multi-subscriber)
  void Function(TriggerEvent)? onTrigger;

  // Broadcast stream — subscribe ได้จากหลาย widget พร้อมกัน
  final _triggerController = StreamController<TriggerEvent>.broadcast();
  Stream<TriggerEvent> get triggerStream => _triggerController.stream;

  /// สถานะการติดตามตำแหน่ง
  bool get isLocationTrackingEnabled => _locationTrackingEnabled;

  /// 🚀 เริ่มต้น service
  ///
  /// [enableLocationTracking] - ถ้า false จะไม่เปิด GPS tracking (ประหยัดแบต)
  Future<void> initialize({bool enableLocationTracking = true}) async {
    if (_isInitialized) return;

    _locationTrackingEnabled = enableLocationTracking;

    // เริ่ม Time-based triggers (เช็คทุก 5 นาที แทน 1 นาที)
    _startTimeChecker();

    // เริ่ม Location-based triggers (ถ้าเปิดใช้งาน)
    if (_locationTrackingEnabled) {
      await _startLocationMonitor();
    } else {
      debugPrint('📍 Location tracking disabled (battery saver mode)');
    }

    _isInitialized = true;
    debugPrint('✅ MVP Trigger Service initialized (battery optimized)');
    debugPrint(
        '   - Time check: every $timeCheckIntervalMinutes minutes');
    debugPrint('   - Location: ${_locationTrackingEnabled ? "enabled (${locationDistanceFilter}m filter)" : "disabled"}');
  }

  /// 🔋 เปิด/ปิด Location Tracking
  Future<void> setLocationTracking(bool enabled) async {
    if (_locationTrackingEnabled == enabled) return;

    _locationTrackingEnabled = enabled;
    if (enabled) {
      await _startLocationMonitor();
      debugPrint('📍 Location tracking enabled');
    } else {
      _locationSubscription?.cancel();
      _locationSubscription = null;
      debugPrint('📍 Location tracking disabled (battery saver)');
    }
  }

  /// ⏰ Time-based triggers (Battery Optimized)
  void _startTimeChecker() {
    // 🔋 เช็คทุก 5 นาที (ประหยัดแบตกว่า 1 นาที)
    _timeCheckTimer =
        Timer.periodic(const Duration(minutes: timeCheckIntervalMinutes), (_) {
      _checkTimeTriggers();
    });

    // เช็คครั้งแรกทันที
    _checkTimeTriggers();
  }

  void _checkTimeTriggers() {
    final now = DateTime.now();

    // เคลียร์ state ถ้าเปลี่ยนวัน
    if (_lastTriggerDate == null || !_isSameDay(_lastTriggerDate!, now)) {
      _triggeredToday.clear();
      _lastTriggerDate = now;
    }

    final hour = now.hour;
    final minute = now.minute;

    // 🔋 Battery Optimized: เช็คช่วงเวลาที่กว้างขึ้น (0-9 นาที แทน 0-5)
    // เพราะ timer interval เป็น 5 นาที
    if (minute > 9) return;

    TriggerType? triggerType;
    String triggerKey = '';

    switch (hour) {
      case 9:
        triggerType = TriggerType.morningStart;
        triggerKey = 'morning_${now.year}${now.month}${now.day}';
        break;
      case 12:
        triggerType = TriggerType.lunchTime;
        triggerKey = 'lunch_${now.year}${now.month}${now.day}';
        break;
      case 17:
        triggerType = TriggerType.eveningEnd;
        triggerKey = 'evening_${now.year}${now.month}${now.day}';
        break;
      case 20:
        triggerType = TriggerType.eveningSummary;
        triggerKey = 'evening_summary_${now.year}${now.month}${now.day}';
        break;
      case 22:
        triggerType = TriggerType.bedtime;
        triggerKey = 'bedtime_${now.year}${now.month}${now.day}';
        break;
    }

    // Deduplication: ตรวจสอบว่า trigger นี้ยิงไปแล้วหรือยัง
    if (triggerType != null && !_triggeredToday.contains(triggerKey)) {
      _triggeredToday.add(triggerKey);
      _fireTriggerAsync(triggerType, now).catchError((Object e) {
        debugPrint('⚠️ Trigger async error (non-fatal): $e');
      });
    }
  }

  /// 🔥 Fire trigger พร้อม build message async (ดึง calendar events)
  Future<void> _fireTriggerAsync(TriggerType type, DateTime now) async {
    String message;
    switch (type) {
      case TriggerType.morningStart:
        message = await _buildMorningMessage(now);
        break;
      case TriggerType.eveningSummary:
        message = await _buildEveningSummaryMessage(now);
        break;
      case TriggerType.lunchTime:
        message = 'ถึงเวลาพักเที่ยงแล้ว วันนี้กินอะไรดีนะ?';
        break;
      case TriggerType.eveningEnd:
        message = 'เลิกงานแล้ว! วันนี้เป็นยังไงบ้างคะ?';
        break;
      case TriggerType.bedtime:
        // ⏰ Smart Sleep-Prep: ตั้งปลุกอัตโนมัติจาก event พรุ่งนี้
        final alarmInfo = await SchedulerService().calculateAlarmFromTomorrow();
        if (alarmInfo != null) {
          final h = alarmInfo['hour']!;
          final m = alarmInfo['minute']!;
          final timeStr = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
          await SchedulerService().setAlarm(hour: h, minute: m, label: 'Haku: เวลาตื่นแล้ว!');
          message = 'พรุ่งนี้มีนัด ฉันตั้งปลุก $timeStr ไว้ให้แล้วนะ รีบนอนล่ะ! 🌙';
        } else {
          message = 'พรุ่งนี้ไม่มีนัด ก่อนนอนอย่าลืมสรุปวันนี้สักหน่อยนะคะ 🌙';
        }
        break;
      default:
        message = '';
    }
    await _fireTrigger(type, message: message);
  }

  /// 🌅 สร้าง morning message พร้อม agenda วันนี้
  Future<String> _buildMorningMessage(DateTime now) async {
    try {
      final worker = CalendarWorker();
      await worker.initialize();
      final events = worker.getEventsForDate(now);
      if (events.isEmpty) {
        return 'สวัสดีตอนเช้า! วันนี้ไม่มีนัดหมาย พร้อมเริ่มวันใหม่ไหมคะ?';
      }
      final list = events.take(3).map((e) {
        final timeStr = e.time != null
            ? ' ${e.time!.hour.toString().padLeft(2, '0')}:${e.time!.minute.toString().padLeft(2, '0')}'
            : '';
        return '${e.title}$timeStr';
      }).join(', ');
      final more = events.length > 3 ? ' (+${events.length - 3})' : '';
      return 'สวัสดีตอนเช้า! วันนี้มี ${events.length} นัด: $list$more';
    } catch (_) {
      return 'สวัสดีตอนเช้า! พร้อมเริ่มวันใหม่ไหมคะ?';
    }
  }

  /// 🌆 สร้าง evening summary message
  Future<String> _buildEveningSummaryMessage(DateTime now) async {
    try {
      final worker = CalendarWorker();
      await worker.initialize();
      final events = worker.getEventsForDate(now);
      if (events.isEmpty) {
        return 'เย็นแล้ว! วันนี้ไม่มีนัดหมาย พักผ่อนให้เต็มที่นะคะ';
      }
      final list = events.take(3).map((e) => e.title).join(', ');
      return 'เย็นแล้ว! วันนี้มีนัด ${events.length} รายการ: $list วันนี้เป็นยังไงบ้างคะ?';
    } catch (_) {
      return 'เย็นแล้ว! วันนี้เป็นยังไงบ้างคะ? อย่าลืมพักผ่อนด้วยนะ';
    }
  }

  /// 📅 ตรวจสอบว่าเป็นวันเดียวกัน
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 📍 Location-based triggers (Battery Optimized)
  ///
  /// 🔋 ใช้ distanceFilter 200m และ medium accuracy เพื่อประหยัดแบต
  Future<void> _startLocationMonitor() async {
    // ยกเลิก subscription เดิมก่อน (ถ้ามี)
    await _locationSubscription?.cancel();
    _locationSubscription = null;

    // ขอ permission ก่อน
    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) {
      debugPrint('⚠️ Location permission denied, skipping location triggers');
      _locationTrackingEnabled = false;
      return;
    }

    // ตรวจจับการเปลี่ยนแปลงสถานที่ (battery optimized)
    final positionStream = LocationService.getPositionStream();
    if (positionStream == null) {
      debugPrint('⚠️ Position stream unavailable');
      return;
    }

    _locationSubscription = positionStream.listen(
      (Position position) async {
        await _checkLocationTriggers(position.latitude, position.longitude);
      },
      onError: (Object error) {
        debugPrint('⚠️ Location stream error: $error');
        // ไม่ throw error ออกไป ให้ทำงานต่อโดยไม่มี location trigger
      },
    );

    debugPrint('📍 Location monitoring started (200m distance filter)');
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
    // ตรวจสอบ flag ก่อนยิง location-based triggers
    if (type == TriggerType.locationRevisit || type == TriggerType.placeFeedback) {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('proactive_location_enabled') ?? true)) return;
    }

    // ดึง Context สำหรับ trigger นี้
    final context = await ContextRetriever().retrieveFullContext(
      currentTime: DateTime.now(),
      currentLocation: location,
    );
    
    // Quick reply options based on trigger type
    final quickReplyOptions = _getQuickReplyOptions(type);
    
    final event = TriggerEvent(
      type: type,
      timestamp: DateTime.now(),
      suggestedMessage: message,
      context: context,
      quickReplyOptions: quickReplyOptions,
    );
    
    // เรียก callback (legacy) + emit ออก stream
    onTrigger?.call(event);
    if (!_triggerController.isClosed) _triggerController.add(event);

    debugPrint('🔔 Trigger fired: ${type.name} - $message');
  }

  /// 💬 ดึง Quick Reply Options ตาม Trigger Type
  List<String> _getQuickReplyOptions(TriggerType type) {
    switch (type) {
      case TriggerType.morningStart:
        return ['พร้อมมาก!', 'ยังง่วง', 'วันนี้มีอะไร?'];
      case TriggerType.lunchTime:
        return ['กินแล้ว', 'ยังไม่กิน', 'ไปกินข้าวข้างนอก'];
      case TriggerType.eveningEnd:
        return ['เหนื่อยมาก', 'สบายดี', 'เลิกงานแล้ว!'];
      case TriggerType.eveningSummary:
        return ['วันดีมาก', 'เหนื่อยหน่อย', 'สรุปวันนี้'];
      case TriggerType.bedtime:
        return ['วันนี้ดีมาก', 'เหนื่อย', 'พรุ่งนี้สู้ๆ'];
      case TriggerType.locationRevisit:
        return ['มาที่เดิม', 'มีเรื่องใหม่', 'ยังไม่ได้บันทึก'];
      case TriggerType.noEntryReminder:
        return ['บันทึกเลย', 'ไม่มีไร', 'เดี๋ยวบันทึก'];
      case TriggerType.placeFeedback:
        return ['ชอบมาก', 'โอเค', 'ไม่ค่อยชอบ'];
    }
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
    _timeCheckTimer = null;
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _isInitialized = false;
    _triggeredToday.clear();
    if (!_triggerController.isClosed) _triggerController.close();
    debugPrint('🧹 MVP Trigger Service disposed');
  }

  /// ⏸️ Pause service (ประหยัดแบตเตอรี่)
  void pause() {
    _timeCheckTimer?.cancel();
    _timeCheckTimer = null;
    _locationSubscription?.cancel();
    _locationSubscription = null;
    debugPrint('⏸️ MVP Trigger Service paused');
  }

  /// ▶️ Resume service
  Future<void> resume() async {
    if (!_isInitialized) return;
    _startTimeChecker();
    if (_locationTrackingEnabled) {
      await _startLocationMonitor();
    }
    debugPrint('▶️ MVP Trigger Service resumed');
  }
}

/// 🔔 Trigger Types
enum TriggerType {
  morningStart,    // 09:00 - เริ่มวัน (พร้อม agenda)
  lunchTime,       // 12:00 - พักเที่ยง
  eveningEnd,      // 17:00 - เลิกงาน
  eveningSummary,  // 20:00 - สรุปวัน (2.12)
  bedtime,         // 22:00 - ก่อนนอน
  locationRevisit, // กลับมาที่เดิม
  noEntryReminder, // ไม่มีบันทึกนานเกินไป
  placeFeedback,   // ถามความรู้สึกหลังออกจากสถานที่
}

/// 📦 Trigger Event
class TriggerEvent {
  final TriggerType type;
  final DateTime timestamp;
  final String? suggestedMessage;
  final ContextData context;
  final List<String> quickReplyOptions;
  // payload เพิ่มเติม เช่น feedbackRequestId สำหรับ placeFeedback
  final Map<String, dynamic>? payloadJson;

  TriggerEvent({
    required this.type,
    required this.timestamp,
    this.suggestedMessage,
    required this.context,
    this.quickReplyOptions = const [],
    this.payloadJson,
  });

  String get displayTitle {
    switch (type) {
      case TriggerType.morningStart:
        return 'สวัสดีตอนเช้า ☀️';
      case TriggerType.lunchTime:
        return 'พักเที่ยง 🍜';
      case TriggerType.eveningEnd:
        return 'เลิกงานแล้ว 🌆';
      case TriggerType.eveningSummary:
        return 'สรุปวันนี้ 📋';
      case TriggerType.bedtime:
        return 'ก่อนนอน 🌙';
      case TriggerType.locationRevisit:
        return 'มาที่เดิมอีกแล้ว 📍';
      case TriggerType.noEntryReminder:
        return 'อย่าลืมบันทึก 📝';
      case TriggerType.placeFeedback:
        return 'รีวิวสถานที่ 📍';
    }
  }
}
