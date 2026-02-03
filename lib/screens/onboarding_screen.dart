import 'package:flutter/material.dart';

import '../services/encryption_service.dart';

/// 👋 Onboarding Screen - แนะนำแอพครั้งแรก
/// 
/// แสดงเฉพาะตอนเปิดแอพครั้งแรก
/// อธิบาย:
/// - ความเป็นส่วนตัว (Privacy First)
/// - การเข้ารหัส (Encryption)
/// - AI บนเครื่อง (On-device)

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isCreatingKey = false;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      icon: '🎌',
      title: 'ยินดีต้อนรับสู่ Haku',
      subtitle: 'บันทึกชีวิตประจำวันแบบส่วนตัวที่สุด',
      description: 'Haku (箱) แปลว่า "กล่อง" ในภาษาญี่ปุ่น\n'
          'สัญลักษณ์ของการเก็บรักษาความทรงจำอย่างปลอดภัย',
    ),
    OnboardingPage(
      icon: '🔒',
      title: 'ความเป็นส่วนตัวก่อนเสมอ',
      subtitle: 'ข้อมูลของคุณ อยู่กับคุณเท่านั้น',
      description: '• เก็บข้อมูลบนเครื่อง ไม่ส่งขึ้น Cloud\n'
          '• เข้ารหัสด้วย SQLCipher\n'
          '• ไม่มีบัญชีผู้ใช้ ไม่มี tracking',
    ),
    OnboardingPage(
      icon: '🤖',
      title: 'AI ส่วนตัวบนเครื่อง',
      subtitle: 'ประมวลผลบนเครื่อง ไม่ต้องอินเทอร์เน็ต',
      description: '• ถามคำถามเกี่ยวกับบันทึกของคุณ\n'
          '• สรุปวัน วิเคราะห์อารมณ์\n'
          '• ทำงานได้แม้ Offline 100%',
    ),
    OnboardingPage(
      icon: '📱',
      title: 'พร้อมใช้งานแล้ว',
      subtitle: 'เริ่มบันทึกชีวิตของคุณได้เลย',
      description: 'แตะ "เริ่มต้นใช้งาน" เพื่อสร้าง\n'
          'encryption key สำหรับปกป้องข้อมูลของคุณ',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    setState(() => _isCreatingKey = true);
    
    // สร้าง encryption key
    await EncryptionService.getOrCreateDatabaseKey();
    
    // TODO: บันทึกว่า onboarding เสร็จแล้ว
    // await SharedPreferences.getInstance().then((prefs) {
    //   prefs.setBool('onboarding_complete', true);
    // });
    
    if (mounted) {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ส่วนเนื้อหา (PageView)
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) => _buildPage(_pages[index]),
              ),
            ),
            
            // จุดบอกหน้า
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (index) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index
                        ? const Color(0xFF9B7CB6)
                        : Colors.white.withAlpha(50),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // ปุ่มควบคุม
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  // ปุ่มข้าม (ถ้าไม่ใช่หน้าสุดท้าย)
                  if (_currentPage < _pages.length - 1)
                    TextButton(
                      onPressed: () {
                        _pageController.jumpToPage(_pages.length - 1);
                      },
                      child: Text(
                        'ข้าม',
                        style: TextStyle(color: Colors.white.withAlpha(150)),
                      ),
                    )
                  else
                    const SizedBox(width: 80),
                  
                  const Spacer(),
                  
                  // ปุ่มถัดไป/เริ่มต้น
                  SizedBox(
                    width: 140,
                    height: 56,
                    child: _isCreatingKey
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF9B7CB6),
                            ),
                          )
                        : FilledButton(
                            onPressed: () {
                              if (_currentPage < _pages.length - 1) {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              } else {
                                _finishOnboarding();
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF9B7CB6),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              _currentPage < _pages.length - 1 ? 'ถัดไป' : 'เริ่มต้นใช้งาน',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

  Widget _buildPage(OnboardingPage page) => Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Text(
            page.icon,
            style: const TextStyle(fontSize: 100),
          ),
          
          const SizedBox(height: 40),
          
          // Title
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Subtitle
          Text(
            page.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              color: Color(0xFF9B7CB6),
              fontWeight: FontWeight.w500,
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Description
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withAlpha(150),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
}

class OnboardingPage {
  final String icon;
  final String title;
  final String subtitle;
  final String description;

  OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
  });
}
