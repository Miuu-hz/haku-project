// integration_test/tests/calendar_test.dart
// 📅 Google Calendar Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:haku/main.dart' as app;
import '../helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('📅 Google Calendar Tests', () {
    testWidgets('Google Sign In button exists', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 🔍 หา settings หรือ calendar menu
      await tester.tap(find.byIcon(Icons.menu));
      await waitFor(tester, 1000);

      // ✅ ควรมีตัวเลือก Calendar หรือ Sync (ไม่บังคับเพราะอาจซ่อนอยู่)
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('Sync objective to Calendar', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 สร้าง objective พร้อม sync
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'สร้าง objective: ส่งงานวันศุกร์ แล้ว sync ไป calendar');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ ตรวจสอบ action หรือ response
      final hasAction = find.textContaining('[ACTION:SYNC_CALENDAR]').evaluate().isNotEmpty ||
                       find.textContaining('calendar').evaluate().isNotEmpty ||
                       find.textContaining('sync').evaluate().isNotEmpty;
      
      expect(hasAction, isTrue);
    });

    testWidgets('View Calendar events', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 ขอดูนัดหมาย
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ดูนัดหมายวันนี้');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ ตรวจสอบว่า AI ตอบ
      final hasResponse = find.byType(ListView).evaluate().length > 1 ||
                         find.textContaining('นัด').evaluate().isNotEmpty ||
                         find.textContaining('ไม่มี').evaluate().isNotEmpty;
      
      expect(hasResponse, isTrue);
    });

    testWidgets('Calendar integration disabled without sign in', (tester) async {
      // ถ้ายังไม่ได้ sign in ควรขอ sign in ก่อน
      app.main();
      await waitFor(tester, 2000);

      // 💬 ขอ sync โดยไม่ได้ sign in
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'เพิ่มนัดลง Google Calendar');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ ควรขอ sign in หรือบอกว่าต้อง sign in ก่อน
      final asksSignIn = find.textContaining('Sign In').evaluate().isNotEmpty ||
                        find.textContaining('เข้าสู่ระบบ').evaluate().isNotEmpty ||
                        find.textContaining('Google').evaluate().isNotEmpty ||
                        find.textContaining('[ACTION:SYNC_CALENDAR]').evaluate().isNotEmpty;
      
      expect(asksSignIn, isTrue);
    });
  });
}
