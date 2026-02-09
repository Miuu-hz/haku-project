# 🧪 Haku Integration Tests

Integration tests สำหรับทดสอบ Haku App แบบ end-to-end

## 📁 โครงสร้าง

```
integration_test/
├── app_test.dart              # Main test runner
├── helpers/
│   └── test_helpers.dart      # Helper functions
├── tests/
│   ├── chat_test.dart         # Haku Engine & Chat tests
│   ├── map_test.dart          # Map & Places tests
│   ├── battery_test.dart      # Battery optimization tests
│   ├── ai_actions_test.dart   # AI Actions & Web Search tests
│   ├── calendar_test.dart     # Google Calendar tests
│   └── llm_test.dart          # MediaPipe LLM tests
└── README.md                  # This file
```

## 🚀 วิธีรัน Tests

### 1. ติดตั้ง dependencies
```bash
flutter pub get
```

### 2. เชื่อมต่ออุปกรณ์
- ต่อมือถือ Android หรือเปิด Emulator
- ตรวจสอบด้วย: `flutter devices`

### 3. รันทุก tests
```bash
flutter test integration_test/app_test.dart
```

### 4. รันเฉพาะบาง test file
```bash
# เฉพาะ Chat tests
flutter test integration_test/tests/chat_test.dart

# เฉพาะ Map tests  
flutter test integration_test/tests/map_test.dart

# เฉพาะ AI Actions
flutter test integration_test/tests/ai_actions_test.dart
```

### 5. รันผ่าน Windows Script
```bash
scripts\run_integration_tests.bat
```

## 📝 Test Coverage

### 🧠 Chat & Haku Engine
- ✅ Identity Card - Remember user name
- ✅ Identity Card - Remember preferences  
- ✅ Reply Reference - Understand context
- ✅ Topic Detection - Separate topics
- ✅ Recent Messages - Remember conversation

### 🗺️ Map & Places
- ✅ Search for places
- ✅ Save favorite place
- ✅ Location Picker
- ✅ AI asks for location

### 🔋 Battery
- ✅ Switch preset modes
- ✅ Battery status display
- ✅ Smart interval

### 🤖 AI Actions
- ✅ [ACTION:SEARCH_PLACE]
- ✅ [ACTION:SAVE_PLACE]
- ✅ [ACTION:WEB_SEARCH]
- ✅ [ACTION:SYNC_CALENDAR]
- ✅ [ACTION:ASK_LOCATION]

### 📅 Google Calendar
- ✅ Sign In button
- ✅ Sync objective
- ✅ View events

### 🤖 MediaPipe LLM
- ✅ Load model
- ✅ Generate Thai text
- ✅ Context awareness
- ✅ Lazy loading

## ⚠️ ข้อควรระวัง

1. **LLM Tests ใช้เวลานาน**: ต้องรอ model โหลด (10-30 วินาที)
2. **Web Search ต้องมี Internet**: ถ้าไม่มีเน็ตจะ fail
3. **Google Calendar ต้อง Sign In**: ถ้ายังไม่ sign in บาง test จะ skip
4. **Battery Tests ต้องมี UI**: ถ้าไม่มี menu ให้เข้าถึงจะ fail

## 🔧 Debugging

### ดู logs ขณะรัน test
```bash
flutter logs
```

### Take screenshots (ต้องเพิ่ม code)
```dart
await tester.pumpAndSettle();
// Screenshot จะถูกบันทึกอัตโนมัติใน CI/CD
```

### Run with verbose
```bash
flutter test integration_test/app_test.dart --verbose
```

## 🆕 เพิ่ม Test ใหม่

1. สร้างไฟล์ใน `integration_test/tests/`
2. Import ใน `integration_test/app_test.dart`
3. เรียก `main()` ของ test file นั้น

ตัวอย่าง:
```dart
// integration_test/tests/my_new_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:haku/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('My Feature Tests', () {
    testWidgets('Test something', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Your test code here
      expect(find.text('Hello'), findsOneWidget);
    });
  });
}
```

## 📚 Reference

- [Flutter Integration Testing](https://docs.flutter.dev/testing/integration-tests)
- [flutter_test package](https://api.flutter.dev/flutter/flutter_test/flutter_test-library.html)
