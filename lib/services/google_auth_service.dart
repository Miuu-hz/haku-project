import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 🔐 Google Auth Service - Google Login + Calendar Sync
///
/// Features:
/// - Google Sign In
/// - Sync objectives ↔ Google Calendar
/// - ใช้ Google account ช่วย web search (ลด block rate)
/// - Mock Mode สำหรับทดสอบ UI

class GoogleAuthService {
  static final GoogleAuthService _instance = GoogleAuthService._internal();
  factory GoogleAuthService() => _instance;
  GoogleAuthService._internal();

  // ═══════════════════════════════════════════════════════════
  // 🎭 MOCK MODE (สำหรับทดสอบ UI โดยไม่ต้องมี Google Config)
  // ═══════════════════════════════════════════════════════════
  static bool _mockMode = false;
  static bool get isMockMode => _mockMode;
  
  /// 🎭 Enable/Disable Mock Mode
  static void setMockMode(bool enable) {
    _mockMode = enable;
    debugPrint(_mockMode ? '🎭 Mock Mode ENABLED' : '🔰 Real Mode ENABLED');
  }

  /// Mock User Data
  GoogleSignInAccount? _mockUser;
  final List<CalendarEvent> _mockEvents = [];
  int _mockEventIdCounter = 1;

  static const String _userKey = 'google_user_data';
  static const String _tokenKey = 'google_access_token';

