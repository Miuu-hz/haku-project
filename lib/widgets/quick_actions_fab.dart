import 'package:flutter/material.dart';

import '../screens/chat_screen.dart';
import '../screens/focus_timer_screen.dart';
import '../screens/new_entry_screen.dart';

/// ⚡ Quick Actions FAB - ปุ่มลัดหลักๆ
/// 
/// แสดงเมื่อกด FAB ค้าง หรือกดปุ่มที่ใหญ่กว่าปกติ
/// มีลัด: เขียนใหม่, แชทกับ AI

class QuickActionsFab extends StatelessWidget {
  const QuickActionsFab({super.key});

  @override
  Widget build(BuildContext context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 🤖 ปุ่มแชทกับ AI
        FloatingActionButton.small(
          heroTag: 'chat',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (context) => const ChatScreen()),
            );
          },
          backgroundColor: const Color(0xFF2A2A3E),
          child: const Text('箱', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 8),
        
        // ➕ ปุ่มเขียนใหม่ (หลัก)
        FloatingActionButton.extended(
          heroTag: 'write',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (context) => const NewEntryScreen()),
            );
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('เขียน'),
        ),
      ],
    );
}

/// 🎯 FAB แบบ Expandable (กดแล้วขยายตัวเลือก)
class ExpandableFab extends StatefulWidget {
  const ExpandableFab({super.key});

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;
  late Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _rotation = Tween<double>(begin: 0, end: 0.125).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 🤖 แชทกับ AI
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _isExpanded ? 56 : 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isExpanded ? 1 : 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A3E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'คุยกับ Haku',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  heroTag: 'chat',
                  onPressed: () {
                    _toggle();
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (context) => const ChatScreen()),
                    );
                  },
                  backgroundColor: const Color(0xFF9B7CB6),
                  child: const Text('箱', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 8),

        // ⏱️ Focus Timer
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _isExpanded ? 56 : 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isExpanded ? 1 : 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A3E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Focus Timer',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  heroTag: 'focus',
                  onPressed: () {
                    _toggle();
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => const FocusTimerScreen(),
                      ),
                    );
                  },
                  backgroundColor: const Color(0xFF4A3A5E),
                  child: const Icon(Icons.timer_outlined, size: 20),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // 📝 แชร์ความรู้สึก (เตรียมไว้)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _isExpanded ? 56 : 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isExpanded ? 1 : 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A3E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'บันทึกเร็ว',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  heroTag: 'quick',
                  onPressed: () {
                    _toggle();
                    // TODO: Quick capture dialog

                    
                  },
                  backgroundColor: const Color(0xFF6B4E71),
                  child: const Icon(Icons.bolt),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // ➕ ปุ่มหลัก (toggle)
        FloatingActionButton(
          onPressed: _toggle,
          backgroundColor: const Color(0xFF9B7CB6),
          child: RotationTransition(
            turns: _rotation,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
}
