import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 🌤️ Weather Service
///
/// ใช้ Open-Meteo API (ฟรี ไม่ต้อง API key) ดึงพยากรณ์ 3 วัน
/// Cache: บันทึก 1 ครั้งต่อวัน → วัดจาก calendar date (ไม่ใช่ 24h)
/// Rolling window: วันนี้ → พรุ่งนี้ → มะรืนนี้ — refresh อัตโนมัติเมื่อขึ้นวันใหม่

class WeatherService {
  static final WeatherService _instance = WeatherService._internal();
  factory WeatherService() => _instance;
  WeatherService._internal();

  static const String _cacheKey = 'weather_forecast_v1';

  WeatherForecast? _cached;

  /// ข้อมูลที่ cache อยู่ (sync) — null ถ้ายังไม่มีหรือหมดอายุ
  WeatherForecast? get current => (_cached?.isFresh == true) ? _cached : null;

  // ──────────────────────────────────────────────────────────
  // 🌐 Public API
  // ──────────────────────────────────────────────────────────

  /// ดึง forecast 3 วัน (cache ถ้ายังเป็นวันเดียวกัน)
  Future<WeatherForecast?> getForecast() async {
    // 1. In-memory cache
    if (_cached != null && _cached!.isFresh) return _cached;

    // 2. SharedPreferences cache
    await _loadFromPrefs();
    if (_cached != null && _cached!.isFresh) return _cached;

    // 3. Fetch fresh from Open-Meteo
    return _fetchFromApi();
  }

  /// ข้อมูลวันนี้ (shortcut สำหรับ UI chip)
  Future<DayForecast?> getTodayForecast() async {
    final forecast = await getForecast();
    return forecast?.today;
  }

  /// Context string สำหรับ LLM (3 วัน)
  /// ตัวอย่าง:
  /// [Weather]
  /// วันนี้: ☀️ สูง 32°C / ต่ำ 24°C — แจ่มใส
  /// พรุ่งนี้: 🌧️ สูง 28°C / ต่ำ 23°C — มีฝน
  /// มะรืนนี้: ☁️ สูง 29°C / ต่ำ 22°C — มีเมฆมาก
  Future<String?> getContextString() async {
    final forecast = await getForecast();
    return forecast?.contextString;
  }

  // ──────────────────────────────────────────────────────────
  // 💾 Cache
  // ──────────────────────────────────────────────────────────

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);
      if (json == null) return;
      _cached = WeatherForecast.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      debugPrint('🌤️ Weather loaded from cache: ${_cached?.isFresh}');
    } catch (e) {
      debugPrint('⚠️ Weather cache load failed: $e');
    }
  }

  Future<void> _saveToPrefs(WeatherForecast forecast) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(forecast.toJson()));
    } catch (e) {
      debugPrint('⚠️ Weather cache save failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  // 🌐 API Fetch
  // ──────────────────────────────────────────────────────────

  Future<WeatherForecast?> _fetchFromApi() async {
    try {
      // ตรวจ location permission แบบ silent
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('🌤️ Weather: no location permission');
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 5),
      );

      // Open-Meteo: 3-day daily forecast
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${pos.latitude}&longitude=${pos.longitude}'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min'
        '&forecast_days=3'
        '&timezone=auto',
      );

      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        debugPrint('⚠️ Open-Meteo HTTP ${res.statusCode}');
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final daily = data['daily'] as Map<String, dynamic>;

      final times = (daily['time'] as List).cast<String>();
      final codes = (daily['weather_code'] as List).cast<int>();
      final maxTemps = (daily['temperature_2m_max'] as List)
          .map((v) => (v as num).toDouble())
          .toList();
      final minTemps = (daily['temperature_2m_min'] as List)
          .map((v) => (v as num).toDouble())
          .toList();

      final days = List.generate(
        times.length,
        (i) => DayForecast(
          date: DateTime.parse(times[i]),
          maxTemp: maxTemps[i],
          minTemp: minTemps[i],
          weatherCode: codes[i],
        ),
      );

      _cached = WeatherForecast(
        days: days,
        fetchedAt: DateTime.now(),
        lat: pos.latitude,
        lon: pos.longitude,
      );

      await _saveToPrefs(_cached!);
      debugPrint('🌤️ Weather fetched: ${days.map((d) => "${d.dayLabel}=${d.emoji}${d.maxTemp.round()}°").join(", ")}');
      return _cached;
    } catch (e) {
      debugPrint('⚠️ Weather fetch failed: $e');
      return null;
    }
  }
}

