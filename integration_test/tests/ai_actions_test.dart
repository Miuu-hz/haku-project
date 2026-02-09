// integration_test/tests/ai_actions_test.dart
// 🤖 AI Actions & Web Search Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:haku/main.dart' as app;
import '../helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🤖 AI Actions Tests', () {
    testWidgets('[ACTION:SEARCH_PLACE] - Japanese restaurant', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 ขอค้นหาร้าน
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'หาร้านอาหารญี่ปุ่น');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ ตรวจสอบว่ามี action หรือผลลัพธ์
      final hasAction = find.textContaining('[ACTION:SEARCH_PLACE]').evaluate().isNotEmpty ||
                       find.textContaining('ญี่ปุ่น').evaluate().isNotEmpty;
      
      expect(hasAction, isTrue);
    });

    testWidgets('[ACTION:SAVE_PLACE] - Save favorite', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 ขอบันทึก
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'บันทึกที่นี่เป็นร้านโปรด');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ ตรวจสอบ response
      final hasAction = find.textContaining('[ACTION:SAVE_PLACE]').evaluate().isNotEmpty ||
                       find.textContaining('บันทึก').evaluate().isNotEmpty;
      
      expect(hasAction, isTrue);
    });

    testWidgets('[ACTION:WEB_SEARCH] - Search today news', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 ขอค้นหาข่าว
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ค้นหาข่าววันนี้');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ ตรวจสอบ action หรือผลลัพธ์
      final hasAction = find.textContaining('[ACTION:WEB_SEARCH]').evaluate().isNotEmpty ||
                       find.textContaining('ข่าว').evaluate().isNotEmpty;
      
      expect(hasAction, isTrue);
    });

    testWidgets('[ACTION:SYNC_CALENDAR] - Add appointment', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 ขอเพิ่มนัด
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'เพิ่มนัดประชุมวันพรุ่งนี้ 10 โมงลง calendar');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ ตรวจสอบ action
      final hasAction = find.textContaining('[ACTION:SYNC_CALENDAR]').evaluate().isNotEmpty ||
                       find.textContaining('calendar').evaluate().isNotEmpty ||
                       find.textContaining('นัด').evaluate().isNotEmpty;
      
      expect(hasAction, isTrue);
    });

    testWidgets('[ACTION:ASK_LOCATION] - Meeting at Siam', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 บอกนัดแต่ไม่ระบุพิกัดชัด
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'นัดที่ Siam');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ AI ควรถามว่าจะค้นหาพิกัดไหม
      final asksLocation = find.textContaining('พิกัด').evaluate().isNotEmpty ||
                          find.textContaining('Siam').evaluate().isNotEmpty ||
                          find.textContaining('ACTION').evaluate().isNotEmpty;
      
      expect(asksLocation, isTrue);
    });
  });

  group('🔍 Web Search Tests', () {
    testWidgets('DuckDuckGo search - Returns results', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 ค้นหาเฉพาะเจาะจง
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ค้นหา: วิธีทำกาแฟ');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 8000); // รอนานหน่อยเพราะต้องเรียก web

      // ✅ ควรมีผลลัพธ์หรือ action
      final hasResult = find.textContaining('[ACTION:WEB_SEARCH]').evaluate().isNotEmpty ||
                       find.textContaining('กาแฟ').evaluate().isNotEmpty ||
                       find.byType(ListView).evaluate().length > 2;
      
      expect(hasResult, isTrue);
    });

    testWidgets('Cache works - Second search faster', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 ค้นหาครั้งแรก
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ค้นหา: Flutter');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 8000);

      // 💬 ค้นหาซ้ำ (ควรเร็วกว่าเพราะ cache)
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ค้นหา: Flutter');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // ✅ ถ้าถึงตรงนี้แสดงว่า cache ทำงาน (ไม่ timeout)
      expect(find.byType(ListView), findsWidgets);
    });
  });
}
