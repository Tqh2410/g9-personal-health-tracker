import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:light/light.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StepLightPermissionResult {
  final bool hasNotificationPermission;
  final bool hasActivityPermission;
  final bool hasBatteryExemption;
  final bool hasPermanentDenied;
  final bool changed;

  const StepLightPermissionResult({
    required this.hasNotificationPermission,
    required this.hasActivityPermission,
    required this.hasBatteryExemption,
    required this.hasPermanentDenied,
    required this.changed,
  });
}

class StepLightMonitorService extends ChangeNotifier {
  static const _stepBaselineKey = 'step_light_baseline';
  static const _lastSedentaryNotifyKey = 'step_light_last_sedentary_notify';
  static const _syncStateDateKey = 'step_light_sync_date';
  static const _syncStateStepsKey = 'step_light_sync_steps';
  static const _deviceIdKey = 'step_light_device_id';
  static const _lastCalorieAlertDateKey = 'health_last_calorie_alert_date';
  static const _lastWaterGoalAlertDateKey = 'health_last_water_goal_alert_date';
  static const _lastEveningLowWaterAlertDateKey =
      'health_last_evening_low_water_alert_date';

  final Light _light = Light();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<StepCount>? _stepSub;
  StreamSubscription<int>? _lightSub;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _dailyStatsSub;
  Timer? _sedentaryTimer;
  Timer? _stepSyncTimer;
  Timer? _syncRetryTimer;

  bool _initialized = false;
  bool _hasNotificationPermission = false;
  bool _hasActivityPermission = false;
  bool _hasBatteryExemption = false;
  bool _syncInProgress = false;
  bool _syncQueued = false;
  bool _hasNetworkConnection = true;

  int _steps = 0;
  int _lightLux = 0;
  int _syncedSteps = 0;
  int _lastSyncedSteps = 0;
  int? _firstReading;
  int _lastMovementAt = DateTime.now().millisecondsSinceEpoch;
  int _lastSedentaryNotifyMs = 0;
  int _dailyCalories = 0;
  int _dailyTargetSteps = 8000;
  double _dailyWaterLiters = 0;
  bool _lowLightNotifiedInCurrentStreak = false;
  String _lastCalorieAlertDate = '';
  String _lastWaterGoalAlertDate = '';
  String _lastEveningLowWaterAlertDate = '';
  String _status = 'Đang khởi tạo...';
  String _syncedDateKey = '';
  String _deviceId = '';
  String? _currentUid;

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  bool get hasNotificationPermission => _hasNotificationPermission;
  bool get hasActivityPermission => _hasActivityPermission;
  bool get hasBatteryExemption => _hasBatteryExemption;
  bool get hasNetworkConnection => _hasNetworkConnection;
  int get steps => _steps;
  int get syncedSteps => _syncedSteps;
  int get dailyTargetSteps => _dailyTargetSteps;
  int get pendingSyncSteps => (_steps - _lastSyncedSteps).clamp(0, 1 << 31);
  int get totalDisplayedSteps {
    final combined = _syncedSteps + pendingSyncSteps;
    return combined > _steps ? combined : _steps;
  }

