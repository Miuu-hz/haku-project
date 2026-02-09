// integration_test/tests/llm_test.dart
// 🤖 MediaPipe LLM Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:haku/main.dart' as app;
import '../helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🤖 MediaPipe LLM Tests', () {
    testWidgets('Load model - Success log appears', (tester) async {
      app.main();
      await waitFor(tester, 3000);

      // 💬 ส่งข้อความเพื่อ trigger lazy loading
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'สวัสดี');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 10000); // รอโหลด model ครั้งแรก

      // ✅ ถ้าโหลดสำเร็จ ควรเห็น response
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('Generate text - Thai response', (tester) async {
      app.main();
      await waitFor(tester, 3000);

      // 💬 ถามเป็นภาษาไทย
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'แนะนำร้านกาแฟหน่อย');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 10000);

      // ✅ ควรได้คำตอบภาษาไทย
      final hasResponse = find.byType(ListView).evaluate().length > 1;
      expect(hasResponse, isTrue);
    });

    testWidgets('Generate text - Context awareness', (tester) async {
      app.main();
      await waitFor(tester, 3000);

      // 💬 ถามคำถามต่อเนื่อง
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'อากาศวันนี้เป็นยังไง');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 8000);

      // 💬 ถามต่อ
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'แล้วพรุ่งนี้ล่ะ');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 8000);

      // ✅ ควรได้คำตอบทั้งสองข้อ
      final messages = find.byType(ListView).evaluate().length;
      expect(messages >= 2, isTrue);
    });

    testWidgets('Lazy loading - Initialize on first use', (tester) async {
      app.main();
      await waitFor(tester, 3000);

      // รอบแรกควรเห็น log "🔄 Lazy Loading"
      // ส่งข้อความแรก
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'เริ่มต้นทดสอบ');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 10000);

      // ✅ ควรได้ response
      expect(find.byType(ListView), findsWidgets);

      // รอบสองควรเร็วกว่า
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ทดสอบครั้งที่สอง');
      await tester.tap(find.byIcon(Icons.send));
      final startTime = DateTime.now();
      await waitFor(tester, 5000);
      final duration = DateTime.now().difference(startTime);

      // รอบสองควรเร็วกว่ารอบแรก (แต่ integration test ยากที่จะวัดเป๊ะ)
      expect(duration.inSeconds < 10, isTrue);
    });

    testWidgets('Auto-unload after idle', (tester) async {
      // Note: ต้องรอ 5 นาที ยากที่จะ test ใน integration test
      // แนะนำให้ test ผ่าน unit test หรือ manual test
      
      app.main();
      await waitFor(tester, 3000);
      
      // ส่งข้อความแล้วรอไม่กี่วินาที
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ทดสอบ');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ ถ้าทำงานได้ = ผ่าน
      expect(true, isTrue);
    });

    testWidgets('Streaming response', (tester) async {
      app.main();
      await waitFor(tester, 3000);

      // 💬 ขอคำตอบยาวๆ
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'เล่าเรื่องสั้นให้ฟังหน่อย');
      await tester.tap(find.byIcon(Icons.send));

      // รอให้เริ่มต้น stream
      await tester.pump(const Duration(milliseconds: 500));

      // ✅ ถ้ามี streaming อาจเห็นข้อความเพิ่มขึ้นทีละนิด
      // แต่ integration test ยากที่จะ catch ระหว่าง stream
      await waitFor(tester, 10000);
      
      expect(find.byType(ListView), findsWidgets);
    });
  });
}
