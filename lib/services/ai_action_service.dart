import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/objective.dart';
import 'google_auth_service.dart';
import 'objective_service.dart';
import 'place_service.dart';
import 'preset_service.dart';
import 'scheduler_service.dart';
import 'web_search_service.dart';

/// 🤖 AI Action Service - ให้ AI สั่งงานแอพได้
///
/// AI สามารถส่ง actions ในรูปแบบ:
/// - [ACTION:SCHEDULE] title=..., date=..., time=..., location=...
/// - [ACTION:PRESET] switch=...
/// - [ACTION:REMINDER] message=..., minutes=...
/// - [ACTION:OBJECTIVE] title=..., due=...
/// - [ACTION:SEARCH_PLACE] query=..., type=...
/// - [ACTION:SAVE_PLACE] name=..., lat=..., lng=...
/// - [ACTION:WEB_SEARCH] query=...
/// - [ACTION:SYNC_CALENDAR] eventId=...
/// - [ACTION:NAVIGATE] lat=..., lng=..., name=...
/// - [ACTION:ASK_LOCATION] message=...
///
/// Parser จะดักจับ actions เหล่านี้และเรียก service ที่เหมาะสม
/// ผู้ใช้สามารถ approve/reject action ก่อนทำงานได้

class AIActionService {
  static final AIActionService _instance = AIActionService._internal();
  factory AIActionService() => _instance;
  AIActionService._internal();

  // Callback เมื่อมี action ที่ต้องการ approval
  void Function(AIAction action)? onActionPending;

  // Callback เมื่อ action ถูก execute
  void Function(AIAction action, bool success)? onActionExecuted;

  // Pending actions รอ approval
  final List<AIAction> _pendingActions = [];
  List<AIAction> get pendingActions => List.unmodifiable(_pendingActions);

  /// 🔍 Parse AI response และดึง actions ออกมา
  ///
  /// Returns: (cleanResponse, actions)
  /// - cleanResponse: ข้อความที่ตัด action tags ออกแล้ว
  /// - actions: list ของ actions ที่ต้องทำ
  ParseResult parseResponse(String response) {
    final actions = <AIAction>[];
    String cleanResponse = response;

    // Pattern: [ACTION:TYPE] key=value, key=value
    final actionPattern = RegExp(
      r'\[ACTION:(\w+)\]\s*([^\[\]]+?)(?=\[ACTION:|$)',
      multiLine: true,
      dotAll: true,
    );

    final matches = actionPattern.allMatches(response);

    for (final match in matches) {
      final actionType = match.group(1)?.toUpperCase();
      final paramsStr = match.group(2)?.trim() ?? '';

      if (actionType == null) continue;

      // Parse parameters
      final params = _parseParams(paramsStr);

      // สร้าง action
      final action = AIAction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: AIActionType.values.firstWhere(
          (t) => t.name.toUpperCase() == actionType,
          orElse: () => AIActionType.unknown,
        ),
        params: params,
        rawText: match.group(0) ?? '',
        createdAt: DateTime.now(),
      );

      if (action.type != AIActionType.unknown) {
        actions.add(action);
      }

      // ลบ action tag จาก response
      cleanResponse = cleanResponse.replaceAll(match.group(0) ?? '', '');
    }

