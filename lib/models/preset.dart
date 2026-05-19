// 🎭 Preset Model - โหมดการใช้งานตามบริบท
//
// Preset คือ "โหมด" ที่กำหนดพฤติกรรมของ Haku ตามสถานการณ์
// เช่น Morning Mode จะทักทายด้วยการเช็คสุขภาพ
// Battle Mode จะเน้น Quick Capture และเตือนพักเบรค

class Preset {
  final String id;
  final String name;
  final String icon;
  final String description;

  /// Trigger conditions (เงื่อนไขที่จะ activate preset นี้)
  final PresetTrigger trigger;

  /// AI personality/behavior ในโหมดนี้
  final PresetBehavior behavior;

  /// Actions ที่จะทำเมื่อเข้าโหมดนี้
  final List<PresetAction> onActivate;

  /// ผู้ใช้สร้างเอง หรือ system default
  final bool isCustom;

  /// เปิดใช้งานหรือไม่
  final bool isEnabled;

  /// ลำดับความสำคัญ (ถ้า trigger หลาย preset พร้อมกัน)
  final int priority;

  const Preset({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.trigger,
    required this.behavior,
    this.onActivate = const [],
    this.isCustom = false,
    this.isEnabled = true,
    this.priority = 0,
  });

  Preset copyWith({
    String? name,
    String? icon,
    String? description,
    PresetTrigger? trigger,
    PresetBehavior? behavior,
    List<PresetAction>? onActivate,
    bool? isEnabled,
    int? priority,
  }) =>
      Preset(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        description: description ?? this.description,
        trigger: trigger ?? this.trigger,
        behavior: behavior ?? this.behavior,
        onActivate: onActivate ?? this.onActivate,
        isCustom: isCustom,
        isEnabled: isEnabled ?? this.isEnabled,
        priority: priority ?? this.priority,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'description': description,
        'trigger': trigger.toJson(),
        'behavior': behavior.toJson(),
        'onActivate': onActivate.map((a) => a.toJson()).toList(),
        'isCustom': isCustom,
        'isEnabled': isEnabled,
        'priority': priority,
      };

  factory Preset.fromJson(Map<String, dynamic> json) => Preset(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String,
        description: json['description'] as String,
        trigger: PresetTrigger.fromJson(json['trigger'] as Map<String, dynamic>),
        behavior:
            PresetBehavior.fromJson(json['behavior'] as Map<String, dynamic>),
        onActivate: (json['onActivate'] as List<dynamic>?)
                ?.map((a) => PresetAction.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
        isCustom: json['isCustom'] as bool? ?? false,
        isEnabled: json['isEnabled'] as bool? ?? true,
        priority: json['priority'] as int? ?? 0,
      );
}

/// ⏰ Trigger Conditions - เงื่อนไขที่จะ activate preset
class PresetTrigger {
  /// ช่วงเวลา (HH:MM format)
  final String? timeStart;
  final String? timeEnd;

  /// วันในสัปดาห์ (1=จันทร์, 7=อาทิตย์)
  final List<int>? daysOfWeek;

  /// GPS Location (lat, lng, radius in meters)
  final double? latitude;
  final double? longitude;
  final double? radiusMeters;
  final String? locationName;

  /// Location type (home, office, new_place)
  final String? locationType;

  /// Manual only (ไม่ auto-trigger)
  final bool manualOnly;

  const PresetTrigger({
    this.timeStart,
    this.timeEnd,
    this.daysOfWeek,
    this.latitude,
    this.longitude,
    this.radiusMeters,
    this.locationName,
    this.locationType,
    this.manualOnly = false,
  });

  bool get hasTimeTrigger => timeStart != null && timeEnd != null;
  bool get hasLocationTrigger => latitude != null && longitude != null;
  bool get hasDayTrigger => daysOfWeek != null && daysOfWeek!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'timeStart': timeStart,
        'timeEnd': timeEnd,
        'daysOfWeek': daysOfWeek,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'locationName': locationName,
        'locationType': locationType,
        'manualOnly': manualOnly,
      };

  factory PresetTrigger.fromJson(Map<String, dynamic> json) => PresetTrigger(
        timeStart: json['timeStart'] as String?,
        timeEnd: json['timeEnd'] as String?,
        daysOfWeek: (json['daysOfWeek'] as List<dynamic>?)?.cast<int>(),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        radiusMeters: (json['radiusMeters'] as num?)?.toDouble(),
        locationName: json['locationName'] as String?,
        locationType: json['locationType'] as String?,
        manualOnly: json['manualOnly'] as bool? ?? false,
      );
}

/// 🧠 Preset Behavior - พฤติกรรมของ AI ในโหมดนี้
class PresetBehavior {
  /// Greeting message เมื่อเข้าโหมด
  final String greeting;

  /// Personality traits (ใช้ใน prompt)
  final String personality;

  /// คำถามที่ AI จะถามบ่อยๆ
  final List<String> suggestedQuestions;

  /// Focus areas (health, work, emotion, exploration)
  final List<String> focusAreas;

  /// เตือนทุกกี่นาที (0 = ไม่เตือน)
  final int reminderIntervalMinutes;

  const PresetBehavior({
    required this.greeting,
    required this.personality,
    this.suggestedQuestions = const [],
    this.focusAreas = const [],
    this.reminderIntervalMinutes = 0,
  });

  Map<String, dynamic> toJson() => {
        'greeting': greeting,
        'personality': personality,
        'suggestedQuestions': suggestedQuestions,
        'focusAreas': focusAreas,
        'reminderIntervalMinutes': reminderIntervalMinutes,
      };

