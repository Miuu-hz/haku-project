import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_task_service.dart';
import 'streak_service.dart';
import 'workers/goal_worker.dart';

/// ⏱️ Focus Timer Service — Pomodoro + Goal-Linked (Feature 2.13)
///
/// Flow:
///   user เลือก Goal (optional) → startFocus() → 25 min countdown
///   → เสร็จ → GoalWorker.logProgress() + StreakService.recordSession()
///   → short break (5 min) หรือ long break (15 min) ทุก 4 pomodoros

enum FocusState {
  idle,       // รอเริ่ม
  focusing,   // กำลัง focus
  shortBreak, // พักสั้น 5 นาที
  longBreak,  // พักยาว 15 นาที (ทุก 4 pomodoros)
  paused,     // หยุดชั่วคราว
}

class FocusTimerService {
  static final FocusTimerService _instance = FocusTimerService._internal();
  factory FocusTimerService() => _instance;
  FocusTimerService._internal();

  // ─── Config ────────────────────────────────────────────────
  static const int workMinutes = 25;
  static const int shortBreakMinutes = 5;
  static const int longBreakMinutes = 15;
  static const int pomodorosBeforeLongBreak = 4;

  // ─── State ─────────────────────────────────────────────────
  FocusState _state = FocusState.idle;
  FocusState? _stateBeforePause;
  Timer? _timer;

  int _secondsRemaining = workMinutes * 60;
  int _completedPomodoros = 0; // ใน session นี้
  int _totalToday = 0;
  Goal? _selectedGoal;

  // ─── Dependencies ──────────────────────────────────────────
  final StreakService _streakService = StreakService();

  // ─── Callbacks ─────────────────────────────────────────────
  /// เรียกทุก 1 วินาที พร้อม secondsRemaining
  void Function(int seconds)? onTick;

  /// เรียกเมื่อ state เปลี่ยน
  void Function(FocusState state)? onStateChange;

  /// เรียกเมื่อ pomodoro เสร็จ — ส่ง goal + streak ใหม่
  void Function(Goal? linkedGoal, int newStreak)? onPomodoroComplete;

  // ─── Getters ───────────────────────────────────────────────
  FocusState get state => _state;
  int get secondsRemaining => _secondsRemaining;
  int get completedPomodoros => _completedPomodoros;
  int get totalToday => _totalToday;
  Goal? get selectedGoal => _selectedGoal;
  int get currentStreak => _streakService.currentStreak;
  int get totalSessions => _streakService.totalSessions;
  String? getMilestone(int streak) => _streakService.getMilestone(streak);

  String get formattedTime {
    final m = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 0.0 → 1.0 (ใช้กับ CircularProgressIndicator)
  double get progress {
    final total = _totalSecondsForState(
      _state == FocusState.paused
          ? (_stateBeforePause ?? FocusState.focusing)
          : _state,
    );
    if (total == 0) return 0;
    return 1 - (_secondsRemaining / total);
  }

  String get stateLabel {
    switch (_state) {
      case FocusState.focusing:
        return 'กำลัง Focus${_selectedGoal != null ? " — ${_selectedGoal!.title}" : ""}';
      case FocusState.shortBreak:
        return 'พักสั้น ☕';
      case FocusState.longBreak:
        return 'พักยาว 🎉';
      case FocusState.paused:
        return 'หยุดชั่วคราว ⏸️';
      case FocusState.idle:
        return 'พร้อมเริ่ม';
    }
  }

  // ─── Init ──────────────────────────────────────────────────
  Future<void> initialize() async {
    await _streakService.initialize();
    await _loadTodayCount();
  }

  Future<void> _loadTodayCount() async {
    final prefs = await SharedPreferences.getInstance();
    _totalToday = prefs.getInt(_todayKey()) ?? 0;
  }

  Future<void> _saveTodayCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_todayKey(), _totalToday);
  }

  String _todayKey() {
    final now = DateTime.now();
    return 'focus_count_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  // ─── Goal Selection ────────────────────────────────────────
  void selectGoal(Goal? goal) {
    _selectedGoal = goal;
    debugPrint('🎯 Focus goal set: ${goal?.title ?? "none"}');
  }

  // ─── Controls ──────────────────────────────────────────────
  void startFocus() {
    if (_state != FocusState.idle) return;
    _secondsRemaining = workMinutes * 60;
    _setState(FocusState.focusing);
    _startTimer();
  }

  void pause() {
    if (_state == FocusState.focusing ||
        _state == FocusState.shortBreak ||
        _state == FocusState.longBreak) {
      _stateBeforePause = _state;
      _timer?.cancel();
      _setState(FocusState.paused);
    }
  }

  void resume() {
    if (_state != FocusState.paused) return;
    _setState(_stateBeforePause ?? FocusState.focusing);
    _stateBeforePause = null;
    _startTimer();
  }

  /// ข้ามช่วงปัจจุบัน (focus → break หรือ break → idle)
  void skip() {
    _timer?.cancel();
    _advanceState();
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _completedPomodoros = 0;
    _selectedGoal = null;
    _secondsRemaining = workMinutes * 60;
    _setState(FocusState.idle);
  }

  // ─── Internal ──────────────────────────────────────────────
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemaining > 0) {
        _secondsRemaining--;
        onTick?.call(_secondsRemaining);
      } else {
        _timer?.cancel();
        _advanceState();
      }
    });
  }

  Future<void> _advanceState() async {
    if (_state == FocusState.focusing) {
      await _onPomodoroComplete();
      // เลือก break ตามจำนวน pomodoros
      final isLong = _completedPomodoros % pomodorosBeforeLongBreak == 0;
      if (isLong) {
        _secondsRemaining = longBreakMinutes * 60;
        _setState(FocusState.longBreak);
      } else {
        _secondsRemaining = shortBreakMinutes * 60;
        _setState(FocusState.shortBreak);
      }
      await BackgroundTaskService.showBreakStartNotification(
        isLong: isLong,
        goalTitle: _selectedGoal?.title,
      );
      _startTimer();
    } else {
      // break เสร็จ → กลับ idle ให้ user เริ่มรอบต่อไปเอง
      _secondsRemaining = workMinutes * 60;
      _setState(FocusState.idle);
      await BackgroundTaskService.showFocusReminderNotification();
    }
  }

  Future<void> _onPomodoroComplete() async {
    _completedPomodoros++;
    _totalToday++;
    await _saveTodayCount();

    // ── Goal-linked: อัปเดต progress อัตโนมัติ ──────────────
    if (_selectedGoal != null) {
      final worker = GoalWorker();
      await worker.initialize();
      await worker.logProgress(_selectedGoal!.id);
      debugPrint('🎯 Auto-logged progress → ${_selectedGoal!.title}');
    }

    // ── Streak ──────────────────────────────────────────────
    final newStreak = await _streakService.recordSession();

    onPomodoroComplete?.call(_selectedGoal, newStreak);
    debugPrint('⏱️ Pomodoro #$_completedPomodoros done! Streak: $newStreak');
  }

  void _setState(FocusState newState) {
    _state = newState;
    onStateChange?.call(newState);
  }

  int _totalSecondsForState(FocusState s) {
    switch (s) {
      case FocusState.focusing:
        return workMinutes * 60;
      case FocusState.shortBreak:
        return shortBreakMinutes * 60;
      case FocusState.longBreak:
        return longBreakMinutes * 60;
      default:
        return workMinutes * 60;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
