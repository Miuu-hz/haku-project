import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/encryption_service.dart';
import '../utils/haku_design_tokens.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isCreatingKey = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  final List<_OBPage> _pages = const [
    _OBPage(
      emoji: '🎌',
      accent: kCrystal400,
      title: 'ยินดีต้อนรับสู่ Haku',
      subtitle: 'บันทึกชีวิตประจำวันแบบส่วนตัวที่สุด',
      description: 'Haku (箱) แปลว่า "กล่อง" ในภาษาญี่ปุ่น\n'
          'สัญลักษณ์ของการเก็บรักษาความทรงจำอย่างปลอดภัย',
    ),
    _OBPage(
      emoji: '🔒',
      accent: kLavender500,
      title: 'ความเป็นส่วนตัวก่อนเสมอ',
      subtitle: 'ข้อมูลของคุณ อยู่กับคุณเท่านั้น',
      description: '• เก็บข้อมูลบนเครื่อง ไม่ส่งขึ้น Cloud\n'
          '• เข้ารหัสด้วย SQLCipher\n'
          '• ไม่มีบัญชีผู้ใช้ ไม่มี tracking',
    ),
    _OBPage(
      emoji: '🤖',
      accent: kVividMint,
      title: 'AI ส่วนตัวบนเครื่อง',
      subtitle: 'ประมวลผลบนเครื่อง ไม่ต้องอินเทอร์เน็ต',
      description: '• ถามคำถามเกี่ยวกับบันทึกของคุณ\n'
          '• สรุปวัน วิเคราะห์อารมณ์\n'
          '• ทำงานได้แม้ Offline 100%',
    ),
    _OBPage(
      emoji: '✨',
      accent: kVividGold,
      title: 'พร้อมใช้งานแล้ว',
      subtitle: 'เริ่มบันทึกชีวิตของคุณได้เลย',
      description: 'แตะ "เริ่มต้นใช้งาน" เพื่อสร้าง\n'
          'encryption key สำหรับปกป้องข้อมูลของคุณ',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    setState(() => _isCreatingKey = true);
    await EncryptionService.getOrCreateDatabaseKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (mounted) widget.onComplete();
  }

  void _onPageChanged(int index) {
    _fadeCtrl.forward(from: 0);
    setState(() => _currentPage = index);
  }

  @override
  Widget build(BuildContext context) {
    return HakuAuroraBackground(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                // PageView
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    itemCount: _pages.length,
                    itemBuilder: (_, i) => FadeTransition(
                      opacity: _fadeAnim,
                      child: _buildPage(_pages[i]),
                    ),
                  ),
                ),

                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: _currentPage == i ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: _currentPage == i
                            ? _pages[i].accent
                            : kFg1.withAlpha(30),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Controls
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Row(
                    children: [
                      if (_currentPage < _pages.length - 1)
                        TextButton(
                          onPressed: () => _pageController.jumpToPage(
                              _pages.length - 1),
                          child: const Text(
                            'ข้าม',
                            style: TextStyle(color: kFg3, fontSize: 15),
                          ),
                        )
                      else
                        const SizedBox(width: 64),

                      const Spacer(),

                      SizedBox(
                        width: 160,
                        height: 52,
                        child: _isCreatingKey
                            ? Center(
                                child: CircularProgressIndicator(
                                  color: _pages[_currentPage].accent,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : _buildNextButton(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNextButton() {
    final isLast = _currentPage == _pages.length - 1;
    final accent = _pages[_currentPage].accent;
    return GestureDetector(
      onTap: () {
        if (isLast) {
          _finishOnboarding();
        } else {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          );
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kRPill),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, accent.withAlpha(180)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(kRPill),
              boxShadow: [
                BoxShadow(
                  color: accent.withAlpha(80),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              isLast ? 'เริ่มต้นใช้งาน' : 'ถัดไป',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: kFg1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(_OBPage page) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Glass card with emoji
          ClipRRect(
            borderRadius: BorderRadius.circular(kR5),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: page.accent.withAlpha(25),
                  borderRadius: BorderRadius.circular(kR5),
                  border: Border.all(color: page.accent.withAlpha(80), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: page.accent.withAlpha(40),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(page.emoji, style: const TextStyle(fontSize: 64)),
              ),
            ),
          ),

          const SizedBox(height: 40),

          // Title
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: kFg1,
              height: 1.15,
              letterSpacing: -0.4,
            ),
          ),

          const SizedBox(height: 10),

          // Subtitle
          Text(
            page.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: page.accent,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 24),

          // Description glass card
          ClipRRect(
            borderRadius: BorderRadius.circular(kR4),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: kGlassFill,
                  borderRadius: BorderRadius.circular(kR4),
                  border: Border.all(color: kGlassStroke),
                ),
                child: Text(
                  page.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: kFg3,
                    height: 1.7,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OBPage {
  final String emoji;
  final Color accent;
  final String title;
  final String subtitle;
  final String description;

  const _OBPage({
    required this.emoji,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.description,
  });
}