    // Cleanup
    cleanResponse = cleanResponse.trim();
    cleanResponse = cleanResponse.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return ParseResult(
      cleanResponse: cleanResponse,
      actions: actions,
    );
  }

  /// 📝 Parse parameters จาก string
  Map<String, String> _parseParams(String paramsStr) {
    final params = <String, String>{};

    // Pattern: key=value หรือ key="value with spaces"
    final paramPattern = RegExp(r'(\w+)\s*=\s*(?:"([^"]+)"|([^,\s]+))');
    final matches = paramPattern.allMatches(paramsStr);

    for (final match in matches) {
      final key = match.group(1);
      final value = match.group(2) ?? match.group(3);
      if (key != null && value != null) {
        params[key] = value;
      }
    }

    return params;
  }

  /// ✅ Execute action (auto-approve)
  Future<ActionExecuteResult> executeAction(AIAction action) async {
    try {
      switch (action.type) {
        case AIActionType.schedule:
          final success = await _executeSchedule(action);
          return ActionExecuteResult(success: success);

        case AIActionType.preset:
          final success = await _executePreset(action);
          return ActionExecuteResult(success: success);

        case AIActionType.reminder:
          final success = await _executeReminder(action);
          return ActionExecuteResult(success: success);

        case AIActionType.objective:
          final success = await _executeObjective(action);
          return ActionExecuteResult(success: success);

        case AIActionType.searchPlace:
          return await _executeSearchPlace(action);

        case AIActionType.savePlace:
          final success = await _executeSavePlace(action);
          return ActionExecuteResult(success: success);

        case AIActionType.webSearch:
          return await _executeWebSearch(action);

        case AIActionType.syncCalendar:
          final success = await _executeSyncCalendar(action);
          return ActionExecuteResult(success: success);

        case AIActionType.navigate:
          final success = await _executeNavigate(action);
          return ActionExecuteResult(success: success);

        case AIActionType.askLocation:
          return ActionExecuteResult(
            success: true,
            requiresUserInput: true,
            inputType: 'location',
            message: action.params['message'] ?? 'เลือกสถานที่',
          );

        case AIActionType.unknown:
          return ActionExecuteResult(success: false);
      }
    } catch (e) {
      debugPrint('❌ Execute action failed: $e');
      return ActionExecuteResult(success: false, error: e.toString());
    }
  }

  /// ✅ Execute action (legacy - returns bool)
  Future<bool> executeActionBool(AIAction action) async {
    final result = await executeAction(action);
    return result.success;
  }

  /// ⏳ Add action to pending (require approval)
  void addPendingAction(AIAction action) {
    _pendingActions.add(action);
    onActionPending?.call(action);
  }

  /// ✅ Approve and execute pending action
  Future<ActionExecuteResult> approveAction(String actionId) async {
    final action = _pendingActions.firstWhere(
      (a) => a.id == actionId,
      orElse: () => throw ArgumentError('Action not found: $actionId'),
    );

    _pendingActions.removeWhere((a) => a.id == actionId);

    final result = await executeAction(action);
    onActionExecuted?.call(action, result.success);
    return result;
  }

  /// ❌ Reject pending action
  void rejectAction(String actionId) {
    _pendingActions.removeWhere((a) => a.id == actionId);
  }

  /// 🗑️ Clear all pending actions
  void clearPendingActions() {
    _pendingActions.clear();
  }

  // ============================================================================
  // Action Executors
  // ============================================================================

  /// 📅 Execute SCHEDULE action
  Future<bool> _executeSchedule(AIAction action) async {
    final title = action.params['title'] ?? 'กิจกรรม';
    final dateStr = action.params['date'];
    final time = action.params['time'];
    final location = action.params['location'];
    final durationStr = action.params['duration'];

    DateTime? date;
    if (dateStr != null) {
      // รองรับ "tomorrow", "วันนี้", "พรุ่งนี้" และ ISO format
      final now = DateTime.now();
      if (dateStr == 'tomorrow' || dateStr == 'พรุ่งนี้') {
        date = DateTime(now.year, now.month, now.day + 1);
      } else if (dateStr == 'today' || dateStr == 'วันนี้') {
        date = DateTime(now.year, now.month, now.day);
      } else {
        try {
          date = DateTime.parse(dateStr);
        } catch (_) {}
      }
    }

    final duration = int.tryParse(durationStr ?? '60') ?? 60;

    final event = EventInfo(
      title: title,
      date: date,
      time: time,
      location: location,
      durationMinutes: duration,
      originalText: action.rawText,
    );

    final success = await SchedulerService().createCalendarEvent(event);

    if (success) {
      debugPrint('✅ Created schedule: $title');

      // ตั้ง reminder ด้วย
      await SchedulerService().scheduleReminder(event);
    }

    return success;
  }

  /// 🎭 Execute PRESET action
  Future<bool> _executePreset(AIAction action) async {
    final presetId = action.params['switch'] ?? action.params['id'];
    if (presetId == null) return false;

    return PresetService().aiSwitchPreset(presetId);
  }

  /// 🔔 Execute REMINDER action
  Future<bool> _executeReminder(AIAction action) async {
    final message = action.params['message'] ?? 'แจ้งเตือน';
    final minutesStr = action.params['minutes'] ?? '15';
    final minutes = int.tryParse(minutesStr) ?? 15;

    final event = EventInfo(
      title: message,
      durationMinutes: minutes,
      originalText: action.rawText,
    );

    return SchedulerService().scheduleReminder(event, minutesBefore: minutes);
  }

  /// 🎯 Execute OBJECTIVE action
  Future<bool> _executeObjective(AIAction action) async {
    final title = action.params['title'] ?? 'เป้าหมาย';
    final dueStr = action.params['due'];
    final time = action.params['time'];
    final location = action.params['location'];

    DateTime? dueDate;
    if (dueStr != null) {
      final now = DateTime.now();
      if (dueStr == 'tomorrow' || dueStr == 'พรุ่งนี้') {
        dueDate = DateTime(now.year, now.month, now.day + 1);
      } else if (dueStr == 'today' || dueStr == 'วันนี้') {
        dueDate = DateTime(now.year, now.month, now.day);
      } else {
        try {
          dueDate = DateTime.parse(dueStr);
        } catch (_) {}
      }
    }

    final objective = Objective(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      dueDate: dueDate,
      dueTime: time,
      location: location,
      originalText: action.rawText,
      isAIGenerated: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await ObjectiveService().addObjective(objective);
    debugPrint('✅ Created objective: $title');
    return true;
  }

  /// 🔍 Execute SEARCH_PLACE action
  Future<ActionExecuteResult> _executeSearchPlace(AIAction action) async {
    final query = action.params['query'] ?? '';
    final type = action.params['type']; // restaurant, cafe, etc.

    if (query.isEmpty) {
      return ActionExecuteResult(
        success: false,
        error: 'No search query provided',
      );
    }

    final placeService = PlaceService();
    await placeService.initialize();

    // Get current position for nearby search
    final position = await placeService.getCurrentPosition();

    final results = await placeService.searchPlaces(
      query,
      nearLat: position?.latitude,
      nearLng: position?.longitude,
      type: type,
    );

    if (results.isEmpty) {
      return ActionExecuteResult(
        success: true,
        data: 'ไม่พบสถานที่สำหรับ "$query"',
      );
    }

    // Format results for AI
    final buffer = StringBuffer();
    buffer.writeln('🔍 พบ ${results.length} สถานที่:');
    for (int i = 0; i < results.length && i < 5; i++) {
      final place = results[i];
      buffer.write('${i + 1}. ${place.typeIcon} ${place.name}');
      if (place.rating != null) {
        buffer.write(' - ${place.displayRating}');
      }
      if (place.address != null) {
        buffer.write('\n   📍 ${place.address}');
      }
      buffer.writeln();
    }

    debugPrint('✅ Found ${results.length} places for: $query');

    return ActionExecuteResult(
      success: true,
      data: buffer.toString(),
      rawData: results,
    );
  }

  /// 💾 Execute SAVE_PLACE action
  Future<bool> _executeSavePlace(AIAction action) async {
    final name = action.params['name'];
    final latStr = action.params['lat'];
    final lngStr = action.params['lng'];
    final category = action.params['category'];

    if (name == null || latStr == null || lngStr == null) {
      debugPrint('⚠️ SAVE_PLACE missing required params');
      return false;
    }

    final lat = double.tryParse(latStr);
    final lng = double.tryParse(lngStr);

    if (lat == null || lng == null) {
      return false;
    }

    final placeService = PlaceService();
    await placeService.initialize();

    await placeService.savePlace(
      name: name,
      lat: lat,
      lng: lng,
      category: category,
    );

    debugPrint('✅ Saved place: $name');
    return true;
  }

  /// 🌐 Execute WEB_SEARCH action
  Future<ActionExecuteResult> _executeWebSearch(AIAction action) async {
    final query = action.params['query'] ?? '';

    if (query.isEmpty) {
      return ActionExecuteResult(
        success: false,
        error: 'No search query provided',
      );
    }

    final webService = WebSearchService();
    await webService.initialize();

    final resultText = await webService.searchForAI(query);

    debugPrint('✅ Web search completed: $query');

    return ActionExecuteResult(
      success: true,
      data: resultText,
    );
  }

  /// 📅 Execute SYNC_CALENDAR action
  Future<bool> _executeSyncCalendar(AIAction action) async {
    final title = action.params['title'] ?? '';
    final dateStr = action.params['date'];
    final timeStr = action.params['time'];
    final location = action.params['location'];
    final description = action.params['description'];

    final googleAuth = GoogleAuthService();
    await googleAuth.initialize();

    if (!googleAuth.isSignedIn) {
      debugPrint('⚠️ Not signed in to Google');
      return false;
    }

    // Parse date/time
    DateTime startTime = DateTime.now().add(const Duration(hours: 1));

    if (dateStr != null) {
      final now = DateTime.now();
      if (dateStr == 'tomorrow' || dateStr == 'พรุ่งนี้') {
        startTime = DateTime(now.year, now.month, now.day + 1, 9, 0);
      } else if (dateStr == 'today' || dateStr == 'วันนี้') {
        startTime = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
      } else {
        try {
          startTime = DateTime.parse(dateStr);
        } catch (_) {}
      }
    }

    if (timeStr != null) {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]) ?? startTime.hour;
        final minute = int.tryParse(parts[1]) ?? 0;
        startTime = DateTime(
          startTime.year,
          startTime.month,
          startTime.day,
          hour,
          minute,
        );
      }
    }

    final result = await googleAuth.createCalendarEvent(
      title: title,
      startTime: startTime,
      location: location,
      description: description,
    );

    debugPrint(result.success
        ? '✅ Calendar event created: $title'
        : '❌ Calendar sync failed: ${result.error}');

    return result.success;
  }

  /// 🧭 Execute NAVIGATE action
  Future<bool> _executeNavigate(AIAction action) async {
    final latStr = action.params['lat'];
    final lngStr = action.params['lng'];
    final name = action.params['name'];

    if (latStr == null || lngStr == null) {
      debugPrint('⚠️ NAVIGATE missing lat/lng');
      return false;
    }

    final lat = double.tryParse(latStr);
    final lng = double.tryParse(lngStr);

    if (lat == null || lng == null) {
      return false;
    }

    // Open in Google Maps
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng${name != null ? '&query_place_name=$name' : ''}',
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        debugPrint('✅ Opened navigation to: $name ($lat, $lng)');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Navigate error: $e');
    }

    return false;
  }
}

