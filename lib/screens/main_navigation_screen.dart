import 'package:flutter/material.dart';

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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        backgroundColor: const Color(0xFF1A1A2E),
        indicatorColor: const Color(0xFF9B7CB6).withAlpha(100),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: 'บันทึก',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Haku AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'ตั้งค่า',
          ),
        ],
      ),
    );
  }
}
