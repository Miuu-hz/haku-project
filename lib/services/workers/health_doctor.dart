import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../unified_vector_service.dart';

/// 💊 Health Doctor - ผู้ช่วยด้านสุขภาพ
///
/// หน้าที่:
/// - จดจำข้อมูลสุขภาพ (ไม่วินิจฉัย!)
/// - ติดตามรอบเดือน
/// - เตือนกินยา
/// - บันทึกอาการ
/// - แนะนำพบแพทย์เมื่อจำเป็น
///
/// DISCLAIMER: ไม่ใช่หมอ ไม่วินิจฉัยโรค
/// เป็นแค่ผู้ช่วยจดจำและเตือน

class HealthDoctor {
  static final HealthDoctor _instance = HealthDoctor._internal();
  factory HealthDoctor() => _instance;
  HealthDoctor._internal();

  static const String _healthDataKey = 'health_doctor_data';

  final UnifiedVectorService _vectorService = UnifiedVectorService();

  HealthData _healthData = HealthData.empty();
  bool _isInitialized = false;

  /// Persona description for LLM context
  static const String persona = '''
ฉันคือผู้ช่วยด้านสุขภาพของคุณ
- ฉันจะจดจำข้อมูลสุขภาพ เช่น รอบเดือน อาการป่วย ยาที่ทาน
- ฉันจะเตือนเรื่องสำคัญ เช่น กินยา ตรวจสุขภาพ
- ฉันไม่ใช่หมอ ไม่วินิจฉัยโรค
- ถ้ามีอาการผิดปกติ ฉันจะแนะนำให้พบแพทย์
''';

  /// Lean format for context
  String get leanFormat {
    final parts = <String>[];

    if (_healthData.lastPeriodDate != null) {
      final daysAgo = DateTime.now().difference(_healthData.lastPeriodDate!).inDays;
      parts.add('Period:${daysAgo}d ago');
    }

    if (_healthData.allergies.isNotEmpty) {
      parts.add('Allergy:${_healthData.allergies.take(3).join(",")}');
    }

    if (_healthData.medications.isNotEmpty) {
      parts.add('Med:${_healthData.medications.take(3).map((m) => m.name).join(",")}');
    }

    if (_healthData.conditions.isNotEmpty) {
      parts.add('Cond:${_healthData.conditions.take(3).join(",")}');
    }

    if (parts.isEmpty) return '';
    return '[Health:${parts.join("|")}]';
  }

