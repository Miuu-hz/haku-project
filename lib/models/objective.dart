/// 🎯 Objective Model - เป้าหมาย/งานที่ AI ช่วยจัดการ
///
/// Objective คือสิ่งที่ผู้ใช้บอกว่าจะทำ และ AI จะช่วย:
/// - สร้าง Schedule อัตโนมัติ
/// - แจ้งเตือนเมื่อใกล้ถึงเวลา
/// - ติดตามความคืบหน้า
///
/// เช่น: "พรุ่งนี้มีนัด 9 โมงกับลูกค้า"
/// → AI จะสร้าง Objective พร้อม schedule และ reminders

class Objective {
  final String id;
  final String title;
  final String? description;

  /// 🔗 เชื่อมโยงกับ Entry ต้นทาง (null ถ้าสร้างเอง)
  final int? entryId;

  /// วันเวลาที่ต้องทำ
  final DateTime? dueDate;
  final String? dueTime;

  /// ระยะเวลา (นาที)
  final int? durationMinutes;

  /// สถานที่
  final String? location;
  final double? latitude;
  final double? longitude;

  /// สถานะ
  final ObjectiveStatus status;

  /// แจ้งเตือนก่อนกี่นาที
  final List<int> reminderMinutesBefore;

  /// ข้อมูลดิบที่ผู้ใช้พิมพ์
  final String originalText;

  /// AI สร้างเอง หรือ ผู้ใช้สร้าง
  final bool isAIGenerated;

  /// ผู้ใช้ approve แล้วหรือยัง
  final bool isApproved;

  /// สร้างเมื่อไหร่
  final DateTime createdAt;

  /// แก้ไขล่าสุด
  final DateTime updatedAt;

  /// Tags
  final List<String> tags;

  /// Related preset
  final String? presetId;

  const Objective({
    required this.id,
    required this.title,
    this.description,
    this.entryId,
    this.dueDate,
    this.dueTime,
    this.durationMinutes,
    this.location,
    this.latitude,
    this.longitude,
    this.status = ObjectiveStatus.pending,
    this.reminderMinutesBefore = const [15, 60],
    this.originalText = '',
    this.isAIGenerated = false,
    this.isApproved = false,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
    this.presetId,
  });

  Objective copyWith({
    String? title,
    String? description,
    int? entryId,
    DateTime? dueDate,
    String? dueTime,
    int? durationMinutes,
    String? location,
    double? latitude,
    double? longitude,
    ObjectiveStatus? status,
    List<int>? reminderMinutesBefore,
    bool? isApproved,
    List<String>? tags,
    String? presetId,
  }) =>
      Objective(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        entryId: entryId ?? this.entryId,
        dueDate: dueDate ?? this.dueDate,
        dueTime: dueTime ?? this.dueTime,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        location: location ?? this.location,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        status: status ?? this.status,
        reminderMinutesBefore:
            reminderMinutesBefore ?? this.reminderMinutesBefore,
        originalText: originalText,
        isAIGenerated: isAIGenerated,
        isApproved: isApproved ?? this.isApproved,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        tags: tags ?? this.tags,
        presetId: presetId ?? this.presetId,
      );

  /// แสดงวันเวลา
  String get displayDateTime {
    if (dueDate == null) return 'ยังไม่กำหนด';

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    String dateStr;
    if (dueDate!.year == now.year &&
        dueDate!.month == now.month &&
        dueDate!.day == now.day) {
      dateStr = 'วันนี้';
    } else if (dueDate!.year == tomorrow.year &&
        dueDate!.month == tomorrow.month &&
        dueDate!.day == tomorrow.day) {
      dateStr = 'พรุ่งนี้';
    } else {
      dateStr = '${dueDate!.day}/${dueDate!.month}';
    }

    if (dueTime != null) {
      return '$dateStr เวลา $dueTime';
    }
    return dateStr;
  }

  /// เหลือเวลาอีกเท่าไหร่
  Duration? get timeUntilDue {
    if (dueDate == null) return null;

    DateTime target = dueDate!;
    if (dueTime != null) {
      final parts = dueTime!.split(':');
      if (parts.length == 2) {
        target = DateTime(
          dueDate!.year,
          dueDate!.month,
          dueDate!.day,
          int.tryParse(parts[0]) ?? 0,
          int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    return target.difference(DateTime.now());
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'entryId': entryId,
        'dueDate': dueDate?.toIso8601String(),
        'dueTime': dueTime,
        'durationMinutes': durationMinutes,
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'status': status.name,
        'reminderMinutesBefore': reminderMinutesBefore,
        'originalText': originalText,
        'isAIGenerated': isAIGenerated,
        'isApproved': isApproved,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'tags': tags,
        'presetId': presetId,
      };

  factory Objective.fromJson(Map<String, dynamic> json) => Objective(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        entryId: json['entryId'] as int?,
        dueDate: json['dueDate'] != null
            ? DateTime.parse(json['dueDate'] as String)
            : null,
        dueTime: json['dueTime'] as String?,
        durationMinutes: json['durationMinutes'] as int?,
        location: json['location'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        status: ObjectiveStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => ObjectiveStatus.pending,
        ),
        reminderMinutesBefore:
            (json['reminderMinutesBefore'] as List<dynamic>?)?.cast<int>() ??
                [15, 60],
        originalText: json['originalText'] as String? ?? '',
        isAIGenerated: json['isAIGenerated'] as bool? ?? false,
        isApproved: json['isApproved'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
        presetId: json['presetId'] as String?,
      );
}

enum ObjectiveStatus {
  pending, // รอดำเนินการ
  inProgress, // กำลังทำ
  completed, // เสร็จแล้ว
  cancelled, // ยกเลิก
  overdue, // เลยกำหนด
}

extension ObjectiveStatusExtension on ObjectiveStatus {
  String get displayName {
    switch (this) {
      case ObjectiveStatus.pending:
        return 'รอดำเนินการ';
      case ObjectiveStatus.inProgress:
        return 'กำลังทำ';
      case ObjectiveStatus.completed:
        return 'เสร็จแล้ว';
      case ObjectiveStatus.cancelled:
        return 'ยกเลิก';
      case ObjectiveStatus.overdue:
        return 'เลยกำหนด';
    }
  }

  String get emoji {
    switch (this) {
      case ObjectiveStatus.pending:
        return '⏳';
      case ObjectiveStatus.inProgress:
        return '🔄';
      case ObjectiveStatus.completed:
        return '✅';
      case ObjectiveStatus.cancelled:
        return '❌';
      case ObjectiveStatus.overdue:
        return '⚠️';
    }
  }
}
