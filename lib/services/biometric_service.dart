import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_ios/local_auth_ios.dart';

/// 🔐 Biometric Service - จัดการล็อกด้วยลายนิ้วมือ/ใบหน้า
/// 
/// รองรับ:
/// - Android: Fingerprint, Face Unlock
/// - iOS: Face ID, Touch ID

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// ✅ ตรวจสอบว่าอุปกรณ์รองรับ Biometric หรือไม่
  static Future<bool> isDeviceSupported() async => _auth.isDeviceSupported();

  /// 🔍 ตรวจสอบว่ามี Biometric ลงทะเบียนไว้หรือไม่
  static Future<bool> canCheckBiometrics() async => _auth.canCheckBiometrics;

  /// 📋 ดึงรายการ Biometric ที่พร้อมใช้
  static Future<List<BiometricType>> getAvailableBiometrics() async => _auth.getAvailableBiometrics();

  /// 🔓 ขอสแกน Biometric เพื่อปลดล็อก
  /// 
  /// คืนค่า true = ผ่าน, false = ไม่ผ่าน/ยกเลิก
  static Future<bool> authenticate() async {
    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'ยืนยันตัวตนเพื่อเข้าใช้งาน Haku',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Haku - ยืนยันตัวตน',
            cancelButton: 'ยกเลิก',
            biometricHint: 'สแกนลายนิ้วมือ',
            biometricNotRecognized: 'ไม่รู้จัก ลองใหม่',
            biometricSuccess: 'สำเร็จ',
            deviceCredentialsRequiredTitle: 'ต้องการ PIN/Password',
            deviceCredentialsSetupDescription: 'โปรดตั้งค่า PIN หรือ Password',
            goToSettingsButton: 'ไปที่การตั้งค่า',
            goToSettingsDescription: 'โปรดตั้งค่าลายนิ้วมือในการตั้งค่าระบบ',
          ),
          IOSAuthMessages(
            cancelButton: 'ยกเลิก',
            goToSettingsButton: 'ไปที่การตั้งค่า',
            goToSettingsDescription: 'โปรดตั้งค่า Face ID/Touch ID ในการตั้งค่า',
            lockOut: 'กรุณาลองใหม่ภายหลัง',
          ),
        ],
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
          biometricOnly: false, // อนุญาตให้ใช้ PIN/Pattern/Password สำรอง
        ),
      );
      
      return didAuthenticate;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Biometric error: ${e.message}');
      }
      return false;
    }
  }

  /// 🔒 ตรวจสอบว่าควรแสดงหน้าล็อกหรือไม่
  /// 
  /// [lastActiveTime] - เวลาที่ใช้งานล่าสุด
  /// [lockAfterMinutes] - ล็อกหลังจากไม่ใช้งานกี่นาที
  static bool shouldLock(
    DateTime? lastActiveTime, {
    int lockAfterMinutes = 1,
  }) {
    if (lastActiveTime == null) return true;
    
    final diff = DateTime.now().difference(lastActiveTime);
    return diff.inMinutes >= lockAfterMinutes;
  }
}