  // Google Sign In
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/calendar',
      'https://www.googleapis.com/auth/calendar.events',
    ],
  );

  GoogleSignInAccount? _currentUser;
  String? _accessToken;

  bool _isInitialized = false;

  // Getters
  bool get isSignedIn => _mockMode ? _mockUser != null : _currentUser != null;
  GoogleSignInAccount? get currentUser => _mockMode ? _mockUser : _currentUser;
  String? get userEmail => _mockMode 
      ? (_mockUser as _MockGoogleAccount?)?.email 
      : _currentUser?.email;
  String? get userName => _mockMode 
      ? (_mockUser as _MockGoogleAccount?)?.displayName 
      : _currentUser?.displayName;
  String? get userPhoto => _mockMode 
      ? (_mockUser as _MockGoogleAccount?)?.photoUrl 
      : _currentUser?.photoUrl;

  /// 🚀 Initialize service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // 🎭 Mock Mode: ไม่ต้อง initialize จริง
    if (_mockMode) {
      _isInitialized = true;
      _initMockEvents();
      debugPrint('✅ Google Auth Service initialized (MOCK MODE)');
      return;
    }

    // Try silent sign in
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        await _refreshToken();
        debugPrint('✅ Google auto sign-in: ${_currentUser!.email}');
      }
    } catch (e) {
      debugPrint('⚠️ Google silent sign-in failed: $e');
    }

    _isInitialized = true;
    debugPrint('✅ Google Auth Service initialized');
    debugPrint('   - Signed in: $isSignedIn');
  }

  /// 🎭 Initialize Mock Events
  void _initMockEvents() {
    final now = DateTime.now();
    _mockEvents.addAll([
      CalendarEvent(
        id: 'mock_1',
        title: '🎯 ประชุมทีม Haku',
        startTime: now.add(const Duration(hours: 2)),
        endTime: now.add(const Duration(hours: 3)),
        description: 'ประชุมติดตามความคืบหน้า',
        location: 'Google Meet',
        htmlLink: 'https://calendar.google.com',
      ),
      CalendarEvent(
        id: 'mock_2',
        title: '🍜 นัดกินข้าวกับเพื่อน',
        startTime: now.add(const Duration(days: 1, hours: 12)),
        endTime: now.add(const Duration(days: 1, hours: 14)),
        description: 'นัดที่ร้านอาหารญี่ปุ่น',
        location: 'Shibuya Restaurant',
        htmlLink: 'https://calendar.google.com',
      ),
      CalendarEvent(
        id: 'mock_3',
        title: '💪 ออกกำลังกาย',
        startTime: now.add(const Duration(days: 2, hours: 18)),
        endTime: now.add(const Duration(days: 2, hours: 19, minutes: 30)),
        description: 'Leg day',
        location: 'Fitness First',
        htmlLink: 'https://calendar.google.com',
      ),
    ]);
  }

  // ============================================================
  // 🔐 AUTHENTICATION
  // ============================================================

  /// 🔐 Sign in with Google
  Future<bool> signIn() async {
    // 🎭 Mock Mode
    if (_mockMode) {
      await Future<void>.delayed(const Duration(milliseconds: 800)); // Simulate delay
      _mockUser = _MockGoogleAccount(
        email: 'demo@haku.app',
        displayName: 'Demo User',
        photoUrl: null,
      );
      debugPrint('🎭 Mock sign-in success: demo@haku.app');
      return true;
    }

    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser != null) {
        await _refreshToken();
        await _saveUserData();
        debugPrint('✅ Google sign-in success: ${_currentUser!.email}');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Google sign-in error: $e');
    }
    return false;
  }

  /// 🚪 Sign out
  Future<void> signOut() async {
    // 🎭 Mock Mode
    if (_mockMode) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _mockUser = null;
      _mockEvents.clear();
      _initMockEvents();
      debugPrint('🎭 Mock sign-out success');
      return;
    }

    try {
      await _googleSignIn.signOut();
      _currentUser = null;
      _accessToken = null;
      await _clearUserData();
      debugPrint('✅ Google sign-out success');
    } catch (e) {
      debugPrint('⚠️ Google sign-out error: $e');
    }
  }

  /// 🔄 Refresh access token
  Future<void> _refreshToken() async {
    try {
      final auth = await _currentUser?.authentication;
      _accessToken = auth?.accessToken;

      if (_accessToken != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, _accessToken!);
      }
    } catch (e) {
      debugPrint('⚠️ Token refresh error: $e');
    }
  }

  /// 💾 Save user data
  Future<void> _saveUserData() async {
    if (_currentUser == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode({
      'email': _currentUser!.email,
      'displayName': _currentUser!.displayName,
      'photoUrl': _currentUser!.photoUrl,
    }));
  }

  /// 🗑️ Clear user data
  Future<void> _clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_tokenKey);
  }

  // ============================================================
  // 📅 GOOGLE CALENDAR
  // ============================================================

  /// 📅 สร้าง event ใน Google Calendar
  Future<CalendarEventResult> createCalendarEvent({
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    String? description,
    String? location,
    List<String>? attendeeEmails,
    bool sendNotifications = false,
  }) async {
    if (!isSignedIn) {
      return CalendarEventResult(
        success: false,
        error: 'Not signed in to Google',
      );
    }

    // 🎭 Mock Mode
    if (_mockMode) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      endTime ??= startTime.add(const Duration(hours: 1));
      
      final event = CalendarEvent(
        id: 'mock_${_mockEventIdCounter++}',
        title: title,
        startTime: startTime,
        endTime: endTime,
        description: description,
        location: location,
        htmlLink: 'https://calendar.google.com/mock',
      );
      
      _mockEvents.add(event);
      _mockEvents.sort((a, b) => (a.startTime ?? DateTime.now())
          .compareTo(b.startTime ?? DateTime.now()));
      
      debugPrint('🎭 Mock event created: ${event.title}');
      return CalendarEventResult(
        success: true,
        eventId: event.id,
        eventLink: event.htmlLink,
      );
    }

    if (_accessToken == null) {
      return CalendarEventResult(
        success: false,
        error: 'Not signed in to Google',
      );
    }

    try {
      // Default end time = start + 1 hour
      endTime ??= startTime.add(const Duration(hours: 1));

      final event = {
        'summary': title,
        'start': {
          'dateTime': startTime.toIso8601String(),
          'timeZone': 'Asia/Bangkok',
        },
        'end': {
          'dateTime': endTime.toIso8601String(),
          'timeZone': 'Asia/Bangkok',
        },
        if (description != null) 'description': description,
        if (location != null) 'location': location,
        if (attendeeEmails != null && attendeeEmails.isNotEmpty)
          'attendees': attendeeEmails.map((e) => {'email': e}).toList(),
        'reminders': {
          'useDefault': false,
          'overrides': [
            {'method': 'popup', 'minutes': 30},
            {'method': 'popup', 'minutes': 10},
          ],
        },
      };

      final response = await http.post(
        Uri.https(
          'www.googleapis.com',
          '/calendar/v3/calendars/primary/events',
          {'sendUpdates': sendNotifications ? 'all' : 'none'},
        ),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(event),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Calendar event created: ${data['id']}');

        return CalendarEventResult(
          success: true,
          eventId: data['id'] as String,
          eventLink: data['htmlLink'] as String?,
        );
      } else {
        debugPrint('⚠️ Calendar API error: ${response.statusCode}');
        debugPrint('   Body: ${response.body}');

        // Token expired? Try refresh
        if (response.statusCode == 401) {
          await _refreshToken();
          // Could retry here
        }

        return CalendarEventResult(
          success: false,
          error: 'API error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Create event error: $e');
      return CalendarEventResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// 📋 ดึง events จาก Calendar
  Future<List<CalendarEvent>> getUpcomingEvents({
    int maxResults = 10,
    DateTime? timeMin,
    DateTime? timeMax,
  }) async {
    if (!isSignedIn) {
      return [];
    }

    // 🎭 Mock Mode
    if (_mockMode) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      timeMin ??= DateTime.now();
      timeMax ??= DateTime.now().add(const Duration(days: 7));
      
      return _mockEvents
          .where((e) {
            final start = e.startTime;
            if (start == null) return false;
            return start.isAfter(timeMin!) && start.isBefore(timeMax!);
          })
          .take(maxResults)
          .toList();
    }

    if (_accessToken == null) return [];

    try {
      timeMin ??= DateTime.now();
      timeMax ??= DateTime.now().add(const Duration(days: 7));

      final response = await http.get(
        Uri.https(
          'www.googleapis.com',
          '/calendar/v3/calendars/primary/events',
          {
            'timeMin': timeMin.toUtc().toIso8601String(),
            'timeMax': timeMax.toUtc().toIso8601String(),
            'maxResults': maxResults.toString(),
            'singleEvents': 'true',
            'orderBy': 'startTime',
          },
        ),
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List? ?? [];

        return items.map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Get events error: $e');
    }

    return [];
  }

  /// 🗑️ ลบ event
  Future<bool> deleteCalendarEvent(String eventId) async {
    if (!isSignedIn) return false;

    // 🎭 Mock Mode
    if (_mockMode) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _mockEvents.removeWhere((e) => e.id == eventId);
      debugPrint('🎭 Mock event deleted: $eventId');
      return true;
    }

    if (_accessToken == null) return false;

    try {
      final response = await http.delete(
        Uri.https(
          'www.googleapis.com',
          '/calendar/v3/calendars/primary/events/$eventId',
        ),
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      );

      return response.statusCode == 204;
    } catch (e) {
      debugPrint('⚠️ Delete event error: $e');
    }

    return false;
  }

  /// 🔄 อัพเดต event
  Future<bool> updateCalendarEvent({
    required String eventId,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    String? description,
    String? location,
  }) async {
    if (!isSignedIn) return false;

    // 🎭 Mock Mode
    if (_mockMode) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final index = _mockEvents.indexWhere((e) => e.id == eventId);
      if (index != -1) {
        final old = _mockEvents[index];
        _mockEvents[index] = CalendarEvent(
          id: old.id,
          title: title ?? old.title,
          startTime: startTime ?? old.startTime,
          endTime: endTime ?? old.endTime,
          description: description ?? old.description,
          location: location ?? old.location,
          htmlLink: old.htmlLink,
        );
        debugPrint('🎭 Mock event updated: $eventId');
        return true;
      }
      return false;
    }

    if (_accessToken == null) return false;

    try {
      final updates = <String, dynamic>{};

      if (title != null) updates['summary'] = title;
      if (description != null) updates['description'] = description;
      if (location != null) updates['location'] = location;
      if (startTime != null) {
        updates['start'] = {
          'dateTime': startTime.toIso8601String(),
          'timeZone': 'Asia/Bangkok',
        };
      }
      if (endTime != null) {
        updates['end'] = {
          'dateTime': endTime.toIso8601String(),
          'timeZone': 'Asia/Bangkok',
        };
      }

      final response = await http.patch(
        Uri.https(
          'www.googleapis.com',
          '/calendar/v3/calendars/primary/events/$eventId',
        ),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(updates),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ Update event error: $e');
    }

    return false;
  }

  // ============================================================
  // 🔄 SYNC OBJECTIVES TO CALENDAR
  // ============================================================

  /// 🔄 Sync objective ไป Calendar
  Future<CalendarEventResult> syncObjectiveToCalendar({
    required String objectiveId,
    required String title,
    required DateTime dueDate,
    String? description,
    String? location,
  }) =>
      // สร้าง event ที่เวลา due
      createCalendarEvent(
        title: '🎯 $title',
        startTime: dueDate,
        description: '''
Objective จาก Haku
ID: $objectiveId

$description
''',
        location: location,
      );

  /// 📊 Get calendar stats
  Future<Map<String, dynamic>> getCalendarStats() async {
    final events = await getUpcomingEvents(
      maxResults: 50,
      timeMax: DateTime.now().add(const Duration(days: 30)),
    );

    final busyDays = <DateTime>{};
    for (final event in events) {
      if (event.startTime != null) {
        busyDays.add(DateTime(
          event.startTime!.year,
          event.startTime!.month,
          event.startTime!.day,
        ));
      }
    }

    return {
      'totalEvents': events.length,
      'busyDays': busyDays.length,
      'upcomingToday': events.where((e) {
        final today = DateTime.now();
        return e.startTime?.day == today.day &&
            e.startTime?.month == today.month &&
            e.startTime?.year == today.year;
      }).length,
    };
  }
}

