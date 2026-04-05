import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;

import '../services/google_calendar_service.dart';

final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  return GoogleSignIn(scopes: ['https://www.googleapis.com/auth/calendar']);
});

final googleCalendarServiceProvider = Provider<GoogleCalendarService>((ref) {
  final googleSignIn = ref.watch(googleSignInProvider);
  return GoogleCalendarService(googleSignIn: googleSignIn);
});

final googleSignInStateProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(googleCalendarServiceProvider);
  return await service.isSignedIn();
});

final googleCalendarListProvider = FutureProvider<List<cal.CalendarListEntry>>((
  ref,
) async {
  final service = ref.watch(googleCalendarServiceProvider);
  try {
    return await service.getCalendarList();
  } catch (e) {
    debugPrint('Lỗi tải danh sách calendar: $e');
    return [];
  }
});

final googleSignInProvider2 = FutureProvider<GoogleSignInAccount?>((ref) async {
  final googleSignIn = ref.watch(googleSignInProvider);
  return googleSignIn.currentUser ??
      (await googleSignIn.signInSilently().catchError((_) => null));
});

class GoogleCalendarNotifier extends StateNotifier<Map<String, String>> {
  final GoogleCalendarService _service;

  GoogleCalendarNotifier(this._service) : super({});

  /// Sync nhật ký giọng nói lên Google Calendar
  /// Trả về event ID nếu thành công
  Future<String?> syncVoiceDiaryToCalendar({
    required String text,
    required DateTime createdAt,
    String? calendarId,
  }) async {
    try {
      // Nếu chưa chọn calendar, lấy calendar mặc định (primary)
      final targetCalendarId = calendarId ?? 'primary';

      final eventId = await _service.createEvent(
        calendarId: targetCalendarId,
        title: 'Nhật ký',
        description: text,
        startTime: createdAt,
        duration: const Duration(hours: 1),
      );

      if (eventId != null) {
        // Lưu mapping giữa voice diary id và calendar event id
        state = {...state, 'voiceDiary_$createdAt': eventId};
      }

      return eventId;
    } catch (e) {
      debugPrint('Lỗi sync nhật ký lên Google Calendar: $e');
      rethrow;
    }
  }

  /// Xóa event khỏi Google Calendar
  Future<void> removeFromCalendar({
    required String voiceDiaryId,
    required String? calendarId,
    required String? eventId,
  }) async {
    if (eventId == null) return;

    try {
      final targetCalendarId = calendarId ?? 'primary';
      await _service.deleteEvent(
        calendarId: targetCalendarId,
        eventId: eventId,
      );

      // Xóa mapping
      state = {...state}..remove('voiceDiary_$voiceDiaryId');
    } catch (e) {
      debugPrint('Lỗi xóa event khỏe Google Calendar: $e');
      rethrow;
    }
  }
}

final googleCalendarNotifierProvider =
    StateNotifierProvider<GoogleCalendarNotifier, Map<String, String>>((ref) {
      final service = ref.watch(googleCalendarServiceProvider);
      return GoogleCalendarNotifier(service);
    });
