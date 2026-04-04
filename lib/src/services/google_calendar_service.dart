import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:http/http.dart' as http;

class GoogleCalendarService {
  final GoogleSignIn _googleSignIn;
  cal.CalendarApi? _calendarApi;
  GoogleSignInAccount? _currentAccount;

  GoogleCalendarService({GoogleSignIn? googleSignIn})
    : _googleSignIn =
          googleSignIn ??
          GoogleSignIn(scopes: ['https://www.googleapis.com/auth/calendar']);

  /// Kiểm tra xem người dùng đã đăng nhập Google chưa
  Future<bool> isSignedIn() async {
    _currentAccount = _googleSignIn.currentUser;
    return _currentAccount != null;
  }

  /// Đăng nhập Google
  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentAccount = await _googleSignIn.signIn();
      if (_currentAccount != null) {
        await _initializeCalendarApi();
      }
      return _currentAccount;
    } catch (e) {
      debugPrint('Lỗi đăng nhập Google: $e');
      return null;
    }
  }

  /// Đăng xuất Google
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _calendarApi = null;
    _currentAccount = null;
  }

  /// Khởi tạo Calendar API
  Future<void> _initializeCalendarApi() async {
    if (_currentAccount == null) return;

    try {
      final headers = await _currentAccount!.authHeaders;
      final authenticatedClient = _GoogleSignInHttpClient(headers);

      _calendarApi = cal.CalendarApi(authenticatedClient);
    } catch (e) {
      debugPrint('Lỗi khởi tạo Calendar API: $e');
    }
  }

  /// Lấy danh sách calendar
  Future<List<cal.CalendarListEntry>> getCalendarList() async {
    if (_calendarApi == null) {
      await _initializeCalendarApi();
    }

    if (_calendarApi == null) {
      throw Exception('Calendar API không được khởi tạo');
    }

    try {
      final calendarList = await _calendarApi!.calendarList.list();
      return calendarList.items ?? [];
    } catch (e) {
      debugPrint('Lỗi lấy danh sách calendar: $e');
      rethrow;
    }
  }

  /// Tạo sự kiện trên Google Calendar
  /// Trả về event ID nếu thành công
  Future<String?> createEvent({
    required String calendarId,
    required String title,
    required String description,
    required DateTime startTime,
    Duration? duration,
  }) async {
    if (_calendarApi == null) {
      await _initializeCalendarApi();
    }

    if (_calendarApi == null) {
      throw Exception('Calendar API không được khởi tạo');
    }

    try {
      final endTime = startTime.add(duration ?? const Duration(hours: 1));

      final event = cal.Event(
        summary: title,
        description: description,
        start: cal.EventDateTime(
          dateTime: startTime,
          timeZone: 'Asia/Ho_Chi_Minh',
        ),
        end: cal.EventDateTime(dateTime: endTime, timeZone: 'Asia/Ho_Chi_Minh'),
      );

      final createdEvent = await _calendarApi!.events.insert(event, calendarId);

      return createdEvent.id;
    } catch (e) {
      debugPrint('Lỗi tạo sự kiện: $e');
      rethrow;
    }
  }

  /// Xóa sự kiện khỏi Google Calendar
  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  }) async {
    if (_calendarApi == null) {
      await _initializeCalendarApi();
    }

    if (_calendarApi == null) {
      throw Exception('Calendar API không được khởi tạo');
    }

    try {
      await _calendarApi!.events.delete(calendarId, eventId);
    } catch (e) {
      debugPrint('Lỗi xóa sự kiện: $e');
      rethrow;
    }
  }

  /// Cập nhật sự kiện
  Future<void> updateEvent({
    required String calendarId,
    required String eventId,
    required String title,
    required String description,
    required DateTime startTime,
    Duration? duration,
  }) async {
    if (_calendarApi == null) {
      await _initializeCalendarApi();
    }

    if (_calendarApi == null) {
      throw Exception('Calendar API không được khởi tạo');
    }

    try {
      final endTime = startTime.add(duration ?? const Duration(hours: 1));

      final event = cal.Event(
        summary: title,
        description: description,
        start: cal.EventDateTime(
          dateTime: startTime,
          timeZone: 'Asia/Ho_Chi_Minh',
        ),
        end: cal.EventDateTime(dateTime: endTime, timeZone: 'Asia/Ho_Chi_Minh'),
      );

      await _calendarApi!.events.update(event, calendarId, eventId);
    } catch (e) {
      debugPrint('Lỗi cập nhật sự kiện: $e');
      rethrow;
    }
  }

  /// Lấy event theo ID
  Future<cal.Event?> getEvent({
    required String calendarId,
    required String eventId,
  }) async {
    if (_calendarApi == null) {
      await _initializeCalendarApi();
    }

    if (_calendarApi == null) {
      throw Exception('Calendar API không được khởi tạo');
    }

    try {
      final event = await _calendarApi!.events.get(calendarId, eventId);
      return event;
    } catch (e) {
      debugPrint('Lỗi lấy event: $e');
      return null;
    }
  }
}

/// HTTP client cho Google API
class _GoogleSignInHttpClient extends http.BaseClient {
  final Map<String, String> _headers;

  _GoogleSignInHttpClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return http.Client().send(request);
  }
}
