/// 🔮 Correlation Models - โมเดลสำหรับ The Hidden Correlation
/// 
/// เก็บ entities ที่สกัดจาก content และ insights ที่ค้นพบ
library;

/// 📊 Entity Type - ประเภทข้อมูลที่สกัดได้
enum EntityType {
  sleepHours,      // จำนวนชั่วโมงนอน (e.g., "นอน 5 ชั่วโมง")
  food,            // อาหาร/เครื่องดื่ม (e.g., "กาแฟร้าน A", "กินข้าวผัด")
  symptoms,        // อาการ/โรค (e.g., "ปวดหัว", "เป็นหวัด", "เมื่อย")
  activities,      // กิจกรรม (e.g., "วิ่ง", "ออกกำลังกาย", "ดูหนัง")
  social,          // สังคม (e.g., "เจอเพื่อน", "ประชุม", "ปาร์ตี้")
  weather,         // สภาพอากาศ (e.g., "ฝนตก", "ร้อน", "หนาว")
  people,          // บุคคล (e.g., "เจอพี่สาว", "คุยกับแม่")
  workStress,      // ความเครียดงาน (e.g., "deadline", "ประชุมยาว", "OT")
  expense,         // ค่าใช้จ่าย (e.g., "ใช้เงิน 500", "ซื้อของ")
  location,        // สถานที่เฉพาะ (e.g., "Central", "ร้านกาแฟ")
  mood,            // อารมณ์โดยละเอียด (e.g., "เศร้า", "กังวล", "ตื่นเต้น")
}

/// 🏷️ Entity - ข้อมูลที่สกัดจาก entry
class Entity {
  final EntityType type;
  final String value;           // ค่าที่สกัดได้ (normalized)
  final String rawText;         // ข้อความต้นฉบับ
  final double confidence;      // ความมั่นใจ (0.0 - 1.0)
  final DateTime timestamp;     // เวลาที่พบ
  final int? entryId;           // เชื่อมโยงกับ entry
  
  // Context เพิ่มเติม
  final Map<String, dynamic>? metadata;

  const Entity({
    required this.type,
    required this.value,
    required this.rawText,
    this.confidence = 1.0,
    required this.timestamp,
    this.entryId,
    this.metadata,
  });

  /// 🔄 แปลงเป็น Map
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'value': value,
    'rawText': rawText,
    'confidence': confidence,
    'timestamp': timestamp.toIso8601String(),
    'entryId': entryId,
    'metadata': metadata,
  };

  /// 🔄 สร้างจาก Map
  factory Entity.fromJson(Map<String, dynamic> json) => Entity(
    type: EntityType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => EntityType.activities,
    ),
    value: json['value'] as String,
    rawText: json['rawText'] as String,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    timestamp: DateTime.parse(json['timestamp'] as String),
    entryId: json['entryId'] as int?,
    metadata: json['metadata'] as Map<String, dynamic>?,
  );

  /// 📋 Copy with
  Entity copyWith({
    EntityType? type,
    String? value,
    String? rawText,
    double? confidence,
    DateTime? timestamp,
    int? entryId,
    Map<String, dynamic>? metadata,
  }) => Entity(
    type: type ?? this.type,
    value: value ?? this.value,
    rawText: rawText ?? this.rawText,
    confidence: confidence ?? this.confidence,
    timestamp: timestamp ?? this.timestamp,
    entryId: entryId ?? this.entryId,
    metadata: metadata ?? this.metadata,
  );

  /// 🎯 Unique key สำหรับ grouping
  String get uniqueKey => '${type.name}:$value';
}

/// 🔗 Correlation Insight - ความเชื่อมโยงที่ค้นพบ
class CorrelationInsight {
  final String id;
  final EntityType entityAType;
  final String entityAValue;
  final EntityType entityBType;
  final String entityBValue;
  
  // สถิติ
  final double correlation;     // -1.0 ถึง 1.0
  final double confidence;      // 0.0 ถึง 1.0 (จำนวนตัวอย่าง/ความน่าเชื่อถือ)
  final int sampleSize;         // จำนวนวันที่มีข้อมูล
  final double support;         // % ของวันที่มีทั้ง A และ B
  
  // รายละเอียด
  final String description;     // คำอธิบายเชิงภาษา
  final List<DateTime> occurrences; // วันที่เกิดขึ้น
  final DateTime discoveredAt;  // วันที่ค้นพบ
  final DateTime lastUpdated;   // อัพเดทล่าสุด
  
  // Metadata
  final Map<String, dynamic>? metadata;

  CorrelationInsight({
    required this.id,
    required this.entityAType,
    required this.entityAValue,
    required this.entityBType,
    required this.entityBValue,
    required this.correlation,
    required this.confidence,
    required this.sampleSize,
    required this.support,
    required this.description,
    required this.occurrences,
    required this.discoveredAt,
    required this.lastUpdated,
    this.metadata,
  });