// ══════════════════════════════════════════════════════════════
// 📦 Data Models
// ══════════════════════════════════════════════════════════════

/// พยากรณ์ 3 วัน (rolling window: วันนี้ + 2 วันข้างหน้า)
class WeatherForecast {
  final List<DayForecast> days;
  final DateTime fetchedAt;
  final double lat;
  final double lon;

  const WeatherForecast({
    required this.days,
    required this.fetchedAt,
    required this.lat,
    required this.lon,
  });

  DayForecast? get today => days.isNotEmpty ? days[0] : null;
  DayForecast? get tomorrow => days.length > 1 ? days[1] : null;
  DayForecast? get dayAfter => days.length > 2 ? days[2] : null;

  /// ยัง fresh อยู่ถ้า fetch ภายในวันปฏิทินเดียวกัน
  bool get isFresh {
    final now = DateTime.now();
    final fetchDay = DateTime(fetchedAt.year, fetchedAt.month, fetchedAt.day);
    final today = DateTime(now.year, now.month, now.day);
    return fetchDay == today;
  }

  /// Context string สำหรับ LLM prompt (ประหยัด token)
  String get contextString {
    final sb = StringBuffer('[Weather]\n');
    for (final d in days) {
      sb.writeln(
        '${d.dayLabel}: ${d.emoji} สูง ${d.maxTemp.round()}°C / ต่ำ ${d.minTemp.round()}°C — ${d.description}',
      );
    }
    return sb.toString().trim();
  }

  Map<String, dynamic> toJson() => {
        'days': days.map((d) => d.toJson()).toList(),
        'fetchedAt': fetchedAt.toIso8601String(),
        'lat': lat,
        'lon': lon,
      };

  factory WeatherForecast.fromJson(Map<String, dynamic> j) => WeatherForecast(
        days: (j['days'] as List)
            .map((d) => DayForecast.fromJson(d as Map<String, dynamic>))
            .toList(),
        fetchedAt: DateTime.parse(j['fetchedAt'] as String),
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );
}

/// พยากรณ์รายวัน
class DayForecast {
  final DateTime date;
  final double maxTemp;
  final double minTemp;
  final int weatherCode;

  const DayForecast({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.weatherCode,
  });

  // WMO Weather Codes → emoji / description
  String get emoji {
    if (weatherCode == 0) return '☀️';
    if (weatherCode <= 2) return '⛅';
    if (weatherCode <= 3) return '☁️';
    if (weatherCode <= 51) return '🌫️';
    if (weatherCode <= 67) return '🌧️';
    if (weatherCode <= 77) return '❄️';
    return '⛈️';
  }

  String get description {
    if (weatherCode == 0) return 'แจ่มใส';
    if (weatherCode <= 2) return 'มีเมฆบางส่วน';
    if (weatherCode <= 3) return 'มีเมฆมาก';
    if (weatherCode <= 51) return 'มีหมอก';
    if (weatherCode <= 67) return 'มีฝน';
    if (weatherCode <= 77) return 'มีหิมะ';
    return 'พายุฝน';
  }

  /// วันที่แบบภาษาไทย relative to today
  String get dayLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisDate = DateTime(date.year, date.month, date.day);
    final diff = thisDate.difference(today).inDays;
    if (diff == 0) return 'วันนี้';
    if (diff == 1) return 'พรุ่งนี้';
    if (diff == 2) return 'มะรืนนี้';
    return '${date.day}/${date.month}';
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'maxTemp': maxTemp,
        'minTemp': minTemp,
        'weatherCode': weatherCode,
      };

  factory DayForecast.fromJson(Map<String, dynamic> j) => DayForecast(
        date: DateTime.parse(j['date'] as String),
        maxTemp: (j['maxTemp'] as num).toDouble(),
        minTemp: (j['minTemp'] as num).toDouble(),
        weatherCode: j['weatherCode'] as int,
      );
}
