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

class GoogleAuthService {
  static final GoogleAuthService _instance = GoogleAuthService._internal();
  factory GoogleAuthService() => _instance;
  GoogleAuthService._internal();

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
  bool get isSignedIn => _currentUser != null;
  GoogleSignInAccount? get currentUser => _currentUser;
  String? get userEmail => _currentUser?.email;
  String? get userName => _currentUser?.displayName;
  String? get userPhoto => _currentUser?.photoUrl;

  /// 🚀 Initialize service
  Future<void> initialize() async {
    if (_isInitialized) return;

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

  // ============================================================
  // 🔐 AUTHENTICATION
  // ============================================================

  /// 🔐 Sign in with Google
  Future<bool> signIn() async {
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
    if (!isSignedIn || _accessToken == null) {
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
    if (!isSignedIn || _accessToken == null) {
      return [];
    }

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

        return items.map((e) => CalendarEvent.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Get events error: $e');
    }

    return [];
  }

  /// 🗑️ ลบ event
  Future<bool> deleteCalendarEvent(String eventId) async {
    if (!isSignedIn || _accessToken == null) return false;

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
    if (!isSignedIn || _accessToken == null) return false;

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
  }) async {
    // สร้าง event ที่เวลา due
    return createCalendarEvent(
      title: '🎯 $title',
      startTime: dueDate,
      description: '''
Objective จาก Haku
ID: $objectiveId

$description
''',
      location: location,
    );
  }

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
