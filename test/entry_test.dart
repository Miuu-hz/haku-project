import 'package:flutter_test/flutter_test.dart';
import 'package:haku/models/entry.dart';

/// 🧪 Unit Tests สำหรับ Entry Model

void main() {
  group('Entry Model Tests', () {
    
    test('📝 สร้าง Entry ด้วยข้อมูลปกติ', () {
      final entry = Entry(
        id: 1,
        content: 'วันนี้อากาศดี #happy',
        createdAt: DateTime(2026, 1, 29, 10, 30),
        mood: 4,
      );

      expect(entry.id, equals(1));
      expect(entry.content, equals('วันนี้อากาศดี #happy'));
      expect(entry.mood, equals(4));
      expect(entry.tags, isEmpty);  // tags ว่างตอนสร้าง
    });

    test('🏷️ ดึง hashtag จาก content', () {
      const content = 'วันนี้ทำงาน #work #coding สนุกมาก #happy';
      final tags = Entry.extractTags(content);

      expect(tags, equals(['work', 'coding', 'happy']));
    });

    test('🏷️ ดึง hashtag ไม่เจอ (content ปกติ)', () {
      const content = 'วันนี้ทำงานเหนื่อยมาก';
      final tags = Entry.extractTags(content);

      expect(tags, isEmpty);
    });

    test('😊 แปลง mood เป็นข้อมูลที่ถูกต้อง', () {
      final happy = Entry.getMoodInfo(5);
      expect(happy['emoji'], equals('😄'));
      expect(happy['label'], equals('ดีมาก'));

      final sad = Entry.getMoodInfo(1);
      expect(sad['emoji'], equals('😢'));
      expect(sad['label'], equals('แย่มาก'));

      final unknown = Entry.getMoodInfo(null);
      expect(unknown['emoji'], equals('📝'));
      expect(unknown['label'], equals('ไม่ระบุ'));
    });

    test('🔄 Entry toMap และ fromMap ต้องตรงกัน', () {
      final original = Entry(
        id: 5,
        content: 'ทดสอบการแปลงข้อมูล',
        createdAt: DateTime(2026, 1, 29, 15, 0),
        latitude: 13.7563,
        longitude: 100.5018,
        locationName: 'กรุงเทพฯ',
        mood: 4,
        tags: ['test', 'flutter'],
      );

      final map = original.toMap();
      final restored = Entry.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.content, equals(original.content));
      expect(restored.latitude, equals(original.latitude));
      expect(restored.longitude, equals(original.longitude));
      expect(restored.mood, equals(original.mood));
    });

    test('🔄 copyWith ต้องทำงานถูกต้อง', () {
      final original = Entry(
        content: 'เดิม',
        createdAt: DateTime.now(),
        mood: 3,
      );

      final updated = original.copyWith(
        content: 'ใหม่',
        mood: 5,
      );

      expect(updated.content, equals('ใหม่'));
      expect(updated.mood, equals(5));
      // ส่วนอื่นต้องเหมือนเดิม
      expect(updated.createdAt, equals(original.createdAt));
    });

    test('🎵 MediaType enum ต้องมีค่าถูกต้อง', () {
      expect(MediaType.none.index, equals(0));
      expect(MediaType.image.index, equals(1));
      expect(MediaType.audio.index, equals(2));
    });
  });
}