  /// 🔄 แปลงเป็น Map
  Map<String, dynamic> toJson() => {
    'id': id,
    'entityAType': entityAType.name,
    'entityAValue': entityAValue,
    'entityBType': entityBType.name,
    'entityBValue': entityBValue,
    'correlation': correlation,
    'confidence': confidence,
    'sampleSize': sampleSize,
    'support': support,
    'description': description,
    'occurrences': occurrences.map((d) => d.toIso8601String()).toList(),
    'discoveredAt': discoveredAt.toIso8601String(),
    'lastUpdated': lastUpdated.toIso8601String(),
    'metadata': metadata,
  };

  /// 🔄 สร้างจาก Map
  factory CorrelationInsight.fromJson(Map<String, dynamic> json) => CorrelationInsight(
    id: json['id'] as String,
    entityAType: EntityType.values.firstWhere(
      (e) => e.name == json['entityAType'],
      orElse: () => EntityType.activities,
    ),
    entityAValue: json['entityAValue'] as String,
    entityBType: EntityType.values.firstWhere(
      (e) => e.name == json['entityBType'],
      orElse: () => EntityType.activities,
    ),
    entityBValue: json['entityBValue'] as String,
    correlation: (json['correlation'] as num).toDouble(),
    confidence: (json['confidence'] as num).toDouble(),
    sampleSize: json['sampleSize'] as int,
    support: (json['support'] as num).toDouble(),
    description: json['description'] as String,
    occurrences: (json['occurrences'] as List<dynamic>)
        .map((d) => DateTime.parse(d as String))
        .toList(),
    discoveredAt: DateTime.parse(json['discoveredAt'] as String),
    lastUpdated: DateTime.parse(json['lastUpdated'] as String),
    metadata: json['metadata'] as Map<String, dynamic>?,
  );

  /// 📝 สร้างข้อความอธิบายอัตโนมัติ
  String generateDescription() {
    final strength = correlation.abs() > 0.7 
        ? 'สูงมาก' 
        : correlation.abs() > 0.5 
            ? 'สูง' 
            : correlation.abs() > 0.3 
                ? 'ปานกลาง' 
                : 'ต่ำ';
    
    final relation = correlation > 0 
        ? 'มีความสัมพันธ์เชิงบวก' 
        : 'มีความสัมพันธ์เชิงลบ';
    
    return '$relationระดับ$strength (${(correlation * 100).toStringAsFixed(0)}%) ระหว่าง "$entityAValue" และ "$entityBValue"';
  }

  /// 🎯 คำแนะนำที่ควรทำ/ไม่ควรทำ
  String? getRecommendation() {
    if (confidence < 0.5 || sampleSize < 5) return null;
    
    // กรณี negative correlation กับ symptoms
    if (entityBType == EntityType.symptoms && correlation > 0.5) {
      return 'เลี่ยง $entityAValue อาจลดโอกาส$entityBValue';
    }
    
    // กรณี positive correlation กับอาการดี
    if (entityBType == EntityType.mood && correlation > 0.5) {
      return 'ลองทำ $entityAValue อีก อาจช่วยให้รู้สึกดีขึ้น';
    }
    
    return null;
  }
}

/// 📊 Daily Entity Snapshot - สรุป entities ของแต่ละวัน
class DailyEntitySnapshot {
  final DateTime date;
  final List<Entity> entities;
  final int? averageMood;
  final int entryCount;

  DailyEntitySnapshot({
    required this.date,
    required this.entities,
    this.averageMood,
    this.entryCount = 0,
  });

  /// หา entity ตาม type
  List<Entity> getByType(EntityType type) => 
      entities.where((e) => e.type == type).toList();

  /// มี entity นี้หรือไม่
  bool hasEntity(EntityType type, String value) =>
      entities.any((e) => e.type == type && e.value == value);
}

/// 🎯 Correlation Analysis Result - ผลการวิเคราะห์
class CorrelationAnalysisResult {
  final List<CorrelationInsight> insights;
  final int totalDaysAnalyzed;
  final int totalEntitiesFound;
  final DateTime analyzedAt;
  final String? gemmaSummary;  // สรุปจาก Gemma (ถ้ามี)

  CorrelationAnalysisResult({
    required this.insights,
    required this.totalDaysAnalyzed,
    required this.totalEntitiesFound,
    required this.analyzedAt,
    this.gemmaSummary,
  });

  /// กรอง insights ที่น่าสนใจ
  List<CorrelationInsight> get interestingInsights => insights
      .where((i) => i.confidence > 0.6 && i.correlation.abs() > 0.5)
      .toList();

  /// หา insights ที่เกี่ยวข้องกับ symptoms
  List<CorrelationInsight> get healthRelatedInsights => insights
      .where((i) => 
          i.entityAType == EntityType.symptoms || 
          i.entityBType == EntityType.symptoms)
      .toList();

  /// หา insights ที่เกี่ยวข้องกับ mood
  List<CorrelationInsight> get moodRelatedInsights => insights
      .where((i) => 
          i.entityAType == EntityType.mood || 
          i.entityBType == EntityType.mood)
      .toList();
}

/// 📋 Entity Extraction Result - ผลการสกัด entities
class EntityExtractionResult {
  final List<Entity> entities;
  final String method;  // 'rule_based', 'gemma', 'hybrid'
  final DateTime extractedAt;
  final int entryId;

  EntityExtractionResult({
    required this.entities,
    required this.method,
    required this.extractedAt,
    required this.entryId,
  });
}