  factory PresetBehavior.fromJson(Map<String, dynamic> json) => PresetBehavior(
        greeting: json['greeting'] as String? ?? '',
        personality: json['personality'] as String? ?? '',
        suggestedQuestions:
            (json['suggestedQuestions'] as List<dynamic>?)?.cast<String>() ??
                [],
        focusAreas:
            (json['focusAreas'] as List<dynamic>?)?.cast<String>() ?? [],
        reminderIntervalMinutes: json['reminderIntervalMinutes'] as int? ?? 0,
      );
}

/// ⚡ Preset Action - สิ่งที่ทำเมื่อเข้าโหมด
class PresetAction {
  final PresetActionType type;
  final Map<String, dynamic> params;

  const PresetAction({
    required this.type,
    this.params = const {},
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'params': params,
      };

  factory PresetAction.fromJson(Map<String, dynamic> json) => PresetAction(
        type: PresetActionType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => PresetActionType.notify,
        ),
        params: json['params'] as Map<String, dynamic>? ?? {},
      );
}

enum PresetActionType {
  notify, // แจ้งเตือน
  askQuestion, // ถามคำถาม
  summarize, // สรุปข้อมูล
  remind, // ตั้งเตือน
  switchPreset, // เปลี่ยน preset
}

// ============================================================================
// 📦 Default Presets
// ============================================================================

class DefaultPresets {
  static const morning = Preset(
    id: 'morning',
    name: 'Morning',
    icon: '🌅',
    description: 'เตรียมความพร้อม + เช็คสภาพร่างกาย',
    trigger: PresetTrigger(
      timeStart: '06:00',
      timeEnd: '09:00',
    ),
    behavior: PresetBehavior(
      greeting: 'สวัสดีตอนเช้า! พร้อมเริ่มวันใหม่ไหมคะ?',
      personality: 'อ่อนโยน ใส่ใจสุขภาพ ให้กำลังใจ',
      suggestedQuestions: [
        'นอนหลับดีไหมคะ?',
        'วันนี้มีแพลนอะไรบ้าง?',
        'รู้สึกยังไงตอนตื่นนอน?',
      ],
      focusAreas: ['health', 'planning'],
      reminderIntervalMinutes: 0,
    ),
    onActivate: [
      PresetAction(
        type: PresetActionType.askQuestion,
        params: {'question': 'นอนหลับดีไหมคะ?'},
      ),
    ],
    priority: 10,
  );

  static const battle = Preset(
    id: 'battle',
    name: 'Battle (Work)',
    icon: '⚔️',
    description: 'Quick Capture + เตือนพักเบรค',
    trigger: PresetTrigger(
      timeStart: '09:00',
      timeEnd: '17:00',
      daysOfWeek: [1, 2, 3, 4, 5], // จันทร์-ศุกร์
      locationType: 'office',
    ),
    behavior: PresetBehavior(
      greeting: 'พร้อมลุยงานกันเลย! มีอะไรให้ช่วยไหมคะ?',
      personality: 'กระชับ ตรงประเด็น ช่วยจดบันทึกไว',
      suggestedQuestions: [
        'ทำอะไรอยู่คะ?',
        'มีประชุมอะไรบ้าง?',
        'จดไว้ไหมคะ?',
      ],
      focusAreas: ['work', 'productivity'],
      reminderIntervalMinutes: 60, // เตือนพักทุก 1 ชม.
    ),
    onActivate: [
      PresetAction(
        type: PresetActionType.notify,
        params: {'message': 'เข้า Work Mode แล้วค่ะ'},
      ),
    ],
    priority: 20,
  );

  static const sanctuary = Preset(
    id: 'sanctuary',
    name: 'Sanctuary',
    icon: '🏠',
    description: 'สรุปวัน + บำบัดอารมณ์',
    trigger: PresetTrigger(
      timeStart: '18:00',
      timeEnd: '23:59',
      locationType: 'home',
    ),
    behavior: PresetBehavior(
      greeting: 'กลับบ้านแล้ว! วันนี้เป็นยังไงบ้างคะ?',
      personality: 'อบอุ่น เข้าอกเข้าใจ รับฟัง',
      suggestedQuestions: [
        'วันนี้เป็นยังไงบ้าง?',
        'มีเรื่องอะไรอยากเล่าไหม?',
        'พักผ่อนหน่อยนะคะ',
      ],
      focusAreas: ['emotion', 'reflection'],
      reminderIntervalMinutes: 0,
    ),
    onActivate: [
      PresetAction(
        type: PresetActionType.summarize,
        params: {'type': 'daily'},
      ),
    ],
    priority: 15,
  );

  static const explorer = Preset(
    id: 'explorer',
    name: 'Explorer',
    icon: '🗺️',
    description: 'Location-based memory + แนะนำที่เที่ยว',
    trigger: PresetTrigger(
      daysOfWeek: [6, 7], // เสาร์-อาทิตย์
      locationType: 'new_place',
    ),
    behavior: PresetBehavior(
      greeting: 'ไปเที่ยวที่ไหนกันคะวันนี้?',
      personality: 'สนุกสนาน กระตือรือร้น ชอบเล่าเรื่อง',
      suggestedQuestions: [
        'ที่นี่ชื่ออะไรคะ?',
        'มาทำอะไรกันคะ?',
        'เคยมาที่นี่ไหม?',
      ],
      focusAreas: ['exploration', 'memory'],
      reminderIntervalMinutes: 30, // เตือนให้ถ่ายรูป/บันทึก
    ),
    onActivate: [
      PresetAction(
        type: PresetActionType.askQuestion,
        params: {'question': 'ที่นี่ชื่ออะไรคะ?'},
      ),
    ],
    priority: 5,
  );

  static List<Preset> get all => [morning, battle, sanctuary, explorer];
}