/// 🎬 AI Action Model
class AIAction {
  final String id;
  final AIActionType type;
  final Map<String, String> params;
  final String rawText;
  final DateTime createdAt;

  const AIAction({
    required this.id,
    required this.type,
    required this.params,
    required this.rawText,
    required this.createdAt,
  });

  /// แสดงชื่อ action
  String get displayName {
    switch (type) {
      case AIActionType.schedule:
        return '📅 สร้างนัดหมาย: ${params['title'] ?? 'กิจกรรม'}';
      case AIActionType.preset:
        return '🎭 เปลี่ยนโหมด: ${params['switch'] ?? params['id']}';
      case AIActionType.reminder:
        return '🔔 ตั้งเตือน: ${params['message'] ?? 'แจ้งเตือน'}';
      case AIActionType.objective:
        return '🎯 สร้างเป้าหมาย: ${params['title'] ?? 'เป้าหมาย'}';
      case AIActionType.searchPlace:
        return '🔍 ค้นหาสถานที่: ${params['query'] ?? ''}';
      case AIActionType.savePlace:
        return '💾 บันทึกสถานที่: ${params['name'] ?? ''}';
      case AIActionType.webSearch:
        return '🌐 ค้นหาเว็บ: ${params['query'] ?? ''}';
      case AIActionType.syncCalendar:
        return '📆 Sync Calendar: ${params['title'] ?? ''}';
      case AIActionType.navigate:
        return '🧭 นำทาง: ${params['name'] ?? 'ไปยังตำแหน่ง'}';
      case AIActionType.askLocation:
        return '📍 ถามสถานที่: ${params['message'] ?? ''}';
      case AIActionType.unknown:
        return '❓ Unknown action';
    }
  }

