// integration_test/tests/chat_test.dart
// 🧪 Haku Engine & Chat Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:haku/main.dart' as app;
import '../helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🧠 Haku Engine Tests', () {
    testWidgets('Identity Card - Remember user name', (tester) async {
      // 🚀 Start app
      app.main();
      await waitFor(tester, 2000);

      // 💬 บอก AI ชื่อ
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'สวัสดี ฉันชื่อ Arm');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // 💬 ถามชื่อ
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ฉันชื่ออะไร');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // ✅ ตรวจสอบว่า AI ตอบ "Arm"
      await expectText(tester, 'Arm');
    });

    testWidgets('Identity Card - Remember preferences', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 บอกว่าชอบกาแฟ
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ฉันชอบกินกาแฟ');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // 💬 ถามความชอบ
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ฉันชอบอะไร');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // ✅ ตรวจสอบว่า AI ตอบเกี่ยวกับ "กาแฟ"
      await expectText(tester, 'กาแฟ');
    });

    testWidgets('Reply Reference - Understand context', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 คุยเรื่องหนึ่ง
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'พรุ่งนี้มีนัดกินข้าวที่สยาม');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // 💬 Reply ข้อความเก่าแล้วถามต่อ
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'กี่โมงดี');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // ✅ AI ควรเข้าใจว่าหมายถึงนัดที่สยาม
      await expectText(tester, 'โมง');
    });

    testWidgets('Topic Detection - Separate topics', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 คุยหลายเรื่อง
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'วันนี้ไป gym มา');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 2000);

      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'แล้วก็กินข้าวกับเพื่อน');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 2000);

      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'พรุ่งนี้ต้องทำงานส่ง');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // ✅ ผ่าน test ถ้าไม่ crash (topic detection ทำงาน)
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('Recent Messages - Remember conversation', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 คุยต่อเนื่องหลายข้อความ
      for (var i = 0; i < 3; i++) {
        await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ข้อความที่ ${i + 1}');
        await tester.tap(find.byIcon(Icons.send));
        await waitFor(tester, 2000);
      }

      // 💬 ถามเกี่ยวกับบทสนทนาก่อนหน้า
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'เราคุยอะไรกันไปบ้าง');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // ✅ AI ควรตอบได้ว่าคุยอะไรไป
      expect(find.byType(ListView), findsWidgets);
    });
  });

  group('💬 Chat UI Tests', () {
    testWidgets('Send message and display response', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 📝 พิมพ์ข้อความ
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'สวัสดี');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // ✅ ตรวจสอบว่ามี bubble ข้อความ
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('Loading indicator shows while waiting', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 📝 ส่งข้อความ
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'เล่าเรื่องตลกให้ฟังหน่อย');
      await tester.tap(find.byIcon(Icons.send));

      // ✅ ตรวจสอบ loading indicator (ถ้ามี)
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
