import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/entry.dart';
import 'database_helper.dart';

/// 🤖 AI Service - จัดการการตอบคำถามจาก AI
/// 
/// Phase 1: ใช้ Mock Responses (ตอบแบบสุ่ม)
/// Phase 2: จะเชื่อมต่อกับ Local LLM (Phi-4/Gemma)

class AIService {
  /// 📝 Mock responses สำหรับ demo
  static final Map<String, List<String>> _mockResponses = {
    'eat': [
      'วันนี้คุณกินข้าวผัดกุ้งตอนเที่ยง และกินราเมนตอนเย็นค่ะ 🍜 ดูอร่อยมากเลย!',
      'จากบันทึก วันนี้คุณมีมื้อเที่ยงที่ร้านอาหารใกล้บ้าน และดื่มชาเขียวตอนบ่ายค่ะ 🍵',
      'วันนี้คุณกินข้าวต้มมัดกับกาแฟตอนเช้า และไปกินบุฟเฟ่ต์มื้อเย็นค่ะ 🍽️',
    ],
    'feel': [
      'วันนี้อารมณ์ของคุณดีมากเลยค่ะ 😊 มีบันทึกที่บอกว่ารู้สึกมีความสุขและ productive',
      'ดูเหมือนวันนี้จะเหนื่อยหน่อยนะคะ 😅 แต่คุณก็ผ่านมันไปได้ดี!',
      'อารมณ์โดยรวมดีค่ะ ✨ มีทั้งช่วงตื่นเต้นและช่วงผ่อนคลาย',
    ],
    'where': [
      'วันนี้คุณไป Central World และสวนลุมพินีค่ะ 📍 ดูเหมือนจะเป็นการเที่ยวแบบชิลๆ',
      'จากพิกัด คุณอยู่ที่บ้านตอนเช้า และไปทำงานที่ออฟฟิศตอนบ่ายค่ะ 🏢',
      'วันนี้คุณไปร้านกาแฟย่านอารีย์ และไปเที่ยวห้างตอนเย็นค่ะ ☕',
    ],
    'yesterday': [
      'เมื่อวานคุณทำงานที่ออฟฟิศทั้งวัน และไปออกกำลังกายตอนเย็นค่ะ 💪',
      'เมื่อวานคุณมีประชุมสำคัญ และไปกินข้าวกับเพื่อนหลังเลิกงานค่ะ 🍻',
      'เมื่อวานเป็นวันพักผ่อน คุณนอนดูซีรีส์และทำอาหารกินเองค่ะ 🍳',
    ],
    'default': [
      'ขอโทษค่ะ ฮาคุยังไม่เข้าใจคำถามนี้ดีพอ 😅 ลองถามใหม่ได้ไหมคะ?',
      'น่าสนใจค่ะ! แต่ฮาคุยังไม่มีข้อมูลเกี่ยวกับเรื่องนี้',
      'ฮาคุกำลังเรียนรู้ค่ะ 🌱 ลองถามเป็นประโยคสั้นๆ ได้ไหมคะ?',
    ],
  };

  /// 💬 รับข้อความและคืนคำตอบแบบ Mock
  /// 
  /// ตรวจจับ intent จาก keyword แล้วตอบแบบสุ่ม
  static Future<String> getMockResponse(String userMessage) async {
    final message = userMessage.toLowerCase();
    
    // ⏳ จำลองความล่าช้าของ AI
    await Future<void>.delayed(const Duration(milliseconds: 800));
    
    // 🔍 ตรวจจับ intent
    if (message.contains('กิน') || message.contains('อาหาร') || message.contains('ทาน')) {
      return _getRandomResponse('eat');
    }
    
    if (message.contains('รู้สึก') || message.contains('อารมณ์') || message.contains('เป็นยังไง')) {
      return _getRandomResponse('feel');
    }
    
    if (message.contains('ไป') || message.contains('ที่ไหน') || message.contains('อยู่')) {
      return _getRandomResponse('where');
    }
    
    if (message.contains('เมื่อวาน') || message.contains('พรุ่งนี้')) {
      return _getRandomResponse('yesterday');
    }
    
    // 📝 ถ้าถามเกี่ยวกับวันนี้ ให้ดึงข้อมูลจริงจาก database
    if (message.contains('วันนี้') || message.contains('ทำอะไร')) {
      return _getTodaySummaryInternal();
    }
    
    return _getRandomResponse('default');
  }

  /// 🎲 สุ่มคำตอบจาก category
  static String _getRandomResponse(String category) {
    final responses = _mockResponses[category] ?? _mockResponses['default']!;
    final random = Random();
    return responses[random.nextInt(responses.length)];
  }

  /// 📅 ดึงสรุปวันนี้จาก Database จริง
  static Future<String> getTodaySummary() async => _getTodaySummaryInternal();

  static Future<String> _getTodaySummaryInternal() async {
    try {
      debugPrint('🔄 _getTodaySummaryInternal called');
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      debugPrint('📅 Date range: $startOfDay - $endOfDay');
      
      // ดึง entries วันนี้ทั้งหมด
      final allEntries = await DatabaseHelper.instance.getAllEntries();
      final todayEntries = allEntries.where((e) => 
        e.createdAt.isAfter(startOfDay) && e.createdAt.isBefore(endOfDay)
      ).toList();

      if (todayEntries.isEmpty) {
        return 'วันนี้คุณยังไม่มีบันทึกเลยค่ะ 📝 ลองเขียนบันทึกสักหน่อยไหม?';
      }

      // นับจำนวนและสรุป
      final count = todayEntries.length;
      final hasLocation = todayEntries.any((e) => e.latitude != null);
      final hasMood = todayEntries.any((e) => e.mood != null);
      
      String moodText = '';
      if (hasMood) {
        final avgMood = todayEntries
            .where((e) => e.mood != null)
            .map((e) => e.mood!)
            .reduce((a, b) => a + b) / 
            todayEntries.where((e) => e.mood != null).length;
        
        if (avgMood >= 4) {
          moodText = 'และดูเหมือนคุณจะมีความสุขมากค่ะ 😊';
        } else if (avgMood <= 2) {
          moodText = 'ดูเหมือนวันนี้จะเหนื่อยหน่อยนะคะ สู้ๆ ค่ะ 💪';
        } else {
          moodText = 'อารมณ์โดยรวมดูสบายๆ ค่ะ 😌';
        }
      }

      return 'วันนี้คุณมี $count บันทึก${hasLocation ? ' และไปหลายที่เลยค่ะ' : ''} $moodText';
    } catch (e) {
      return 'ขอโทษค่ะ ฮาคุดึงข้อมูลไม่ได้ตอนนี้ 😅';
    }
  }

  /// 🔍 Semantic Search (เตรียมไว้ Phase 2)
  /// 
  /// จะใช้ sqlite-vec สำหรับค้นหาความหมาย
  static Future<List<Entry>> semanticSearch(String query) async {
    // TODO: Phase 2 - Implement with sqlite-vec
    // 1. แปลง query เป็น vector
    // 2. ค้นหาใน vector database
    // 3. คืนค่า entries ที่ใกล้เคียง
    return [];
  }

  /// 🧠 Generate embedding (เตรียมไว้ Phase 2)
  /// 
  /// ใช้โมเดลขนาดเล็ก (all-MiniLM-L6-v2 หรือ bge-small)
  static Future<List<double>> generateEmbedding(String text) async {
    // TODO: Phase 2 - Load ONNX model via flutter_onnx
    return [];
  }
}
