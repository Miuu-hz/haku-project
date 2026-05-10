import 'package:flutter/material.dart';

import '../utils/haku_design_tokens.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// 🧭 หน้า Navigation หลัก (Bottom Navigation Bar)
///
/// มี 3 แท็บ:
/// - บันทึก (Home)
/// - Haku AI (Chat)
/// - ตั้งค่า (Settings)

class MainNavigationScreen extends StatefulWidget {
  final String? initialChatQuestion;

  const MainNavigationScreen({super.key, this.initialChatQuestion});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      ChatScreen(initialQuestion: widget.initialChatQuestion),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: HakuGlassNavBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book_rounded),
            label: 'บันทึก',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Haku AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'ตั้งค่า',
          ),
        ],
      ),
    );
  }
}
