// integration_test/helpers/test_helpers.dart
// 🧪 Helper functions สำหรับ Integration Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ⏱️ Wait สำหรับ animation/loading จบ
Future<void> waitFor(WidgetTester tester, [int milliseconds = 500]) async {
  await tester.pumpAndSettle(Duration(milliseconds: milliseconds));
}

/// 🔍 หา widget โดย text แล้ว tap
Future<void> tapByText(WidgetTester tester, String text) async {
  await tester.tap(find.textContaining(text));
  await tester.pumpAndSettle();
}

/// 🔍 หา widget โดย key แล้ว tap
Future<void> tapByKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// 📝 พิมพ์ข้อความลง TextField
Future<void> enterTextByHint(WidgetTester tester, String hint, String text) async {
  await tester.enterText(find.byWidgetPredicate((widget) {
    if (widget is TextField) {
      final decoration = widget.decoration;
      return decoration?.hintText?.contains(hint) ?? false;
    }
    return false;
  }), text);
  await tester.pumpAndSettle();
}

/// 📝 พิมพ์ข้อความลง TextField โดย key
Future<void> enterTextByKey(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pumpAndSettle();
}

/// ✅ ตรวจสอบว่ามีข้อความปรากฏบนหน้าจอ
Future<void> expectText(WidgetTester tester, String text) async {
  expect(find.textContaining(text), findsOneWidget);
}

/// ✅ ตรวจสอบว่ามีข้อความไม่ปรากฏ
Future<void> expectNoText(WidgetTester tester, String text) async {
  expect(find.textContaining(text), findsNothing);
}

/// ⏳ รอจนกว่าข้อความจะปรากฏ (timeout 10 วินาที)
Future<void> waitForText(WidgetTester tester, String text, [int timeoutSeconds = 10]) async {
  final endTime = DateTime.now().add(Duration(seconds: timeoutSeconds));
  while (DateTime.now().isBefore(endTime)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.textContaining(text).evaluate().isNotEmpty) {
      return;
    }
  }
  throw Exception('Timeout: Text "$text" not found after $timeoutSeconds seconds');
}

/// 🔄 Scroll จนเจอข้อความ
Future<void> scrollUntilVisible(
  WidgetTester tester,
  String text, {
  String scrollableKey = 'scrollable',
}) async {
  await tester.scrollUntilVisible(
    find.textContaining(text),
    100,
    scrollable: find.byKey(Key(scrollableKey)),
  );
  await tester.pumpAndSettle();
}

/// 📸 Take screenshot (สำหรับ debugging)
Future<void> takeScreenshot(WidgetTester tester, String name) async {
  // ใช้ใน CI/CD หรือ debugging
  await tester.pumpAndSettle();
}

/// 🤖 Mock function สำหรับ AI response
Future<void> mockAIResponse(String response) async {
  // ใช้ร่วมกับ mockito หรือ fake services
}

/// 🔋 Mock battery status (ต้องใช้ method channel mocking)
Future<void> mockBatteryLevel(int level) async {
  // ใช้ TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
}

/// 📱 Test device sizes
class TestDevices {
  static const Size phone = Size(375, 812); // iPhone X
  static const Size tablet = Size(768, 1024); // iPad
  static const Size smallPhone = Size(320, 568); // iPhone SE
}
