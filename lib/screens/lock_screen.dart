import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/biometric_service.dart';

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
    
    // ลองสแกนอัตโนมัติตอนเปิดหน้า
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
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              
              // 🔐 Icon Animation
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) => Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: const [
                          Color(0xFF9B7CB6),
                          Color(0xFF6B4E71),
                        ],
                        transform: GradientRotation(
                          _animationController.value * 2 * 3.14159,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(60),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF9B7CB6).withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.fingerprint,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ),
              
              const SizedBox(height: 40),
              
              // ข้อความ
              const Text(
                'Haku ถูกล็อก',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 12),
              
              Text(
                'ยืนยันตัวตนเพื่อเข้าใช้งาน',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              
              const SizedBox(height: 40),
              
              // ปุ่มสแกน
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
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.fingerprint),
                  label: Text(_isAuthenticating ? 'กำลังยืนยัน...' : 'สแกนลายนิ้วมือ / ใบหน้า'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF9B7CB6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              
              // ข้อความ error
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              // 🔓 ปุ่มข้ามสำหรับ Development (TODO: เอาออกใน production)
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  // ignore: avoid_print
                  print('⚠️ DEV MODE: Skipping biometric authentication');
                  widget.onAuthenticated();
                },
                icon: const Icon(Icons.bug_report, size: 18),
                label: const Text('ข้าม (โหมดพัฒนา)'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orange.withValues(alpha: 0.8),
                ),
              ),
              
              const Spacer(),
              
              // ปุ่มยกเลิก (ถ้ามี)
              if (widget.showCancel)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'ยกเลิก',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
              
              // ข้อความด้านล่าง
              Text(
                'ข้อมูลของคุณถูกเข้ารหัสและเก็บบนเครื่องนี้เท่านั้น',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
}
