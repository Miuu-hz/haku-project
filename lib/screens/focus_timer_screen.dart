import 'package:flutter/material.dart';

import '../services/focus_timer_service.dart';
import '../services/workers/goal_worker.dart';

/// ⏱️ Focus Timer Screen — Pomodoro + Goal-Linked (Feature 2.13)
class FocusTimerScreen extends StatefulWidget {
  const FocusTimerScreen({super.key});

  @override
  State<FocusTimerScreen> createState() => _FocusTimerScreenState();
}

class _FocusTimerScreenState extends State<FocusTimerScreen> {
  final FocusTimerService _timer = FocusTimerService();
  final GoalWorker _goalWorker = GoalWorker();

  List<Goal> _activeGoals = [];

  @override
  void initState() {
    super.initState();
    _init();

    _timer.onTick = (_) {
      if (mounted) setState(() {});
    };
    _timer.onStateChange = (_) {
      if (mounted) setState(() {});
    };
    _timer.onPomodoroComplete = (goal, streak) {
      final milestone = _timer.getMilestone(streak);
      if (mounted) {
        setState(() {});
        _showCompletionSnackBar(goal, streak, milestone);
      }
    };
  }

  Future<void> _init() async {
    await _timer.initialize();
    await _goalWorker.initialize();
    if (mounted) {
      setState(() {
        _activeGoals = _goalWorker.activeGoals;
      });
    }
  }

  void _showCompletionSnackBar(Goal? goal, int streak, String? milestone) {
    final msg = StringBuffer('🎉 Pomodoro เสร็จ!');
    if (goal != null) msg.write(' +1 → ${goal.title}');
    if (milestone != null) msg.write('  $milestone');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.toString()),
        backgroundColor: const Color(0xFF6B4E71),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _timer.onTick = null;
    _timer.onStateChange = null;
    _timer.onPomodoroComplete = null;
    super.dispose();
  }

  // ─── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            _buildStreakRow(),
            const SizedBox(height: 32),
            _buildTimerRing(),
            const SizedBox(height: 8),
            _buildStateLabel(),
            const SizedBox(height: 24),
            _buildPomodoroDots(),
            const SizedBox(height: 8),
            Text(
              'วันนี้: ${_timer.totalToday} pomodoro${_timer.totalToday != 1 ? "s" : ""}',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 28),
            if (_timer.state == FocusState.idle) _buildGoalPicker(),
            const SizedBox(height: 24),
            _buildControls(),
            const SizedBox(height: 32),
            if (_timer.state == FocusState.idle) _buildGoalProgressList(),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text('Focus Timer'),
      actions: [
        if (_timer.currentStreak > 0)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              label: Text(
                '🔥 ${_timer.currentStreak} วัน',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              backgroundColor: const Color(0xFF6B4E71),
            ),
          ),
      ],
    );
  }

  Widget _buildStreakRow() {
    final streak = _timer.currentStreak;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _statChip('🔥 Streak', '$streak วัน'),
        const SizedBox(width: 12),
        _statChip('⏱️ ทั้งหมด', '${_timer.totalSessions} sessions'),
      ],
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTimerRing() {
    final isFocusing = _timer.state == FocusState.focusing;
    final isBreak = _timer.state == FocusState.shortBreak ||
        _timer.state == FocusState.longBreak;
    final color = isFocusing
        ? const Color(0xFF9B7CB6)
        : isBreak
            ? const Color(0xFF4CAF50)
            : Colors.white24;

    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 220,
            height: 220,
            child: CircularProgressIndicator(
              value: _timer.state == FocusState.idle ? 0 : _timer.progress,
              strokeWidth: 10,
              backgroundColor: const Color(0xFF2A2A3E),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _timer.formattedTime,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                ),
              ),
              if (_timer.selectedGoal != null && _timer.state != FocusState.idle)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_timer.selectedGoal!.category.emoji} ${_timer.selectedGoal!.title}',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStateLabel() {
    return Text(
      _timer.stateLabel,
      style: const TextStyle(color: Colors.white70, fontSize: 15),
    );
  }

  /// 4 วงกลมแสดง pomodoros ที่ทำแล้วในรอบนี้
  Widget _buildPomodoroDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(FocusTimerService.pomodorosBeforeLongBreak, (i) {
        final filled = i < (_timer.completedPomodoros % FocusTimerService.pomodorosBeforeLongBreak);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? const Color(0xFF9B7CB6) : const Color(0xFF2A2A3E),
              border: Border.all(color: const Color(0xFF9B7CB6), width: 1.5),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildGoalPicker() {
    if (_activeGoals.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'ยังไม่มีเป้าหมาย — บอก Haku ว่าอยากทำอะไรในแชทก่อนนะคะ',
          style: TextStyle(color: Colors.white54, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Focus เพื่อเป้าหมายไหน?',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButton<Goal?>(
            value: _timer.selectedGoal,
            isExpanded: true,
            dropdownColor: const Color(0xFF1E1E2E),
            underline: const SizedBox(),
            hint: const Text('ไม่ระบุ (focus ทั่วไป)',
                style: TextStyle(color: Colors.white38)),
            items: [
              const DropdownMenuItem<Goal?>(
                value: null,
                child: Text('ไม่ระบุ',
                    style: TextStyle(color: Colors.white54)),
              ),
              ..._activeGoals.map(
                (g) => DropdownMenuItem<Goal?>(
                  value: g,
                  child: Row(
                    children: [
                      Text(g.category.emoji),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          g.title,
                          style: const TextStyle(color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (g.target != null)
                        Text(
                          '${g.progress}/${g.target!.amount}',
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            onChanged: (goal) => setState(() => _timer.selectGoal(goal)),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final state = _timer.state;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Reset
        if (state != FocusState.idle)
          IconButton(
            onPressed: () => setState(() => _timer.reset()),
            icon: const Icon(Icons.stop_rounded),
            color: Colors.white38,
            iconSize: 32,
            tooltip: 'รีเซ็ต',
          ),
        const SizedBox(width: 12),

        // Start / Pause / Resume
        SizedBox(
          width: 72,
          height: 72,
          child: FloatingActionButton(
            onPressed: () {
              setState(() {
                if (state == FocusState.idle) {
                  _timer.startFocus();
                } else if (state == FocusState.paused) {
                  _timer.resume();
                } else {
                  _timer.pause();
                }
              });
            },
            backgroundColor: const Color(0xFF9B7CB6),
            child: Icon(
              state == FocusState.idle
                  ? Icons.play_arrow_rounded
                  : state == FocusState.paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
              size: 36,
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Skip
        if (state != FocusState.idle)
          IconButton(
            onPressed: () => _timer.skip(),
            icon: const Icon(Icons.skip_next_rounded),
            color: Colors.white38,
            iconSize: 32,
            tooltip: 'ข้าม',
          ),
      ],
    );
  }

  /// แสดง progress ของ active goals ด้านล่าง
  Widget _buildGoalProgressList() {
    if (_activeGoals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        const Text(
          'ความคืบหน้าเป้าหมาย',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 10),
        ..._activeGoals.take(4).map(_buildGoalTile),
      ],
    );
  }

  Widget _buildGoalTile(Goal goal) {
    final hasTarget = goal.target != null;
    final percent = goal.progressPercent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(goal.category.emoji),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  goal.title,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasTarget)
                Text(
                  '${goal.progress}/${goal.target!.amount} ${goal.target!.unit}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
            ],
          ),
          if (hasTarget) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: percent,
              backgroundColor: const Color(0xFF2A2A3E),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF9B7CB6)),
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ],
      ),
    );
  }
}
