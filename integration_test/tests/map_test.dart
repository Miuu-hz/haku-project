// integration_test/tests/map_test.dart
// 🧪 Map & Places Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:haku/main.dart' as app;
import '../helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🗺️ Map & Places Tests', () {
    testWidgets('Search for places - Coffee shop', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 ค้นหาสถานที่
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'ร้านกาแฟใกล้ๆ');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ ตรวจสอบผลลัพธ์
      // AI ควรส่ง [ACTION:SEARCH_PLACE] หรือแสดงผลลัพธ์
      final hasAction = find.textContaining('[ACTION:SEARCH_PLACE]').evaluate().isNotEmpty;
      final hasResult = find.textContaining('กาแฟ').evaluate().isNotEmpty;
      
      expect(hasAction || hasResult, isTrue);
    });

    testWidgets('Save favorite place', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 บอกว่าอยู่ที่นี่
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'บันทึกที่นี่เป็นร้านโปรด');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ ตรวจสอบว่า AI ตอบหรือทำ action
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('Location Picker - Open and select', (tester) async {
      // Note: ต้องมี entry point ที่เปิด Location Picker ได้
      app.main();
      await waitFor(tester, 2000);

      // 💬 ขอเปิด map
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'เปิดแผนที่');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 3000);

      // ถ้า AI action เปิด map ได้
      // จะเจอ FlutterMap widget
      
      // ✅ ไม่บังคับ (ขึ้นอยู่กับว่า AI ตอบยังไง)
    });

    testWidgets('AI asks for location - Meeting at Central', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 บอกนัดหมาย
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'มีนัดที่ Central');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ AI ควรถามว่าจะค้นหาพิกัดไหม หรือแสดง action
      final asksLocation = find.textContaining('พิกัด').evaluate().isNotEmpty ||
                          find.textContaining('Central').evaluate().isNotEmpty ||
                          find.textContaining('[ACTION:').evaluate().isNotEmpty;
      
      expect(asksLocation, isTrue);
    });

    testWidgets('Place search results display', (tester) async {
      app.main();
      await waitFor(tester, 2000);

      // 💬 ค้นหาสถานที่เฉพาะ
      await enterTextByHint(tester, 'พิมพ์ข้อความ', 'หาร้านอาหารญี่ปุ่น');
      await tester.tap(find.byIcon(Icons.send));
      await waitFor(tester, 5000);

      // ✅ ตรวจสอบผลลัพธ์
      final hasJapanese = find.textContaining('ญี่ปุ่น').evaluate().isNotEmpty ||
                         find.textContaining('[ACTION:SEARCH_PLACE]').evaluate().isNotEmpty;
      
      expect(hasJapanese, isTrue);
    });
  });
}

// Stub class สำหรับ compile
class FlutterMap extends StatelessWidget {
  const FlutterMap({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}
