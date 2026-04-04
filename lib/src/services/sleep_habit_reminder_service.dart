import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class SleepHabitReminderConfig {
  final bool enabled;
  final int dailyReminderCount;
  final TimeOfDay sleepReminderTime;

  const SleepHabitReminderConfig({
    required this.enabled,
    required this.dailyReminderCount,
    required this.sleepReminderTime,
  });

  static const defaultConfig = SleepHabitReminderConfig(
    enabled: false,
    dailyReminderCount: 3,
    sleepReminderTime: TimeOfDay(hour: 22, minute: 0),
  );
}

class SleepHabitReminderService {
  static const String _enabledKey = 'sleep_habit_reminder_enabled';
  static const String _countKey = 'sleep_habit_reminder_count';
  static const String _sleepHourKey = 'sleep_habit_sleep_hour';
  static const String _sleepMinuteKey = 'sleep_habit_sleep_minute';
  static const String _cloudCollection = 'settings';
  static const String _cloudDoc = 'sleepHabitReminder';
  static const int _waterReminderBaseId = 201;
  static const int _sleepReminderId = 300;
  static const int _maxReminderSlots = 10;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (!_initialized) {
      _initialized = true;
      tz.initializeTimeZones();

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _notifications.initialize(settings);

      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    await _syncLocalTimezone();
  }

