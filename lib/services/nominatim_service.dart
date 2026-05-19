import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 📍 NominatimService — reverse geocode GPS → ชื่อพื้นที่ (ไม่ส่ง GPS ไปไหนอีก)
///
/// ใช้ OpenStreetMap Nominatim (free, non-profit)
/// Output: NominatimAddress ที่มี suburb + county สำหรับ build search query
class NominatimService {
  static final NominatimService _instance = NominatimService._internal();
  factory NominatimService() => _instance;
  NominatimService._internal();

  static const String _baseUrl = 'nominatim.openstreetmap.org';

  // Cache ง่ายๆ: key = "lat_lng_rounded", value = address
  final Map<String, NominatimAddress> _cache = {};

  /// 🔄 Reverse geocode: GPS → ชื่อพื้นที่
  ///
  /// [zoom] = 14 → ระดับ suburb/tambon (เหมาะสำหรับค้นร้านค้า)
  Future<NominatimAddress?> reverseGeocode(double lat, double lng) async {
    // round ทศนิยม 2 ตำแหน่ง (~1km) เพื่อใช้เป็น cache key
    final cacheKey =
        '${lat.toStringAsFixed(2)}_${lng.toStringAsFixed(2)}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    try {
      final uri = Uri.https(_baseUrl, '/reverse', {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'json',
        'zoom': '14',
        'accept-language': 'th',
      });

      final resp = await http.get(uri, headers: {
        'User-Agent': 'HakuApp/1.0 (contact@haku.app)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr == null) return null;

      final result = NominatimAddress.fromJson(addr);
      _cache[cacheKey] = result;
      debugPrint('📍 Nominatim: ${result.toSearchSuffix()}');
      return result;
    } catch (e) {
      debugPrint('⚠️ Nominatim reverse failed: $e');
      return null;
    }
  }
}

/// 📦 ที่อยู่จาก Nominatim
class NominatimAddress {
  final String? village;    // บ้านโคก
  final String? suburb;     // ยางตลาด (ตำบล)
  final String? town;       // เมืองกาฬสินธุ์ (ถ้าอยู่ในอำเภอเมือง)
  final String? city;       // กาฬสินธุ์
  final String? county;     // อำเภอยางตลาด
  final String? state;      // กาฬสินธุ์ (จังหวัด)

  NominatimAddress({
    this.village,
    this.suburb,
    this.town,
    this.city,
    this.county,
    this.state,
  });

  factory NominatimAddress.fromJson(Map<String, dynamic> json) {
    // strip "อำเภอ"/"เขต" prefix ออก เหลือแค่ชื่อ
    String? clean(String? s) {
      if (s == null) return null;
      return s
          .replaceFirst(RegExp(r'^อำเภอ\s*'), '')
          .replaceFirst(RegExp(r'^เขต\s*'), '')
          .trim();
    }

    return NominatimAddress(
      village: json['village'] as String?,
      suburb: json['suburb'] as String? ?? json['quarter'] as String?,
      town: json['town'] as String?,
      city: json['city'] as String?,
      county: clean(json['county'] as String?),
      state: json['state'] as String?,
    );
  }

  /// สร้าง suffix สำหรับ search query เช่น "ยางตลาด กาฬสินธุ์"
  ///
  /// เลือก: suburb (ตำบล) + county/state (อำเภอ/จังหวัด)
  String toSearchSuffix() {
    final parts = <String>[];

    // ระดับตำบล/แขวง
    final tambon = suburb ?? town;
    if (tambon != null && tambon.isNotEmpty) parts.add(tambon);

    // ระดับอำเภอ (ถ้ามี และต่างจากตำบล)
    if (county != null && county!.isNotEmpty && county != tambon) {
      parts.add(county!);
    }

    // จังหวัด
    final province = state ?? city;
    if (province != null && province.isNotEmpty) parts.add(province);

    return parts.join(' ');
  }

  @override
  String toString() => toSearchSuffix();
}
