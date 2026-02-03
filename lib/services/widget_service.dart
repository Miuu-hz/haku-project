import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// 📱 Widget Service - สื่อสารกับ Android Widgets
/// 
/// ใช้ MethodChannel เพื่อส่งข้อมูลไปให้ Native Android Widgets

class WidgetService {
  static const MethodChannel _channel = MethodChannel('com.example.haku/widget');

  /// 📤 ขอข้อมูล action จาก widget (ถ้ามี)
  /// 
  /// คืนค่า Map ที่มี:
  /// - action: 'chat' | 'new_entry' | 'ask'
  /// - question: คำถาม (ถ้า action เป็น 'ask')
  static Future<Map<String, dynamic>?> getWidgetAction() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getWidgetAction');
      if (result == null) return null;
      return result.cast<String, dynamic>();
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Error getting widget action: ${e.message}');
      }
      return null;
    }
  }

  /// 🔄 บังคับให้ widget อัพเดท
  static Future<void> updateWidget() async {
    try {
      await _channel.invokeMethod('updateWidget');
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Error updating widget: ${e.message}');
      }
    }
  }

  /// 📝 ส่งข้อมูลล่าสุดไปให้ widget แสดง
  /// 
  /// [lastEntry] - ข้อความบันทึกล่าสุด
  /// [lastAiResponse] - คำตอบล่าสุดจาก AI
  static Future<void> updateWidgetData({
    String? lastEntry,
    String? lastAiResponse,
  }) async {
    try {
      await _channel.invokeMethod('updateWidgetData', {
        'lastEntry': lastEntry,
        'lastAiResponse': lastAiResponse,
      });
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Error updating widget data: ${e.message}');
      }
    }
  }
}