  Future<void> _syncLocalTimezone() async {
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      final resolved = _resolveTimezoneIdentifier(timezoneInfo.identifier);
      tz.setLocalLocation(tz.getLocation(resolved));
    } catch (_) {
      // Keep the default location if the device timezone cannot be resolved.
    }
  }

  String _resolveTimezoneIdentifier(String rawIdentifier) {
    final raw = rawIdentifier.trim();
    if (raw.isNotEmpty) {
      try {
        tz.getLocation(raw);
        return raw;
      } catch (_) {}
    }

    final normalized = raw.toUpperCase().replaceAll(' ', '');
    final gmtMatch = RegExp(
      r'^(?:UTC|GMT)([+-])(\d{1,2})(?::?(\d{2}))?$',
    ).firstMatch(normalized);
    if (gmtMatch != null) {
      final sign = gmtMatch.group(1)!;
      final hour = int.tryParse(gmtMatch.group(2) ?? '') ?? 0;
      final minute = int.tryParse(gmtMatch.group(3) ?? '0') ?? 0;
      if (minute == 0 && hour <= 14) {
        final etcSign = sign == '+' ? '-' : '+';
        final etcName = 'Etc/GMT$etcSign$hour';
        try {
          tz.getLocation(etcName);
          return etcName;
        } catch (_) {}
      }
    }

    final offset = DateTime.now().timeZoneOffset;
    if (offset.inMinutes % 60 == 0) {
      final absHours = offset.inHours.abs();
      if (absHours <= 14) {
        final etcSign = offset.isNegative ? '+' : '-';
        final etcName = 'Etc/GMT$etcSign$absHours';
        try {
          tz.getLocation(etcName);
          return etcName;
        } catch (_) {}
      }
    }

    if (offset.inHours == 7 && offset.inMinutes.remainder(60) == 0) {
      try {
        tz.getLocation('Asia/Ho_Chi_Minh');
        return 'Asia/Ho_Chi_Minh';
      } catch (_) {}
    }

    return 'UTC';
  }

  Future<bool> requestPermission() async {
    return _requestSchedulingPermissions();
  }

  Future<bool> _requestSchedulingPermissions() async {
    final plugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (plugin == null) {
      return true;
    }

    final notificationsGranted = await plugin.requestNotificationsPermission();
    if (notificationsGranted == false) {
      return false;
    }

    final exactAlarmGranted = await plugin.requestExactAlarmsPermission();
    if (exactAlarmGranted == false) {
      return false;
    }

    return true;
  }

  Future<bool> _hasSchedulingPermissions() async {
    final plugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (plugin == null) {
      return true;
    }

    final notificationsEnabled = await plugin.areNotificationsEnabled();
    if (notificationsEnabled == false) {
      return false;
    }

    final canExact = await plugin.canScheduleExactNotifications();
    if (canExact == false) {
      return false;
    }

    return true;
  }

  Future<SleepHabitReminderConfig> loadConfig() async {
    return loadConfigForUid(null);
  }

  Future<SleepHabitReminderConfig> loadConfigForUid(String? uid) async {
    if (uid != null && uid.isNotEmpty) {
      final cloudConfig = await _loadCloudConfig(uid);
      if (cloudConfig != null) {
        await _cacheConfigLocally(cloudConfig);
        return cloudConfig;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final enabled =
        prefs.getBool(_enabledKey) ??
        SleepHabitReminderConfig.defaultConfig.enabled;
    final count = _normalizeCount(
      prefs.getInt(_countKey) ??
          SleepHabitReminderConfig.defaultConfig.dailyReminderCount,
    );
    final sleepHour =
        prefs.getInt(_sleepHourKey) ??
        SleepHabitReminderConfig.defaultConfig.sleepReminderTime.hour;
    final sleepMinute =
        prefs.getInt(_sleepMinuteKey) ??
        SleepHabitReminderConfig.defaultConfig.sleepReminderTime.minute;

    return SleepHabitReminderConfig(
      enabled: enabled,
      dailyReminderCount: count,
      sleepReminderTime: TimeOfDay(
        hour: sleepHour.clamp(0, 23),
        minute: sleepMinute.clamp(0, 59),
      ),
    );
  }

  Future<void> saveConfig(SleepHabitReminderConfig config) async {
    await saveConfigForUid(null, config);
  }

  Future<void> saveConfigForUid(
    String? uid,
    SleepHabitReminderConfig config,
  ) async {
    await _cacheConfigLocally(config);
    if (uid != null && uid.isNotEmpty) {
      try {
        await _saveCloudConfig(uid, config);
      } catch (_) {
        // Keep the local save so the UI remains usable if cloud sync fails.
      }
    }
  }

  Future<void> _cacheConfigLocally(SleepHabitReminderConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, config.enabled);
    await prefs.setInt(_countKey, _normalizeCount(config.dailyReminderCount));
    await prefs.setInt(_sleepHourKey, config.sleepReminderTime.hour);
    await prefs.setInt(_sleepMinuteKey, config.sleepReminderTime.minute);
  }

  Future<SleepHabitReminderConfig?> _loadCloudConfig(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(_cloudCollection)
          .doc(_cloudDoc)
          .get();

      if (!doc.exists) return null;

      final data = doc.data() ?? <String, dynamic>{};
      return SleepHabitReminderConfig(
        enabled:
            data['enabled'] as bool? ??
            SleepHabitReminderConfig.defaultConfig.enabled,
        dailyReminderCount: _normalizeCount(
          (data['dailyReminderCount'] as num?)?.toInt() ??
              SleepHabitReminderConfig.defaultConfig.dailyReminderCount,
        ),
        sleepReminderTime: TimeOfDay(
          hour:
              ((data['sleepHour'] as num?)?.toInt() ??
                      SleepHabitReminderConfig
                          .defaultConfig
                          .sleepReminderTime
                          .hour)
                  .clamp(0, 23),
          minute:
              ((data['sleepMinute'] as num?)?.toInt() ??
                      SleepHabitReminderConfig
                          .defaultConfig
                          .sleepReminderTime
                          .minute)
                  .clamp(0, 59),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCloudConfig(
    String uid,
    SleepHabitReminderConfig config,
  ) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection(_cloudCollection)
        .doc(_cloudDoc)
        .set({
          'enabled': config.enabled,
          'dailyReminderCount': _normalizeCount(config.dailyReminderCount),
          'sleepHour': config.sleepReminderTime.hour,
          'sleepMinute': config.sleepReminderTime.minute,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<bool> applyConfig({
    String? uid,
    SleepHabitReminderConfig? configOverride,
    bool requestPermission = true,
  }) async {
    await initialize();
    final config = configOverride ?? await loadConfigForUid(uid);
    if (!config.enabled) {
      await cancelAll();
      return true;
    }
    final granted = requestPermission
        ? await _requestSchedulingPermissions()
        : await _hasSchedulingPermissions();
    if (!granted) {
      return false;
    }
    await schedule(config);
    return true;
  }

  Future<bool> toggleEnabled(bool enabled, {String? uid}) async {
    final current = await loadConfigForUid(uid);
    final nextConfig = SleepHabitReminderConfig(
      enabled: enabled,
      dailyReminderCount: current.dailyReminderCount,
      sleepReminderTime: current.sleepReminderTime,
    );
    await saveConfigForUid(uid, nextConfig);
    if (enabled) {
      return applyConfig(uid: uid, configOverride: nextConfig);
    } else {
      await cancelAll();
      return true;
    }
  }

  Future<void> schedule(SleepHabitReminderConfig config) async {
    await initialize();
    await cancelAll();

    const reminderDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'health_daily_reminders',
        'Nhắc nhở sức khỏe hằng ngày',
        channelDescription: 'Nhắc uống nước, vận động và ngủ sớm',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    final times = _buildWaterReminderTimes(config.dailyReminderCount);
    for (
      var index = 0;
      index < times.length && index < _maxReminderSlots;
      index++
    ) {
      final time = times[index];
      final target = _nextInstanceOf(time.hour, time.minute);
      await _notifications.zonedSchedule(
        _waterReminderBaseId + index,
        'Nhắc uống nước và vận động',
        'Đến giờ uống nước và vận động nhẹ vài phút.',
        target,
        reminderDetails,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }

    final nextSleep = _nextInstanceOf(
      config.sleepReminderTime.hour,
      config.sleepReminderTime.minute,
    );
    final sleepBody =
        '${_formatTimeOfDay(config.sleepReminderTime)} rồi, hãy thư giãn và đi ngủ sớm nhé.';

    // Single daily reminder to avoid duplicate notifications.
    await _notifications.zonedSchedule(
      _sleepReminderId,
      'Nhắc ngủ sớm',
      sleepBody,
      nextSleep,
      reminderDetails,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelAll() async {
    for (var id = 0; id < _maxReminderSlots; id++) {
      await _notifications.cancel(_waterReminderBaseId + id);
    }
    await _notifications.cancel(_sleepReminderId);
    await _notifications.cancel(301);
  }

  int _normalizeCount(int value) {
    if (value < 1) return 1;
    if (value > 6) return 6;
    return value;
  }

  List<TimeOfDay> _buildWaterReminderTimes(int count) {
    final normalizedCount = _normalizeCount(count);
    if (normalizedCount == 1) {
      return const [TimeOfDay(hour: 12, minute: 0)];
    }

    const startMinutes = 9 * 60;
    const endMinutes = 18 * 60 + 30;
    final span = endMinutes - startMinutes;
    final result = <TimeOfDay>[];

    for (var index = 0; index < normalizedCount; index++) {
      final ratio = index / (normalizedCount - 1);
      final totalMinutes = startMinutes + (span * ratio).round();
      result.add(
        TimeOfDay(
          hour: (totalMinutes ~/ 60).clamp(0, 23),
          minute: totalMinutes % 60,
        ),
      );
    }

    return result;
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    final sameMinute =
        scheduled.year == now.year &&
        scheduled.month == now.month &&
        scheduled.day == now.day &&
        scheduled.hour == now.hour &&
        scheduled.minute == now.minute;

    if (scheduled.isBefore(now) && !sameMinute) {
      scheduled = scheduled.add(const Duration(days: 1));
    } else if (sameMinute && scheduled.isBefore(now)) {
      scheduled = now.add(const Duration(seconds: 5));
    }
    return scheduled;
  }

  String _formatTimeOfDay(TimeOfDay timeOfDay) {
    final hour = timeOfDay.hour.toString().padLeft(2, '0');
    final minute = timeOfDay.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
