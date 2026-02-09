import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/objective.dart';
import 'scheduler_service.dart';

/// 🎯 Objective Service - จัดการเป้าหมาย/งาน
///
/// หน้าที่หลัก:
/// 1. เก็บและจัดการ Objectives
/// 2. Sync กับ Calendar
/// 3. ติดตามความคืบหน้า
/// 4. ให้ AI สามารถสร้าง/แก้ไข Objectives ได้

class ObjectiveService {
  static final ObjectiveService _instance = ObjectiveService._internal();
  factory ObjectiveService() => _instance;
  ObjectiveService._internal();

  static const String _prefsKey = 'haku_objectives';

  List<Objective> _objectives = [];
  List<Objective> get objectives => List.unmodifiable(_objectives);

  // Callbacks
  void Function(Objective objective)? onObjectiveAdded;
  void Function(Objective objective)? onObjectiveUpdated;
  void Function(String objectiveId)? onObjectiveDeleted;
  void Function(Objective objective)? onObjectiveOverdue;

  Timer? _checkOverdueTimer;
  bool _isInitialized = false;

  /// 🚀 เริ่มต้น service
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadObjectives();
    _startOverdueChecker();

    _isInitialized = true;
    debugPrint('✅ Objective Service initialized');
    debugPrint('   - Objectives: ${_objectives.length}');
  }

  /// 📦 โหลด objectives จาก storage
  Future<void> _loadObjectives() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);

      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
        _objectives = jsonList
            .map((j) => Objective.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('⚠️ Load objectives failed: $e');
    }
  }

  /// 💾 บันทึก objectives
  Future<void> _saveObjectives() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_objectives.map((o) => o.toJson()).toList());
      await prefs.setString(_prefsKey, jsonStr);
    } catch (e) {
      debugPrint('⚠️ Save objectives failed: $e');
    }
  }

  /// ➕ เพิ่ม Objective
  Future<void> addObjective(Objective objective, {bool createCalendarEvent = true}) async {
    _objectives.add(objective);
    await _saveObjectives();

    // สร้าง calendar event ถ้าต้องการ
    if (createCalendarEvent && objective.dueDate != null) {
      final event = EventInfo(
        title: objective.title,
        date: objective.dueDate,
        time: objective.dueTime,
        location: objective.location,
        durationMinutes: objective.durationMinutes ?? 60,
        originalText: objective.originalText,
      );

      await SchedulerService().createCalendarEvent(event);

      // ตั้ง reminders
      for (final minutes in objective.reminderMinutesBefore) {
        await SchedulerService().scheduleReminder(event, minutesBefore: minutes);
      }
    }

    onObjectiveAdded?.call(objective);
    debugPrint('➕ Added objective: ${objective.title}');
  }

  /// ✏️ แก้ไข Objective
  Future<void> updateObjective(Objective objective) async {
    final index = _objectives.indexWhere((o) => o.id == objective.id);
    if (index == -1) return;

    _objectives[index] = objective;
    await _saveObjectives();

    onObjectiveUpdated?.call(objective);
    debugPrint('✏️ Updated objective: ${objective.title}');
  }

  /// 🗑️ ลบ Objective
  Future<void> deleteObjective(String objectiveId) async {
    _objectives.removeWhere((o) => o.id == objectiveId);
    await _saveObjectives();

    onObjectiveDeleted?.call(objectiveId);
    debugPrint('🗑️ Deleted objective: $objectiveId');
  }

  /// ✅ Mark as completed
  Future<void> completeObjective(String objectiveId) async {
    final index = _objectives.indexWhere((o) => o.id == objectiveId);
    if (index == -1) return;

    _objectives[index] = _objectives[index].copyWith(
      status: ObjectiveStatus.completed,
    );
    await _saveObjectives();

    onObjectiveUpdated?.call(_objectives[index]);
    debugPrint('✅ Completed objective: ${_objectives[index].title}');
  }

  /// 🔄 Mark as in progress
  Future<void> startObjective(String objectiveId) async {
    final index = _objectives.indexWhere((o) => o.id == objectiveId);
    if (index == -1) return;

    _objectives[index] = _objectives[index].copyWith(
      status: ObjectiveStatus.inProgress,
    );
    await _saveObjectives();

    onObjectiveUpdated?.call(_objectives[index]);
  }

  /// ❌ Cancel objective
  Future<void> cancelObjective(String objectiveId) async {
    final index = _objectives.indexWhere((o) => o.id == objectiveId);
    if (index == -1) return;

    _objectives[index] = _objectives[index].copyWith(
      status: ObjectiveStatus.cancelled,
    );
    await _saveObjectives();

    onObjectiveUpdated?.call(_objectives[index]);
  }

  /// ✅ Approve AI-generated objective
  Future<void> approveObjective(String objectiveId) async {
    final index = _objectives.indexWhere((o) => o.id == objectiveId);
    if (index == -1) return;

    _objectives[index] = _objectives[index].copyWith(
      isApproved: true,
    );
    await _saveObjectives();

    // สร้าง calendar event
    final objective = _objectives[index];
    if (objective.dueDate != null) {
      final event = EventInfo(
        title: objective.title,
        date: objective.dueDate,
        time: objective.dueTime,
        location: objective.location,
        durationMinutes: objective.durationMinutes ?? 60,
        originalText: objective.originalText,
      );

      await SchedulerService().createCalendarEvent(event);
    }

    onObjectiveUpdated?.call(_objectives[index]);
    debugPrint('✅ Approved objective: ${objective.title}');
  }

  // ============================================================================
  // Getters
  // ============================================================================

  /// Objectives ที่ยังไม่เสร็จ
  List<Objective> get pendingObjectives => _objectives
      .where((o) =>
          o.status == ObjectiveStatus.pending ||
          o.status == ObjectiveStatus.inProgress)
      .toList();

  /// Objectives วันนี้
  List<Objective> get todayObjectives {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    return _objectives.where((o) {
      if (o.dueDate == null) return false;
      return o.dueDate!.isAfter(today.subtract(const Duration(seconds: 1))) &&
          o.dueDate!.isBefore(tomorrow);
    }).toList();
  }

  /// Objectives พรุ่งนี้
  List<Objective> get tomorrowObjectives {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final dayAfter = tomorrow.add(const Duration(days: 1));

    return _objectives.where((o) {
      if (o.dueDate == null) return false;
      return o.dueDate!.isAfter(tomorrow.subtract(const Duration(seconds: 1))) &&
          o.dueDate!.isBefore(dayAfter);
    }).toList();
  }

  /// Objectives ที่ AI สร้างและรอ approval
  List<Objective> get pendingApprovalObjectives => _objectives
      .where((o) => o.isAIGenerated && !o.isApproved)
      .toList();

  /// Objectives ที่เลยกำหนด
  List<Objective> get overdueObjectives => _objectives
      .where((o) => o.status == ObjectiveStatus.overdue)
      .toList();

  // ============================================================================
  // Overdue Checker
  // ============================================================================

  void _startOverdueChecker() {
    // เช็คทุก 5 นาที
    _checkOverdueTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkOverdue();
    });

    // เช็คครั้งแรกทันที
    _checkOverdue();
  }

  void _checkOverdue() {
    final now = DateTime.now();
    bool changed = false;

    for (int i = 0; i < _objectives.length; i++) {
      final objective = _objectives[i];

      // ข้าม objectives ที่เสร็จหรือยกเลิกแล้ว
      if (objective.status == ObjectiveStatus.completed ||
          objective.status == ObjectiveStatus.cancelled ||
          objective.status == ObjectiveStatus.overdue) {
        continue;
      }

      // เช็คว่าเลยกำหนดหรือยัง
      if (objective.dueDate != null) {
        DateTime dueDateTime = objective.dueDate!;

        // ถ้ามีเวลากำหนด ให้รวมเข้าไปด้วย
        if (objective.dueTime != null) {
          final parts = objective.dueTime!.split(':');
          if (parts.length == 2) {
            dueDateTime = DateTime(
              objective.dueDate!.year,
              objective.dueDate!.month,
              objective.dueDate!.day,
              int.tryParse(parts[0]) ?? 0,
              int.tryParse(parts[1]) ?? 0,
            );
          }
        }

        if (now.isAfter(dueDateTime)) {
          _objectives[i] = objective.copyWith(
            status: ObjectiveStatus.overdue,
          );
          changed = true;

          onObjectiveOverdue?.call(_objectives[i]);
          debugPrint('⚠️ Objective overdue: ${objective.title}');
        }
      }
    }

    if (changed) {
      _saveObjectives();
    }
  }

  /// 🧹 Dispose
  void dispose() {
    _checkOverdueTimer?.cancel();
    _isInitialized = false;
  }
}
