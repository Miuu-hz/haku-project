import 'package:flutter/material.dart';

import '../utils/haku_design_tokens.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// 🧭 หน้า Navigation หลัก — Floating Glass Pill Nav
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final screens = [
      const HomeScreen(),
      ChatScreen(initialQuestion: widget.initialChatQuestion),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: screens,
          ),
          // Floating glass pill nav
          Positioned(
            bottom: 22 + bottomInset,
            left: 0,
            right: 0,
            child: Center(
              child: HakuGlassNavBar(
                currentIndex: _currentIndex,
                onTap: (i) => setState(() => _currentIndex = i),
                destinations: const [],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