// ============================================================
// 🎭 MOCK CLASSES (สำหรับทดสอบ)
// ============================================================

/// Mock Google Account สำหรับ Mock Mode
class _MockGoogleAccount implements GoogleSignInAccount {
  @override
  final String email;
  @override
  final String? displayName;
  @override
  final String? photoUrl;
  @override
  final String id = 'mock_user_id';
  @override
  final String? serverAuthCode = null;

  _MockGoogleAccount({
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  @override
  Future<GoogleSignInAuthentication> get authentication async {
    return _MockGoogleAuth();
  }

  @override
  Future<Map<String, String>> get authHeaders async => {
    'Authorization': 'Bearer mock_token',
  };

  @override
  Future<void> clearAuthCache() async {}
}

/// Mock Google Auth
class _MockGoogleAuth implements GoogleSignInAuthentication {
  @override
  String get accessToken => 'mock_access_token';
  @override
  String? get idToken => 'mock_id_token';
  @override
  String? get serverAuthCode => null;
}

// ============================================================
// 📦 DATA MODELS
// ============================================================

/// 📅 Calendar Event
class CalendarEvent {
  final String id;
  final String title;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? description;
  final String? location;
  final String? htmlLink;

  CalendarEvent({
    required this.id,
    required this.title,
    this.startTime,
    this.endTime,
    this.description,
    this.location,
    this.htmlLink,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    DateTime? parseDateTime(dynamic dateTimeObj) {
      if (dateTimeObj == null) return null;
      if (dateTimeObj is Map) {
        final dt = dateTimeObj['dateTime'] ?? dateTimeObj['date'];
        if (dt != null) return DateTime.parse(dt as String);
      }
      return null;
    }

    return CalendarEvent(
      id: json['id'] as String,
      title: json['summary'] as String? ?? 'Untitled',
      startTime: parseDateTime(json['start']),
      endTime: parseDateTime(json['end']),
      description: json['description'] as String?,
      location: json['location'] as String?,
      htmlLink: json['htmlLink'] as String?,
    );
  }

  String get displayTime {
    if (startTime == null) return '';
    final hour = startTime!.hour.toString().padLeft(2, '0');
    final minute = startTime!.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get displayDate {
    if (startTime == null) return '';
    final day = startTime!.day.toString().padLeft(2, '0');
    final month = startTime!.month.toString().padLeft(2, '0');
    return '$day/$month';
  }
}

/// ✅ Calendar Event Result
class CalendarEventResult {
  final bool success;
  final String? eventId;
  final String? eventLink;
  final String? error;

  CalendarEventResult({
    required this.success,
    this.eventId,
    this.eventLink,
    this.error,
  });
}
