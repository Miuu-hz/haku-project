import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/lock_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/background_task_service.dart';
import 'services/biometric_service.dart';
import 'services/encryption_service.dart';
import 'services/widget_service.dart';

/// 🎌 Haku (箱) - AI Personal Life Logger
/// 
/// แอพบันทึกชีวิตประจำวันที่เน้นความเป็นส่วนตัว (Privacy-First)
/// ทำงานบนอุปกรณ์โดยไม่ต้องส่งข้อมูลขึ้น Cloud
/// 
/// Phase 1 FINAL Features:
/// - ✅ SQLite + SQLCipher Encryption
/// - ✅ Biometric Lock (Face ID / Fingerprint)
/// - ✅ Auto-lock after inactivity
/// - ✅ Export (JSON/Markdown/CSV)
/// - ✅ Android Widgets
/// - ✅ AI Chat UI (Mock)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⏰ zonedSchedule: background time triggers (09:00 morning, 20:00 evening)
  try {
    await BackgroundTaskService.initialize();
    await BackgroundTaskService.scheduleDailyTriggers();
  } catch (e) {
    debugPrint('⚠️ BackgroundTaskService init failed (non-fatal): $e');
  }

  runApp(
    const ProviderScope(
      child: HakuApp(),
    ),
  );
}

/// 🎨 ธีมหลักของแอพ
class HakuApp extends StatelessWidget {
  const HakuApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Haku - AI Life Logger',
      debugShowCheckedModeBanner: false,
      
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B4E71),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansThaiTextTheme(
          ThemeData.dark().textTheme,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: const Color(0xFF1A1A2E),
          titleTextStyle: GoogleFonts.notoSansThai(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: const Color(0xFF9B7CB6),
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      
      home: const AppEntryPoint(),
    );
}

/// 🚪 จุดเริ่มต้นของแอพ
class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});

  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _showOnboarding = false;
  bool _isLocked = false;
  final bool _biometricEnabled = true;
  final int _autoLockMinutes = 1;
  DateTime? _lastActiveTime;
  Timer? _lockTimer;
  String? _pendingWidgetQuestion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // ตรวจสอบว่ามี encryption key หรือยัง (คือเคย onboarding หรือยัง)
    final hasKey = await EncryptionService.hasEncryptionKey();
    
    // ตรวจสอบว่าเปิดมาจาก Widget หรือไม่
    final widgetAction = await WidgetService.getWidgetAction();
    if (widgetAction != null) {
      final question = widgetAction['question'] as String?;
      if (question != null) _pendingWidgetQuestion = question;
    }
    
    setState(() {
      _showOnboarding = !hasKey;
      _isLocked = hasKey && _biometricEnabled;  // ล็อกถ้ามี key และเปิด biometric
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    super.dispose();
  }

  /// 👀 ตรวจสอบ App Lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _lastActiveTime = DateTime.now();
        _startLockTimer();
        break;
        
      case AppLifecycleState.resumed:
        _lockTimer?.cancel();
        _checkShouldLock();
        break;
        
      default:
        break;
    }
  }

  void _startLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer(Duration(minutes: _autoLockMinutes), () {
      if (mounted && _biometricEnabled) {
        setState(() => _isLocked = true);
      }
    });
  }

  void _checkShouldLock() {
    if (_lastActiveTime == null || !_biometricEnabled) return;
    
    final shouldLock = BiometricService.shouldLock(
      _lastActiveTime,
      lockAfterMinutes: _autoLockMinutes,
    );
    
    if (shouldLock && mounted) {
      setState(() => _isLocked = true);
    }
  }

  void _unlock() {
    setState(() {
      _isLocked = false;
      _lastActiveTime = DateTime.now();
    });
  }

  void _completeOnboarding() {
    setState(() {
      _showOnboarding = false;
      _isLocked = _biometricEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF9B7CB6)),
        ),
      );
    }

    // 👋 แสดง Onboarding ถ้ายังไม่เคยเปิดแอพ
    if (_showOnboarding) {
      return OnboardingScreen(
        onComplete: _completeOnboarding,
      );
    }

    // 🔒 ถ้าล็อกอยู่ แสดงหน้าล็อก
    if (_isLocked) {
      return LockScreen(
        onAuthenticated: _unlock,
        showCancel: false,
      );
    }

    // 🏠 แสดงหน้าหลัก
    return MainNavigationScreen(
      initialChatQuestion: _pendingWidgetQuestion,
    );
  }
}