  /// รายละเอียด
  String get description {
    final parts = <String>[];

    if (params.containsKey('date')) {
      parts.add('วันที่: ${params['date']}');
    }
    if (params.containsKey('time')) {
      parts.add('เวลา: ${params['time']}');
    }
    if (params.containsKey('location')) {
      parts.add('สถานที่: ${params['location']}');
    }

    return parts.isEmpty ? rawText : parts.join(', ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'params': params,
        'rawText': rawText,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AIAction.fromJson(Map<String, dynamic> json) => AIAction(
        id: json['id'] as String,
        type: AIActionType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => AIActionType.unknown,
        ),
        params: Map<String, String>.from(json['params'] as Map),
        rawText: json['rawText'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

enum AIActionType {
  schedule, // สร้างนัดหมาย
  preset, // เปลี่ยน preset
  reminder, // ตั้งเตือน
  objective, // สร้าง objective
  searchPlace, // ค้นหาสถานที่
  savePlace, // บันทึกสถานที่
  webSearch, // ค้นหาเว็บ
  syncCalendar, // Sync กับ Google Calendar
  navigate, // เปิดแผนที่นำทาง
  askLocation, // ถามให้ผู้ใช้เลือกสถานที่
  unknown, // ไม่รู้จัก
}

/// 📦 Parse Result
class ParseResult {
  final String cleanResponse;
  final List<AIAction> actions;

  const ParseResult({
    required this.cleanResponse,
    required this.actions,
  });

  bool get hasActions => actions.isNotEmpty;
}

/// ✅ Action Execute Result
class ActionExecuteResult {
  final bool success;
  final String? data; // ผลลัพธ์เป็น text (เช่น ผลค้นหา)
  final dynamic rawData; // ผลลัพธ์ดิบ (เช่น List<PlaceResult>)
  final String? error;
  final bool requiresUserInput;
  final String? inputType; // 'location', 'confirmation', etc.
  final String? message;

  const ActionExecuteResult({
    required this.success,
    this.data,
    this.rawData,
    this.error,
    this.requiresUserInput = false,
    this.inputType,
    this.message,
  });

  /// มีข้อมูลที่ต้องส่งกลับให้ AI
  bool get hasDataForAI => data != null && data!.isNotEmpty;
}