  /// 🚀 Initialize
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadData();
    _isInitialized = true;
    debugPrint('✅ HealthDoctor initialized');
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_healthDataKey);
      if (json != null) {
        _healthData = HealthData.fromJson(jsonDecode(json) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('⚠️ Error loading health data: $e');
    }
  }

  Future<void> _saveData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_healthDataKey, jsonEncode(_healthData.toJson()));
    } catch (e) {
      debugPrint('⚠️ Error saving health data: $e');
    }
  }

  // ============================================================
  // 🔍 DETECTION
  // ============================================================

  /// ตรวจจับข้อมูลสุขภาพจากข้อความ
  Future<List<HealthFact>> detectHealth(String message) async {
    final facts = <HealthFact>[];
    final lower = message.toLowerCase();

    // Period detection
    if (_containsPeriod(lower)) {
      facts.add(HealthFact(
        type: HealthFactType.period,
        value: 'started',
        date: DateTime.now(),
      ));
      await recordPeriod();
    }

    // Pain detection
    final painMatch = RegExp(r'ปวด\s*(\S+)').firstMatch(message);
    if (painMatch != null) {
      facts.add(HealthFact(
        type: HealthFactType.symptom,
        value: 'pain:${painMatch.group(1)}',
        date: DateTime.now(),
      ));
      await recordSymptom('ปวด${painMatch.group(1)}');
    }

    // Sick detection
    if (lower.contains('ไม่สบาย') || lower.contains('ป่วย')) {
      facts.add(HealthFact(
        type: HealthFactType.symptom,
        value: 'sick',
        date: DateTime.now(),
      ));
      await recordSymptom('ไม่สบาย');
    }

    // Allergy detection
    final allergyMatch = RegExp(r'แพ้\s*(\S+)').firstMatch(message);
    if (allergyMatch != null) {
      final allergen = allergyMatch.group(1)!;
      facts.add(HealthFact(
        type: HealthFactType.allergy,
        value: allergen,
        date: DateTime.now(),
      ));
      await addAllergy(allergen);
    }

    // Medication detection
    final medPatterns = [
      RegExp(r'กิน(?:ยา)?\s*(\S+)'),
      RegExp(r'ทาน(?:ยา)?\s*(\S+)'),
    ];
    for (final pattern in medPatterns) {
      final match = pattern.firstMatch(message);
      if (match != null && message.contains('ยา')) {
        facts.add(HealthFact(
          type: HealthFactType.medication,
          value: match.group(1) ?? 'ยา',
          date: DateTime.now(),
        ));
      }
    }

    return facts;
  }

  bool _containsPeriod(String text) {
    return text.contains('เป็นเมน') ||
        text.contains('ประจำเดือน') ||
        text.contains('รอบเดือน') ||
        text.contains('เมนส์');
  }

  // ============================================================
  // 📝 RECORDING
  // ============================================================

  /// บันทึกรอบเดือน
  Future<void> recordPeriod({DateTime? date}) async {
    final recordDate = date ?? DateTime.now();

    // Calculate cycle if we have previous data
    int? cycleLength;
    if (_healthData.lastPeriodDate != null) {
      cycleLength = recordDate.difference(_healthData.lastPeriodDate!).inDays;
    }

    _healthData = _healthData.copyWith(
      lastPeriodDate: recordDate,
      periodHistory: [
        ..._healthData.periodHistory,
        PeriodRecord(date: recordDate, cycleLength: cycleLength),
      ],
    );

    await _saveData();
    await _saveToRAG('period', 'Period started', {'date': recordDate.toIso8601String()});

    debugPrint('💊 HealthDoctor: Period recorded');
  }

  /// บันทึกอาการ
  Future<void> recordSymptom(String symptom, {String? notes}) async {
    final record = SymptomRecord(
      symptom: symptom,
      date: DateTime.now(),
      notes: notes,
    );

    _healthData = _healthData.copyWith(
      symptoms: [..._healthData.symptoms, record],
    );

    await _saveData();
    await _saveToRAG('symptom', symptom, {'notes': notes});

    debugPrint('💊 HealthDoctor: Symptom recorded: $symptom');
  }

  /// เพิ่มข้อมูลแพ้
  Future<void> addAllergy(String allergen) async {
    if (_healthData.allergies.contains(allergen)) return;

    _healthData = _healthData.copyWith(
      allergies: [..._healthData.allergies, allergen],
    );

    await _saveData();
    await _saveToRAG('allergy', allergen, {});

    debugPrint('💊 HealthDoctor: Allergy added: $allergen');
  }

  /// เพิ่มยาที่ทาน
  Future<void> addMedication({
    required String name,
    String? dosage,
    String? frequency,
    String? notes,
  }) async {
    final med = Medication(
      name: name,
      dosage: dosage,
      frequency: frequency,
      notes: notes,
      startDate: DateTime.now(),
    );

    _healthData = _healthData.copyWith(
      medications: [..._healthData.medications, med],
    );

    await _saveData();
    debugPrint('💊 HealthDoctor: Medication added: $name');
  }

  /// เพิ่มโรคประจำตัว
  Future<void> addCondition(String condition) async {
    if (_healthData.conditions.contains(condition)) return;

    _healthData = _healthData.copyWith(
      conditions: [..._healthData.conditions, condition],
    );

    await _saveData();
    debugPrint('💊 HealthDoctor: Condition added: $condition');
  }

  // ============================================================
  // 📊 ANALYSIS
  // ============================================================

  /// วิเคราะห์และคาดการณ์
  Future<HealthAnalysis> analyze() async {
    final predictions = <HealthPrediction>[];
    final reminders = <HealthReminder>[];

    // Period prediction
    if (_healthData.periodHistory.length >= 2) {
      final avgCycle = _calculateAverageCycle();
      if (avgCycle != null && _healthData.lastPeriodDate != null) {
        final nextPeriod = _healthData.lastPeriodDate!.add(Duration(days: avgCycle));
        final daysUntil = nextPeriod.difference(DateTime.now()).inDays;

        predictions.add(HealthPrediction(
          type: 'period',
          prediction: 'รอบถัดไปประมาณ $daysUntil วัน',
          confidence: 0.7,
          date: nextPeriod,
        ));

        // อาจปวดท้อง 2-5 วันหลังเริ่ม
        if (_healthData.lastPeriodDate != null) {
          final daysSinceStart = DateTime.now().difference(_healthData.lastPeriodDate!).inDays;
          if (daysSinceStart >= 0 && daysSinceStart <= 5) {
            predictions.add(HealthPrediction(
              type: 'cramps',
              prediction: 'อาจมีอาการปวดท้องในช่วงนี้',
              confidence: 0.6,
            ));
          }
        }
      }
    }

    // Medication reminders
    for (final med in _healthData.medications) {
      reminders.add(HealthReminder(
        type: 'medication',
        message: 'อย่าลืมกินยา ${med.name}',
        frequency: med.frequency ?? 'daily',
      ));
    }

    return HealthAnalysis(
      predictions: predictions,
      reminders: reminders,
      summary: _generateSummary(),
    );
  }

  int? _calculateAverageCycle() {
    final cycles = _healthData.periodHistory
        .where((p) => p.cycleLength != null)
        .map((p) => p.cycleLength!)
        .toList();

    if (cycles.isEmpty) return null;
    return (cycles.reduce((a, b) => a + b) / cycles.length).round();
  }

  String _generateSummary() {
    final parts = <String>[];

    if (_healthData.lastPeriodDate != null) {
      final daysAgo = DateTime.now().difference(_healthData.lastPeriodDate!).inDays;
      parts.add('Period: $daysAgo days ago');
    }

    if (_healthData.allergies.isNotEmpty) {
      parts.add('Allergies: ${_healthData.allergies.join(", ")}');
    }

    if (_healthData.medications.isNotEmpty) {
      parts.add('Medications: ${_healthData.medications.length}');
    }

    if (_healthData.symptoms.isNotEmpty) {
      final recent = _healthData.symptoms.take(3).map((s) => s.symptom).join(", ");
      parts.add('Recent symptoms: $recent');
    }

    return parts.join(' | ');
  }

  // ============================================================
  // 💾 RAG
  // ============================================================

  Future<void> _saveToRAG(String category, String content, Map<String, dynamic> metadata) async {
    try {
      await _vectorService.addFact(
        category: 'health_$category',
        content: content,
        metadata: {
          ...metadata,
          'recordedAt': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('⚠️ Failed to save health to RAG: $e');
    }
  }

  // ============================================================
  // 📋 GETTERS
  // ============================================================

  HealthData get data => _healthData;

  /// Get recent symptoms
  List<SymptomRecord> getRecentSymptoms({int days = 7}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return _healthData.symptoms.where((s) => s.date.isAfter(cutoff)).toList();
  }

  /// Clear all data
  Future<void> clearAll() async {
    _healthData = HealthData.empty();
    await _saveData();
  }
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

enum HealthFactType {
  period,
  symptom,
  allergy,
  medication,
  condition,
}

class HealthFact {
  final HealthFactType type;
  final String value;
  final DateTime date;

  HealthFact({
    required this.type,
    required this.value,
    required this.date,
  });
}

class HealthData {
  final DateTime? lastPeriodDate;
  final List<PeriodRecord> periodHistory;
  final List<String> allergies;
  final List<Medication> medications;
  final List<String> conditions;
  final List<SymptomRecord> symptoms;

  HealthData({
    this.lastPeriodDate,
    required this.periodHistory,
    required this.allergies,
    required this.medications,
    required this.conditions,
    required this.symptoms,
  });

  factory HealthData.empty() => HealthData(
    periodHistory: [],
    allergies: [],
    medications: [],
    conditions: [],
    symptoms: [],
  );

  HealthData copyWith({
    DateTime? lastPeriodDate,
    List<PeriodRecord>? periodHistory,
    List<String>? allergies,
    List<Medication>? medications,
    List<String>? conditions,
    List<SymptomRecord>? symptoms,
  }) => HealthData(
    lastPeriodDate: lastPeriodDate ?? this.lastPeriodDate,
    periodHistory: periodHistory ?? this.periodHistory,
    allergies: allergies ?? this.allergies,
    medications: medications ?? this.medications,
    conditions: conditions ?? this.conditions,
    symptoms: symptoms ?? this.symptoms,
  );

  factory HealthData.fromJson(Map<String, dynamic> json) => HealthData(
    lastPeriodDate: json['lastPeriodDate'] != null
        ? DateTime.parse(json['lastPeriodDate'] as String)
        : null,
    periodHistory: (json['periodHistory'] as List<dynamic>?)
        ?.map((e) => PeriodRecord.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    allergies: List<String>.from(json['allergies'] as Iterable<dynamic>? ?? []),
    medications: (json['medications'] as List<dynamic>?)
        ?.map((e) => Medication.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    conditions: List<String>.from(json['conditions'] as Iterable<dynamic>? ?? []),
    symptoms: (json['symptoms'] as List<dynamic>?)
        ?.map((e) => SymptomRecord.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'lastPeriodDate': lastPeriodDate?.toIso8601String(),
    'periodHistory': periodHistory.map((p) => p.toJson()).toList(),
    'allergies': allergies,
    'medications': medications.map((m) => m.toJson()).toList(),
    'conditions': conditions,
    'symptoms': symptoms.map((s) => s.toJson()).toList(),
  };
}

class PeriodRecord {
  final DateTime date;
  final int? cycleLength;

  PeriodRecord({required this.date, this.cycleLength});

  factory PeriodRecord.fromJson(Map<String, dynamic> json) => PeriodRecord(
    date: DateTime.parse(json['date'] as String),
    cycleLength: json['cycleLength'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'cycleLength': cycleLength,
  };
}

class Medication {
  final String name;
  final String? dosage;
  final String? frequency;
  final String? notes;
  final DateTime startDate;

  Medication({
    required this.name,
    this.dosage,
    this.frequency,
    this.notes,
    required this.startDate,
  });

  factory Medication.fromJson(Map<String, dynamic> json) => Medication(
    name: json['name'] as String,
    dosage: json['dosage'] as String?,
    frequency: json['frequency'] as String?,
    notes: json['notes'] as String?,
    startDate: DateTime.parse(json['startDate'] as String),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'dosage': dosage,
    'frequency': frequency,
    'notes': notes,
    'startDate': startDate.toIso8601String(),
  };
}

class SymptomRecord {
  final String symptom;
  final DateTime date;
  final String? notes;

  SymptomRecord({
    required this.symptom,
    required this.date,
    this.notes,
  });

  factory SymptomRecord.fromJson(Map<String, dynamic> json) => SymptomRecord(
    symptom: json['symptom'] as String,
    date: DateTime.parse(json['date'] as String),
    notes: json['notes'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'symptom': symptom,
    'date': date.toIso8601String(),
    'notes': notes,
  };
}

class HealthPrediction {
  final String type;
  final String prediction;
  final double confidence;
  final DateTime? date;

  HealthPrediction({
    required this.type,
    required this.prediction,
    required this.confidence,
    this.date,
  });
}

class HealthReminder {
  final String type;
  final String message;
  final String frequency;

  HealthReminder({
    required this.type,
    required this.message,
    required this.frequency,
  });
}

class HealthAnalysis {
  final List<HealthPrediction> predictions;
  final List<HealthReminder> reminders;
  final String summary;

  HealthAnalysis({
    required this.predictions,
    required this.reminders,
    required this.summary,
  });
}
