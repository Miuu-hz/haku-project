<<<<<<< HEAD
/// 📝 โมเดลข้อมูล Entry (บันทึกประจำวัน)
/// 
/// เก็บข้อมูลทั้งหมดของการบันทึกแต่ละครั้ง
/// รองรับหลายรูปแบบ: ข้อความ, เสียง, รูปภาพ, ตำแหน่ง
library;

class Entry {
  final int? id;                          // Primary Key (null ถ้ายังไม่บันทึก)
  final String content;                   // เนื้อหาข้อความ
  final DateTime createdAt;               // เวลาที่สร้าง
  final double? latitude;                 // พิกัดละติจูด (null ถ้าไม่มี)
  final double? longitude;                // พิกัดลองจิจูด (null ถ้าไม่มี)
  final String? locationName;             // ชื่อสถานที่ (เช่น "Central World")
  final String? mediaPath;                // Path ของไฟล์เสียง/รูปภาพ
  final MediaType mediaType;              // ประเภท media (none, image, audio)
  final int? mood;                        // อารมณ์ (1-5, null ถ้าไม่ได้ระบุ)
  final List<String> tags;                // แท็กที่ดึงมาจาก #hashtag
  
  const Entry({
    this.id,
    required this.content,
    required this.createdAt,
=======
/// 📝 Entry Model - บันทึกประจำวัน
///
/// เก็บข้อมูลบันทึกของผู้ใช้ รวมถึง:
/// - เนื้อหา (content)
/// - ตำแหน่ง (GPS coordinates + location name)
/// - รูปภาพ/วิดีโอ (media)
/// - อารมณ์ (mood)
/// - แท็ก (tags)

/// ประเภทสื่อที่แนบมากับบันทึก
enum MediaType {
  none,   // 0
  image,  // 1
  video,  // 2
  audio,  // 3
}

class Entry {
  final int? id;
  final String content;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final String? mediaPath;
  final MediaType mediaType;
  final int? mood; // 1-5 (1=แย่มาก, 5=ดีมาก)
  final List<String> tags;

  Entry({
    this.id,
    required this.content,
    DateTime? createdAt,
>>>>>>> 21c9be3c902c18aaa90280be22e4688dcc96c84b
    this.latitude,
    this.longitude,
    this.locationName,
    this.mediaPath,
    this.mediaType = MediaType.none,
    this.mood,
<<<<<<< HEAD
    this.tags = const [],
  });

  /// 🔄 แปลงจาก Map (ที่ได้จาก SQLite) เป็น Entry Object
  factory Entry.fromMap(Map<String, dynamic> map) => Entry(
      id: map['id'] as int?,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      locationName: map['location_name'] as String?,
      mediaPath: map['media_path'] as String?,
      mediaType: MediaType.values[map['media_type'] as int? ?? 0],
      mood: map['mood'] as int?,
      tags: (map['tags'] as String? ?? '').split(',').where((t) => t.isNotEmpty).toList(),
    );

  /// 🔄 แปลงจาก Entry Object เป็น Map (สำหรับบันทึกลง SQLite)
  Map<String, dynamic> toMap() => {
      'id': id,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'location_name': locationName,
      'media_path': mediaPath,
      'media_type': mediaType.index,
      'mood': mood,
      'tags': tags.join(','),
    };

  /// 🔍 สร้าง Entry ใหม่ที่มีข้อมูลบางส่วนเปลี่ยน (immutable pattern)
=======
    List<String>? tags,
  })  : createdAt = createdAt ?? DateTime.now(),
        tags = tags ?? [];

  /// สร้าง Entry จาก Map (จาก database)
  factory Entry.fromMap(Map<String, dynamic> map) => Entry(
        id: map['id'] as int?,
        content: map['content'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        latitude: map['latitude'] as double?,
        longitude: map['longitude'] as double?,
        locationName: map['location_name'] as String?,
        mediaPath: map['media_path'] as String?,
        mediaType: MediaType.values[map['media_type'] as int? ?? 0],
        mood: map['mood'] as int?,
        tags: _parseTags(map['tags'] as String?),
      );

  /// แปลง Entry เป็น Map (สำหรับ database)
  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'location_name': locationName,
        'media_path': mediaPath,
        'media_type': mediaType.index,
        'mood': mood,
        'tags': tags.join(','),
      };

  /// Copy with new values
>>>>>>> 21c9be3c902c18aaa90280be22e4688dcc96c84b
  Entry copyWith({
    int? id,
    String? content,
    DateTime? createdAt,
    double? latitude,
    double? longitude,
    String? locationName,
    String? mediaPath,
    MediaType? mediaType,
    int? mood,
    List<String>? tags,
<<<<<<< HEAD
  }) => Entry(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      mediaPath: mediaPath ?? this.mediaPath,
      mediaType: mediaType ?? this.mediaType,
      mood: mood ?? this.mood,
      tags: tags ?? this.tags,
    );

  /// 🏷️ ดึง hashtag จาก content อัตโนมัติ
  /// ตัวอย่าง: "วันนี้มีความสุข #happy #work" → ['happy', 'work']
  static List<String> extractTags(String content) {
    final regex = RegExp(r'#(\w+)', caseSensitive: false);
    return regex.allMatches(content).map((m) => m.group(1)!).toList();
  }

  /// 😊 แปลง mood เป็นข้อความและสี
  static Map<String, dynamic> getMoodInfo(int? mood) {
    switch (mood) {
      case 1:
        return {'emoji': '😢', 'label': 'แย่มาก', 'color': 0xFFEF5350};
      case 2:
        return {'emoji': '😕', 'label': 'แย่', 'color': 0xFFFF7043};
      case 3:
        return {'emoji': '😐', 'label': 'เฉยๆ', 'color': 0xFFFFB74D};
      case 4:
        return {'emoji': '🙂', 'label': 'ดี', 'color': 0xFF81C784};
      case 5:
        return {'emoji': '😄', 'label': 'ดีมาก', 'color': 0xFF4CAF50};
      default:
        return {'emoji': '📝', 'label': 'ไม่ระบุ', 'color': 0xFF9E9E9E};
    }
  }
}

/// 🎵 ประเภทของ Media ที่แนบมากับ Entry
enum MediaType {
  none,     // ไม่มี media
  image,    // รูปภาพ
  audio,    // เสียง
=======
  }) =>
      Entry(
        id: id ?? this.id,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        locationName: locationName ?? this.locationName,
        mediaPath: mediaPath ?? this.mediaPath,
        mediaType: mediaType ?? this.mediaType,
        mood: mood ?? this.mood,
        tags: tags ?? this.tags,
      );

  // ============================================================================
  // Static Helper Methods
  // ============================================================================

  /// Parse tags จาก comma-separated string
  static List<String> _parseTags(String? tagsStr) {
    if (tagsStr == null || tagsStr.isEmpty) return [];
    return tagsStr.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }

  /// ดึง tags จากเนื้อหา (หา #hashtag)
  static List<String> extractTags(String content) {
    final regex = RegExp(r'#(\w+)');
    return regex.allMatches(content).map((m) => m.group(1)!).toList();
  }

  /// ข้อมูล Mood (emoji + label)
  static Map<String, dynamic> getMoodInfo(int? mood) {
    switch (mood) {
      case 1:
        return {'emoji': '😢', 'label': 'แย่มาก', 'color': 0xFFE53935};
      case 2:
        return {'emoji': '😕', 'label': 'ไม่ค่อยดี', 'color': 0xFFFF9800};
      case 3:
        return {'emoji': '😐', 'label': 'เฉยๆ', 'color': 0xFFFFEB3B};
      case 4:
        return {'emoji': '🙂', 'label': 'ดี', 'color': 0xFF8BC34A};
      case 5:
        return {'emoji': '😊', 'label': 'ดีมาก', 'color': 0xFF4CAF50};
      default:
        return {'emoji': '❓', 'label': 'ไม่ระบุ', 'color': 0xFF9E9E9E};
    }
  }

  /// รายการ Mood ทั้งหมด (สำหรับ UI)
  static List<Map<String, dynamic>> get allMoods => [
        getMoodInfo(1),
        getMoodInfo(2),
        getMoodInfo(3),
        getMoodInfo(4),
        getMoodInfo(5),
      ];

  // ============================================================================
  // Display Helpers
  // ============================================================================

  /// แสดงวันที่ในรูปแบบไทย
  String get displayDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entryDate = DateTime(createdAt.year, createdAt.month, createdAt.day);

    if (entryDate == today) {
      return 'วันนี้';
    } else if (entryDate == today.subtract(const Duration(days: 1))) {
      return 'เมื่อวาน';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }

  /// แสดงเวลา
  String get displayTime =>
      '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

  /// แสดงวันเวลารวม
  String get displayDateTime => '$displayDate $displayTime';

  /// Preview เนื้อหา (ตัดให้สั้น)
  String get contentPreview {
    if (content.length <= 100) return content;
    return '${content.substring(0, 100)}...';
  }

  /// มีตำแหน่งหรือไม่
  bool get hasLocation => latitude != null && longitude != null;

  /// มีสื่อหรือไม่
  bool get hasMedia => mediaPath != null && mediaPath!.isNotEmpty;

  @override
  String toString() =>
      'Entry(id: $id, content: ${contentPreview}, createdAt: $createdAt)';
>>>>>>> 21c9be3c902c18aaa90280be22e4688dcc96c84b
}
