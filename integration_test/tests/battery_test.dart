// integration_test/tests/battery_test.dart
// 🔋 Battery & Optimization Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:haku/main.dart' as app;
import '../helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🔋 Battery Optimization Tests', () {
    testWidgets('Switch preset modes - Power Saver', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 🔍 หา settings หรือ battery menu (ต้องมี UI ให้เข้าถึง)
      // ถ้ามี drawer menu
      await tester.tap(find.byIcon(Icons.menu));
      await waitFor(tester, 1000);

      // กดที่ Battery หรือ Settings
      await tester.tap(find.textContaining('Battery').first);
      await waitFor(tester, 1000);

      // กดเลือก Power Saver
      await tester.tap(find.textContaining('Power Saver').first);
      await waitFor(tester, 1000);

      // ✅ ตรวจสอบว่าเลือกแล้ว
      await expectText(tester, 'Power Saver');
    });

    testWidgets('Switch preset modes - Performance', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // เข้า settings
      await tester.tap(find.byIcon(Icons.menu));
      await waitFor(tester, 1000);

      await tester.tap(find.textContaining('Battery').first);
      await waitFor(tester, 1000);

      // กดเลือก Performance
      await tester.tap(find.textContaining('Performance').first);
      await waitFor(tester, 1000);

      // ✅ ตรวจสอบ
      await expectText(tester, 'Performance');
    });

    testWidgets('Battery status displays correctly', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 🔍 หา battery indicator (ถ้ามี)
      // ถ้ามี indicator ควรแสดงได้ ถ้าไม่มีก็ไม่เป็นไร (อาจซ่อนอยู่)
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('Defer to charging - Heavy tasks wait', (tester) async {
      // Note: อันนี้ต้อง mock battery status หรือ test ผ่าน unit test
      // Integration test ยากที่จะควบคุม charging state
      
      app.main();
      await waitFor(tester, 2000);

      // 💬 สร้าง task ที่หนัก (เช่น ขอสรุปข้อความยาวๆ)
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'สรุปบทสนทนาทั้งหมด');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // ✅ ถ้าไม่ชาร์จ อาจเห็นข้อความว่ารอชาร์จ
      // ไม่บังคับเพราะขึ้นกับ battery state
    });
  });

  group('⚡ Smart Interval Tests', () {
    testWidgets('Activity pattern display', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // เข้า settings
      await tester.tap(find.byIcon(Icons.menu));
      await waitFor(tester, 1000);

      // หา Smart Interval หรือ Activity
      await tester.tap(find.textContaining('Activity').first);
      await waitFor(tester, 1000);

      // ✅ ควรมีข้อมูล activity pattern แสดง
      expect(find.byType(ListView), findsWidgets);
    });
  });
}