  bool get hasPendingSync => pendingSyncSteps > 0;
  int get lightLux => _lightLux;
  String get status => _status;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _initNotifications();
    await syncPermissionStates();
    await _restoreState();
    await _restoreSyncState();
    await _loadDeviceId();
    await _startConnectivityWatch();
    _authSub = _auth.authStateChanges().listen(_handleAuthStateChanged);
    await _handleAuthStateChanged(_auth.currentUser);
    await _startTracking();
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    _firstReading = prefs.getInt(_stepBaselineKey);
    _lastSedentaryNotifyMs = prefs.getInt(_lastSedentaryNotifyKey) ?? 0;
    _lastCalorieAlertDate = prefs.getString(_lastCalorieAlertDateKey) ?? '';
    _lastWaterGoalAlertDate = prefs.getString(_lastWaterGoalAlertDateKey) ?? '';
    _lastEveningLowWaterAlertDate =
        prefs.getString(_lastEveningLowWaterAlertDateKey) ?? '';
  }

  Future<void> _restoreSyncState() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    _syncedDateKey = prefs.getString(_syncStateDateKey) ?? todayKey;
    if (_syncedDateKey != todayKey) {
      _syncedDateKey = todayKey;
      _syncedSteps = 0;
      _lastSyncedSteps = 0;
      return;
    }

    _lastSyncedSteps = prefs.getInt(_syncStateStepsKey) ?? 0;
    _syncedSteps = _lastSyncedSteps;
  }

  Future<void> _loadDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDeviceId = prefs.getString(_deviceIdKey);
    if (savedDeviceId != null && savedDeviceId.isNotEmpty) {
      _deviceId = savedDeviceId;
      return;
    }

    _deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    await prefs.setString(_deviceIdKey, _deviceId);
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(settings);

    final granted = await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled();

    _hasNotificationPermission = granted ?? false;
  }

  Future<void> syncPermissionStates() async {
    final activityStatus = await Permission.activityRecognition.status;
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    final notificationStatus = await Permission.notification.status;

    _hasActivityPermission = activityStatus.isGranted;
    _hasBatteryExemption = batteryStatus.isGranted;
    _hasNotificationPermission = notificationStatus.isGranted;
    notifyListeners();
  }

  Future<void> _handleAuthStateChanged(User? user) async {
    final uid = user?.uid;
    if (_currentUid == uid) return;

    _currentUid = uid;
    await _dailyStatsSub?.cancel();
    _dailyStatsSub = null;

    if (uid == null || uid.isEmpty) {
      _syncedSteps = _steps;
      _dailyCalories = 0;
      _dailyTargetSteps = 8000;
      _dailyWaterLiters = 0;
      notifyListeners();
      return;
    }

    final docRef = _db
        .collection('users')
        .doc(uid)
        .collection('dailyStats')
        .doc(_todayKey());

    _dailyStatsSub = docRef.snapshots().listen((snapshot) {
      final data = snapshot.data();
      final cloudSteps = _toInt(data?['steps']);
      final cloudTargetSteps = _normalizeTargetSteps(data?['targetSteps']);
      _dailyCalories = _toInt(data?['calories']);
      _dailyWaterLiters = _toDouble(data?['waterLiters']);

      var shouldNotify = false;
      if (cloudSteps != _syncedSteps) {
        _syncedSteps = cloudSteps;
        shouldNotify = true;
      }

      if (cloudTargetSteps != _dailyTargetSteps) {
        _dailyTargetSteps = cloudTargetSteps;
        shouldNotify = true;
      }

      if (shouldNotify) {
        notifyListeners();
      }

      _checkNutritionThresholdNotifications();
      _checkEveningLowWaterReminder();
    });

    await _syncStepsToCloud();
  }

  Future<StepLightPermissionResult> requestRuntimePermissions() async {
    final activityBefore = await Permission.activityRecognition.status;
    final batteryBefore = await Permission.ignoreBatteryOptimizations.status;
    final notifyBefore = await Permission.notification.status;

    final activityStatus = await Permission.activityRecognition.request();
    final batteryStatus = await Permission.ignoreBatteryOptimizations.request();
    final notificationStatus = await Permission.notification.request();

    await syncPermissionStates();

    final hasPermanentDenied =
        activityStatus.isPermanentlyDenied ||
        notificationStatus.isPermanentlyDenied ||
        batteryStatus.isPermanentlyDenied;

    if (!_hasNotificationPermission || !_hasActivityPermission) {
      _status =
          'Cần cấp quyền thông báo và hoạt động thể chất để theo dõi ổn định.';
    } else {
      _status = 'Đã cấp quyền cần thiết. Theo dõi đang hoạt động.';
      await _startTracking();
    }
    notifyListeners();

    final changed =
        activityBefore != activityStatus ||
        batteryBefore != batteryStatus ||
        notifyBefore != notificationStatus;

    return StepLightPermissionResult(
      hasNotificationPermission: _hasNotificationPermission,
      hasActivityPermission: _hasActivityPermission,
      hasBatteryExemption: _hasBatteryExemption,
      hasPermanentDenied: hasPermanentDenied,
      changed: changed,
    );
  }

  Future<void> _showReminderNotification(String title, String body) async {
    if (!_hasNotificationPermission) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'step_light_reminders',
        'Step & Light Reminders',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  bool _isCooldownPassed(int lastNotifyMs, Duration cooldown) {
    if (lastNotifyMs == 0) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastNotifyMs;
    return elapsed >= cooldown.inMilliseconds;
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return 0;
  }

  int _normalizeTargetSteps(dynamic value) {
    final parsed = _toInt(value);
    if (parsed < 1000) return 1000;
    return parsed;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return 0;
  }

  Future<void> _saveAlertDate(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  void _checkNutritionThresholdNotifications() {
    final todayKey = _todayKey();

    if (_dailyCalories > 2500 && _lastCalorieAlertDate != todayKey) {
      _lastCalorieAlertDate = todayKey;
      _saveAlertDate(_lastCalorieAlertDateKey, todayKey);
      _showReminderNotification(
        'Calo hôm nay đã cao',
        'Bạn đã vượt 2.500 kcal trong ngày. Hãy cân bằng bữa ăn và vận động nhẹ.',
      );
    }

    if (_dailyWaterLiters >= 2.0 && _lastWaterGoalAlertDate != todayKey) {
      _lastWaterGoalAlertDate = todayKey;
      _saveAlertDate(_lastWaterGoalAlertDateKey, todayKey);
      _showReminderNotification(
        'Đã đạt mục tiêu nước',
        'Bạn đã uống trên 2.000 ml nước hôm nay. Duy trì rất tốt!',
      );
    }
  }

  void _checkEveningLowWaterReminder() {
    final now = DateTime.now();
    final todayKey = _todayKey();
    if (_lastEveningLowWaterAlertDate == todayKey) return;

    if (now.hour == 18 && now.minute == 0 && _dailyWaterLiters <= 0.5) {
      _lastEveningLowWaterAlertDate = todayKey;
      _saveAlertDate(_lastEveningLowWaterAlertDateKey, todayKey);
      _showReminderNotification(
        'Nhắc uống nước lúc 18:00',
        'Đến 18:00 nhưng bạn mới uống ${_dailyWaterLiters.toStringAsFixed(1)}L. Hãy bổ sung thêm nước nhé.',
      );
    }
  }

  Future<void> _saveSyncState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncStateDateKey, _syncedDateKey);
    await prefs.setInt(_syncStateStepsKey, _lastSyncedSteps);
  }

  bool _hasNetworkFromResults(List<ConnectivityResult> results) {
    for (final result in results) {
      if (result != ConnectivityResult.none) {
        return true;
      }
    }
    return false;
  }

  Future<void> _startConnectivityWatch() async {
    final connectivity = Connectivity();
    final initial = await connectivity.checkConnectivity();
    _hasNetworkConnection = _hasNetworkFromResults(initial);

    _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
      final next = _hasNetworkFromResults(results);
      final changed = next != _hasNetworkConnection;
      _hasNetworkConnection = next;

      if (_hasNetworkConnection && _steps > _lastSyncedSteps) {
        _queueStepSync();
      }

      if (changed) {
        notifyListeners();
      }
    });
  }

  void _queueStepSync() {
    if (_currentUid == null) return;

    _stepSyncTimer?.cancel();
    _stepSyncTimer = Timer(const Duration(seconds: 2), () {
      _syncStepsToCloud();
    });
  }

  Future<void> _syncStepsToCloud() async {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) return;

    final todayKey = _todayKey();
    if (_syncedDateKey != todayKey) {
      _syncedDateKey = todayKey;
      _lastSyncedSteps = 0;
    }

    if (_steps <= _lastSyncedSteps) {
      return;
    }

    if (_syncInProgress) {
      _syncQueued = true;
      return;
    }

    _syncInProgress = true;
    try {
      final delta = _steps - _lastSyncedSteps;
      if (delta <= 0) return;

      final docRef = _db
          .collection('users')
          .doc(uid)
          .collection('dailyStats')
          .doc(todayKey);

      final challengeRef = _db.collection('challenges').doc('daily-10k');

      await docRef.set({
        'steps': FieldValue.increment(delta),
        'updatedAt': FieldValue.serverTimestamp(),
        'date': todayKey,
        'stepDeviceId': _deviceId,
        'stepLocalSteps': _steps,
      }, SetOptions(merge: true));

      // Keep challenge leaderboard in sync with today's steps for multi-device accounts.
      await challengeRef.set({
        'participants': {uid: FieldValue.increment(delta)},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _lastSyncedSteps = _steps;
      _syncedSteps = _steps;
      await _saveSyncState();
      notifyListeners();
    } catch (e) {
      _status = 'Không thể đồng bộ bước chân: $e';
      notifyListeners();
    } finally {
      _syncInProgress = false;
      if (_syncQueued) {
        _syncQueued = false;
        await _syncStepsToCloud();
      }
    }
  }

  Future<void> _startTracking() async {
    if (_stepSub != null &&
        _lightSub != null &&
        _sedentaryTimer != null &&
        _syncRetryTimer != null) {
      return;
    }

    _status = 'Đang bật cảm biến...';
    notifyListeners();

    try {
      _stepSub ??= Pedometer.stepCountStream.listen(
        (event) {
          if (_firstReading == null) {
            _firstReading = event.steps;
            SharedPreferences.getInstance().then((prefs) {
              prefs.setInt(_stepBaselineKey, _firstReading!);
            });
          }

          final relativeSteps = event.steps - (_firstReading ?? 0);
          _steps = relativeSteps < 0 ? event.steps : relativeSteps;
          _lastMovementAt = DateTime.now().millisecondsSinceEpoch;
          _status = 'Đang theo dõi bước chân';
          notifyListeners();
          _queueStepSync();
        },
        onError: (error) {
          _status = 'Không đọc được dữ liệu bước chân: $error';
          notifyListeners();
        },
      );

      _lightSub ??= _light.lightSensorStream.listen(
        (lux) {
          _lightLux = lux.round();
          if (_lightLux < 15) {
            _status = 'Ánh sáng yếu - nên nghỉ mắt đôi chút';
            if (!_lowLightNotifiedInCurrentStreak) {
              _lowLightNotifiedInCurrentStreak = true;
              _showReminderNotification(
                'Cảnh báo ánh sáng thấp',
                'Môi trường quá tối, hãy cho mắt nghỉ và điều chỉnh đèn.',
              );
            }
          } else {
            _lowLightNotifiedInCurrentStreak = false;
            _status = 'Môi trường sáng bình thường';
          }
          notifyListeners();
        },
        onError: (error) {
          _status = 'Không đọc được cảm biến ánh sáng: $error';
          notifyListeners();
        },
      );

      _sedentaryTimer ??= Timer.periodic(const Duration(minutes: 1), (_) async {
        _checkEveningLowWaterReminder();

        final minutesSinceMove =
            (DateTime.now().millisecondsSinceEpoch - _lastMovementAt) / 60000;
        if (minutesSinceMove < 120) return;

        _status = 'Bạn đã ngồi lâu hơn 2 giờ - hãy đi lại/vận động nhẹ!';
        notifyListeners();

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (_isCooldownPassed(
          _lastSedentaryNotifyMs,
          const Duration(minutes: 120),
        )) {
          _lastSedentaryNotifyMs = nowMs;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_lastSedentaryNotifyKey, nowMs);
          await _showReminderNotification(
            'Nhớ vận động',
            'Bạn đã ngồi lâu, hãy đi lại nhẹ trong 3-5 phút.',
          );
        }
      });

      // Retry cloud sync periodically so offline steps are pushed even when
      // network returns but no new step event is generated.
      _syncRetryTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
        if (_currentUid == null || _currentUid!.isEmpty) {
          return;
        }
        if (_steps > _lastSyncedSteps) {
          _syncStepsToCloud();
        }
      });
    } catch (e) {
      _status = 'Không thể khởi tạo cảm biến: $e';
      notifyListeners();
    }
  }

  Future<void> resetStepSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_stepBaselineKey);
    _firstReading = null;
    _steps = 0;
    _lastSyncedSteps = 0;
    _syncedSteps = 0;
    _syncedDateKey = _todayKey();
    await _saveSyncState();
    notifyListeners();
  }

  @override
  void dispose() {
    _stepSub?.cancel();
    _lightSub?.cancel();
    _connectivitySub?.cancel();
    _sedentaryTimer?.cancel();
    _authSub?.cancel();
    _dailyStatsSub?.cancel();
    _stepSyncTimer?.cancel();
    _syncRetryTimer?.cancel();
    super.dispose();
  }
}
