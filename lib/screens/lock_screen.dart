import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/biometric_service.dart';
import '../utils/haku_design_tokens.dart';

/// 🔒 หน้าล็อกจอ - ยืนยันตัวตนก่อนเข้าแอพ
///
/// แสดงเมื่อ:
/// - เปิดแอพครั้งแรก (ถ้าเปิด biometric)
/// - กลับมาจาก background หลังไม่ใช้งานนาน (1 นาที)

class LockScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;
  final bool showCancel;

  const LockScreen({
    super.key,
    required this.onAuthenticated,
    this.showCancel = false,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  bool _isAuthenticating = false;
  String _errorMessage = '';
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _errorMessage = '';
    });

    try {
      final didAuthenticate = await BiometricService.authenticate();

      if (didAuthenticate && mounted) {
        widget.onAuthenticated();
      } else if (mounted) {
        setState(() {
          _errorMessage = 'ยืนยันตัวตนไม่สำเร็จ กรุณาลองใหม่';
          _isAuthenticating = false;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'เกิดข้อผิดพลาด: ${e.message}';
          _isAuthenticating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => HakuAuroraBackground(
        children: [
          Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),

                  // Rotating lavender fingerprint orb
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) => Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: const [kLavender400, kLavender600],
                          transform: GradientRotation(
                            _animationController.value * 2 * 3.14159,
                          ),
                        ),
                        borderRadius: BorderRadius.circular(60),
                        boxShadow: kGlowLavender,
                      ),
                      child: const Center(
                        child: Icon(Icons.fingerprint, size: 60, color: Colors.white),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  const Text(
                    'Haku ถูกล็อก',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: kFg1,
                    ),
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'ยืนยันตัวตนเพื่อเข้าใช้งาน',
                    style: TextStyle(fontSize: 16, color: kFg3),
                  ),

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _isAuthenticating ? null : _authenticate,
                      icon: _isAuthenticating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kFgOnCyan,
                              ),
                            )
                          : const Icon(Icons.fingerprint),
                      label: Text(
                        _isAuthenticating ? 'กำลังยืนยัน...' : 'สแกนลายนิ้วมือ / ใบหน้า',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: kCrystal400,
                        foregroundColor: kFgOnCyan,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kR3),
                        ),
                      ),
                    ),
                  ),

                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kErr.withAlpha(20),
                        borderRadius: BorderRadius.circular(kR2),
                        border: Border.all(color: kErr.withAlpha(100)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: kErr, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: const TextStyle(color: kErr, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (kDebugMode) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () {
                        debugPrint('⚠️ DEV MODE: Skipping biometric authentication');
                        widget.onAuthenticated();
                      },
                      icon: const Icon(Icons.bug_report, size: 18),
                      label: const Text('ข้าม (โหมดพัฒนา)'),
                      style: TextButton.styleFrom(foregroundColor: kWarn),
                    ),
                  ],

                  const Spacer(),

                  if (widget.showCancel)
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'ยกเลิก',
                        style: TextStyle(color: kFg3),
                      ),
                    ),

                  const Text(
                    'ข้อมูลของคุณถูกเข้ารหัสและเก็บบนเครื่องนี้เท่านั้น',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: kFg4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
}
