import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/lock_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/background_task_service.dart';
import 'services/biometric_service.dart';
import 'services/encryption_service.dart';
import 'services/widget_service.dart';
import 'utils/haku_design_tokens.dart';

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

  // 🌐 เตรียม locale data สำหรับ DateFormat (intl package)
  await initializeDateFormatting('th', null);

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

/// 🎨 ธีมหลักของแอพ — Haku Crystal (light aurora + glass)
class HakuApp extends StatelessWidget {
  const HakuApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Haku - AI Life Logger',
        debugShowCheckedModeBanner: false,
        theme: _buildCrystalTheme(),
        home: const AppEntryPoint(),
      );

  ThemeData _buildCrystalTheme() {
    final baseTextTheme = GoogleFonts.notoSansThaiTextTheme(
      GoogleFonts.interTextTheme(ThemeData.light().textTheme),
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: kCrystal400,
      brightness: Brightness.light,
      primary: kCrystal400,
      secondary: kLavender500,
      surface: kGlassFill,
      onSurface: kFg1,
      error: kErr,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: baseTextTheme.copyWith(
        displayLarge: kDisplay.copyWith(fontFamily: baseTextTheme.displayLarge?.fontFamily),
        headlineLarge: kH1.copyWith(fontFamily: baseTextTheme.headlineLarge?.fontFamily),
        headlineMedium: kH2.copyWith(fontFamily: baseTextTheme.headlineMedium?.fontFamily),
        headlineSmall: kH3.copyWith(fontFamily: baseTextTheme.headlineSmall?.fontFamily),
        titleLarge: kH4.copyWith(fontFamily: baseTextTheme.titleLarge?.fontFamily),
        bodyLarge: kBody.copyWith(fontFamily: baseTextTheme.bodyLarge?.fontFamily),
        bodyMedium: kBodyMd.copyWith(fontFamily: baseTextTheme.bodyMedium?.fontFamily),
        labelLarge: kLabel.copyWith(fontFamily: baseTextTheme.labelLarge?.fontFamily),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: kGlassFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kR4),
          side: const BorderSide(color: kGlassEdge, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: kGlassFill,
        foregroundColor: kFg1,
        titleTextStyle: GoogleFonts.notoSansThai(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: kFg1,
        ),
        iconTheme: const IconThemeData(color: kFg1),
        actionsIconTheme: const IconThemeData(color: kFg1),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: kCrystal400,
        foregroundColor: kFgOnCyan,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kR3),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: kGlassFillSoft,
        indicatorColor: kCrystal400.withAlpha(40),
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.notoSansThai(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: kFg3,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: kCrystal600);
          }
          return const IconThemeData(color: kFg3);
        }),
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: kGlassFillStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(kR5),
            topRight: Radius.circular(kR5),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: kGlassFillStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kR4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: kField2,
        contentTextStyle: GoogleFonts.notoSansThai(
          color: Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kR3),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kGlassFillSoft,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kR3),
          borderSide: const BorderSide(color: kGlassStroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kR3),
          borderSide: const BorderSide(color: kGlassStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kR3),
          borderSide: const BorderSide(color: kCrystal400, width: 1.5),
        ),
        hintStyle: const TextStyle(color: kFg4),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: kGlassFillSoft,
        selectedColor: kCrystal400.withAlpha(30),
        labelStyle: GoogleFonts.notoSansThai(
          fontSize: 13,
          color: kFg1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRPill),
          side: const BorderSide(color: kGlassStroke),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: kGlassStroke,
        thickness: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: kGlassFillStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kR3),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: kFg3,
        textColor: kFg1,
      ),
    );
  }
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
      _isLocked = hasKey && _biometricEnabled; // ล็อกถ้ามี key และเปิด biometric
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
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: kFieldGradient),
          child: const Center(
            child: CircularProgressIndicator(color: kCrystal400),
          ),
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
