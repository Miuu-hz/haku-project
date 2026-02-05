import 'package:flutter/foundation.dart';

import '../models/objective.dart';
import 'objective_service.dart';
import 'preset_service.dart';
import 'scheduler_service.dart';

/// 🤖 AI Action Service - ให้ AI สั่งงานแอพได้
///
/// AI สามารถส่ง actions ในรูปแบบ:
/// - [ACTION:SCHEDULE] title=..., date=..., time=...
/// - [ACTION:PRESET] switch=...
/// - [ACTION:REMINDER] message=..., minutes=...
/// - [ACTION:OBJECTIVE] title=..., due=...
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
  Future<bool> executeAction(AIAction action) async {
    try {
      switch (action.type) {
        case AIActionType.schedule:
          return await _executeSchedule(action);

        case AIActionType.preset:
          return await _executePreset(action);

        case AIActionType.reminder:
          return await _executeReminder(action);

        case AIActionType.objective:
          return await _executeObjective(action);

        case AIActionType.unknown:
          return false;
      }
    } catch (e) {
      debugPrint('❌ Execute action failed: $e');
      return false;
    }
  }

  /// ⏳ Add action to pending (require approval)
  void addPendingAction(AIAction action) {
    _pendingActions.add(action);
    onActionPending?.call(action);
  }

  /// ✅ Approve and execute pending action
  Future<bool> approveAction(String actionId) async {
    final action = _pendingActions.firstWhere(
      (a) => a.id == actionId,
      orElse: () => throw ArgumentError('Action not found: $actionId'),
    );

    _pendingActions.removeWhere((a) => a.id == actionId);

    final success = await executeAction(action);
    onActionExecuted?.call(action, success);
    return success;
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
