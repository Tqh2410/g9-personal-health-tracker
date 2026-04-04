import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/activity_screen.dart';
import '../screens/nutrition_screen.dart';
import '../screens/vitals_screen.dart';
import '../screens/ai_food_screen.dart';
import '../screens/sleep_habit_screen.dart';
import '../screens/sos_screen.dart';
import '../screens/community_screen.dart';
import '../screens/voice_diary_screen.dart';
import '../screens/hardware_monitor_screen.dart';
import '../screens/step_light_screen.dart';
import '../models/nutrition_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_refresh_provider.dart';
import '../services/nutrition_service.dart';
import '../services/sleep_habit_reminder_service.dart';

class DashboardStats {
  final double waterLiters;
  final int steps;
  final int targetSteps;
  final int calories;
  final int? heartRate;
  final List<String> recentActivities;

  const DashboardStats({
    required this.waterLiters,
    required this.steps,
    required this.targetSteps,
    required this.calories,
    required this.heartRate,
    required this.recentActivities,
  });

  static const empty = DashboardStats(
    waterLiters: 0,
    steps: 0,
    targetSteps: 8000,
    calories: 0,
    heartRate: null,
    recentActivities: <String>[],
  );
}

String _todayKey() {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year}-$month-$day';
}

double _numToDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return 0;
}

int _numToInt(dynamic value) {
  if (value is num) return value.toInt();
  return 0;
}

int _normalizeTargetSteps(dynamic value) {
  final parsed = _numToInt(value);
  if (parsed < 1000) return 1000;
  return parsed;
}

String _formatStepNumber(int value) {
  return value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => '.',
  );
}

final dashboardStatsProvider = StreamProvider<DashboardStats>((ref) async* {
  ref.watch(dashboardRefreshTriggerProvider);

  final authUser = ref.watch(authStateProvider).valueOrNull;
  final uid = authUser?.id;
  if (uid == null || uid.isEmpty) {
    yield DashboardStats.empty;
    return;
  }

  final db = FirebaseFirestore.instance;
  final dateKey = _todayKey();

  DashboardStats fallbackStats = DashboardStats.empty;

  try {
    final userDoc = await db.collection('users').doc(uid).get();
    final userData = userDoc.data() ?? <String, dynamic>{};
    final rootDaily = userData['dailyStats'];
    if (rootDaily is Map<String, dynamic>) {
      final waterLiters = _numToDouble(rootDaily['waterLiters']);
      final steps = _numToInt(rootDaily['steps']);
      final targetSteps = rootDaily.containsKey('targetSteps')
          ? _normalizeTargetSteps(rootDaily['targetSteps'])
          : 8000;
      final calories = _numToInt(rootDaily['calories']);
      final hr = rootDaily['heartRate'];
      final heartRate = hr is num ? hr.toInt() : null;
      final recent = rootDaily['recentActivities'];
      if (recent is List) {
        fallbackStats = DashboardStats(
          waterLiters: waterLiters,
          steps: steps,
          targetSteps: targetSteps,
          calories: calories,
          heartRate: heartRate,
          recentActivities: recent.whereType<String>().toList(growable: false),
        );
      } else {
        fallbackStats = DashboardStats(
          waterLiters: waterLiters,
          steps: steps,
          targetSteps: targetSteps,
          calories: calories,
          heartRate: heartRate,
          recentActivities: <String>[],
        );
      }
    }
  } catch (_) {
    // Keep defaults when user document cannot be read.
  }

  try {
    final dayDoc = await db
        .collection('users')
        .doc(uid)
        .collection('dailyStats')
        .doc(dateKey)
        .get();
    if (dayDoc.exists) {
      final dayData = dayDoc.data() ?? <String, dynamic>{};
      final recent = dayData['recentActivities'];
      yield DashboardStats(
        waterLiters: dayData.containsKey('waterLiters')
            ? _numToDouble(dayData['waterLiters'])
            : fallbackStats.waterLiters,
        steps: dayData.containsKey('steps')
            ? _numToInt(dayData['steps'])
            : fallbackStats.steps,
        targetSteps: dayData.containsKey('targetSteps')
            ? _normalizeTargetSteps(dayData['targetSteps'])
            : fallbackStats.targetSteps,
        calories: dayData.containsKey('calories')
            ? _numToInt(dayData['calories'])
            : fallbackStats.calories,
        heartRate: dayData['heartRate'] is num
            ? (dayData['heartRate'] as num).toInt()
            : fallbackStats.heartRate,
        recentActivities: recent is List
            ? recent.whereType<String>().toList(growable: false)
            : fallbackStats.recentActivities,
      );
      return;
    }
  } catch (_) {
    // Subcollection may be blocked by current Firestore rules.
  }

  try {
    final vitalQuery = await db
        .collection('vitals')
        .doc(uid)
        .collection(dateKey)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (vitalQuery.docs.isNotEmpty) {
      final latest = vitalQuery.docs.first.data();
      final hr = latest['heartRate'];
      if (hr is num) {
        fallbackStats = DashboardStats(
          waterLiters: fallbackStats.waterLiters,
          steps: fallbackStats.steps,
          targetSteps: fallbackStats.targetSteps,
          calories: fallbackStats.calories,
          heartRate: hr.toInt(),
          recentActivities: fallbackStats.recentActivities,
        );
      }
    }
  } catch (_) {
    // Vitals collection may not exist yet or is denied by rules.
  }

  yield fallbackStats;

  await for (final daySnap
      in db
          .collection('users')
          .doc(uid)
          .collection('dailyStats')
          .doc(dateKey)
          .snapshots()) {
    if (!daySnap.exists) {
      yield fallbackStats;
      continue;
    }

    final dayData = daySnap.data() ?? <String, dynamic>{};
    final recent = dayData['recentActivities'];
    yield DashboardStats(
      waterLiters: dayData.containsKey('waterLiters')
          ? _numToDouble(dayData['waterLiters'])
          : fallbackStats.waterLiters,
      steps: dayData.containsKey('steps')
          ? _numToInt(dayData['steps'])
          : fallbackStats.steps,
      targetSteps: dayData.containsKey('targetSteps')
          ? _normalizeTargetSteps(dayData['targetSteps'])
          : fallbackStats.targetSteps,
      calories: dayData.containsKey('calories')
          ? _numToInt(dayData['calories'])
          : fallbackStats.calories,
      heartRate: dayData['heartRate'] is num
          ? (dayData['heartRate'] as num).toInt()
          : fallbackStats.heartRate,
      recentActivities: recent is List
          ? recent.whereType<String>().toList(growable: false)
          : fallbackStats.recentActivities,
    );
  }
});

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      final isLoggingIn =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/sign-up' ||
          state.matchedLocation == '/forgot-password';

      return authState.when(
        data: (user) {
          if (user != null && isLoggingIn) {
            return '/home';
          }
          if (user == null && !isLoggingIn) {
            return '/login';
          }
          return null;
        },
        loading: () => null,
        error: (_, _) => '/login',
      );
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        name: 'sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/activity',
                name: 'activity',
                builder: (context, state) => const ActivityScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/nutrition',
                name: 'nutrition',
                builder: (context, state) => const NutritionScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/community',
                name: 'community',
                builder: (context, state) => const CommunityScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/step-light',
                name: 'step-light',
                builder: (context, state) => const StepLightScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/vitals',
        name: 'vitals',
        builder: (context, state) => const VitalsScreen(),
      ),
      GoRoute(
        path: '/ai-food',
        name: 'ai-food',
        builder: (context, state) =>
            AiFoodScreen(initialSource: state.uri.queryParameters['source']),
      ),
      GoRoute(
        path: '/sleep-habit',
        name: 'sleep-habit',
        builder: (context, state) => const SleepHabitScreen(),
      ),
      GoRoute(
        path: '/sos',
        name: 'sos',
        builder: (context, state) => const SosScreen(),
      ),
      GoRoute(
        path: '/voice-diary',
        name: 'voice-diary',
        builder: (context, state) => const VoiceDiaryScreen(),
      ),
      GoRoute(
        path: '/hardware',
        name: 'hardware',
        builder: (context, state) => const HeartRateMeasurementScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Không tìm thấy trang: ${state.uri}')),
    ),
  );
});

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NavigationBar(
            height: 74,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onTap,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            indicatorColor: scheme.secondaryContainer,
            backgroundColor: scheme.surface,
            shadowColor: Colors.transparent,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Trang chủ',
              ),
              NavigationDestination(
                icon: Icon(Icons.fitness_center_outlined),
                selectedIcon: Icon(Icons.fitness_center),
                label: 'Hoạt động',
              ),
              NavigationDestination(
                icon: Icon(Icons.restaurant_menu_outlined),
                selectedIcon: Icon(Icons.restaurant_menu),
                label: 'Dinh dưỡng',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Cộng đồng',
              ),
              NavigationDestination(
                icon: Icon(Icons.directions_run_outlined),
                selectedIcon: Icon(Icons.directions_run),
                label: 'Theo dõi',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _addQuickWaterNutritionLog(WidgetRef ref) async {
    final uid = ref.read(authStateProvider).valueOrNull?.id;
    if (uid == null || uid.isEmpty) return;

    final entry = NutritionEntry(
      id: '',
      mealType: 'thao tác nhanh',
      food: 'Uống nước 250ml',
      calories: 0,
      waterLiters: 0.25,
      createdAt: DateTime.now(),
    );

    await NutritionService().addNutritionAndUpdateDailyStats(uid, entry);
    triggerDashboardRefresh(ref);
  }

  Future<void> _setDailyStepTarget(WidgetRef ref, int targetSteps) async {
    final authUser = ref.read(authStateProvider).valueOrNull;
    final uid = authUser?.id;
    if (uid == null || uid.isEmpty) return;

    final normalizedTarget = _normalizeTargetSteps(targetSteps);
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dailyStats')
        .doc(_todayKey());

    await docRef.set({
      'targetSteps': normalizedTarget,
      'updatedAt': FieldValue.serverTimestamp(),
      'date': _todayKey(),
    }, SetOptions(merge: true));

    ref.invalidate(dashboardStatsProvider);
  }

  Future<void> _showStepTargetSheet(
    BuildContext context,
    WidgetRef ref,
    int currentTarget,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: currentTarget.toString());

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(sheetContext).viewInsets.bottom + 22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Mục tiêu bước trong ngày',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nhập mục tiêu (bước)',
                  hintText: 'Ví dụ: 5000, 8000, 10000',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mục tiêu tối thiểu là 1.000 bước mỗi ngày.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () async {
                  final parsed = int.tryParse(controller.text.trim());
                  if (parsed == null || parsed <= 0) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(
                        content: Text('Vui lòng nhập số bước hợp lệ.'),
                      ),
                    );
                    return;
                  }

                  await _setDailyStepTarget(ref, parsed);
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Đã cập nhật mục tiêu: ${_formatStepNumber(_normalizeTargetSteps(parsed))} bước',
                      ),
                    ),
                  );
                },
                child: const Text('Lưu mục tiêu'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateDailyStats(
    WidgetRef ref, {
    double addWater = 0,
    int addCalories = 0,
    int? heartRate,
    String? activity,
  }) async {
    final authUser = ref.read(authStateProvider).valueOrNull;
    final uid = authUser?.id;
    if (uid == null || uid.isEmpty) return;

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dailyStats')
        .doc(_todayKey());

    final data = <String, dynamic>{
      'waterLiters': FieldValue.increment(addWater),
      'calories': FieldValue.increment(addCalories),
      'updatedAt': FieldValue.serverTimestamp(),
      'date': _todayKey(),
    };

    if (heartRate != null) {
      data['heartRate'] = heartRate;
    }
    if (activity != null && activity.isNotEmpty) {
      data['recentActivities'] = FieldValue.arrayUnion([activity]);
    }

    await docRef.set(data, SetOptions(merge: true));
    ref.invalidate(dashboardStatsProvider);
  }

  Future<void> _showQuickUpdateSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final waterController = TextEditingController();
    final caloriesController = TextEditingController();
    final heartRateController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).viewInsets.bottom + 22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Cập nhật chỉ số hôm nay',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: waterController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Nước (L)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: caloriesController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Calories',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: heartRateController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Nhịp tim (bpm)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final addWater =
                        double.tryParse(waterController.text.trim()) ?? 0;
                    final addCalories =
                        int.tryParse(caloriesController.text.trim()) ?? 0;
                    final hr = int.tryParse(heartRateController.text.trim());

                    await _updateDailyStats(
                      ref,
                      addWater: addWater,
                      addCalories: addCalories,
                      heartRate: hr,
                      activity:
                          'Cập nhật: +${addWater.toStringAsFixed(2)}L, +$addCalories kcal',
                    );

                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã cập nhật thành công')),
                      );
                    }
                  },
                  child: const Text('Lưu cập nhật'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _initialsFromEmail(String email) {
    if (email.isEmpty) return 'U';
    final parts = email.split('@').first.split('.');
    if (parts.length >= 2) {
      return '${parts[0].isNotEmpty ? parts[0][0] : ''}${parts[1].isNotEmpty ? parts[1][0] : ''}'
          .toUpperCase();
    }
    return email[0].toUpperCase();
  }

  Future<void> _showAccountSheet(
    BuildContext context,
    WidgetRef ref,
    String displayName,
    String email,
    String? photoUrl,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final rootMessenger = ScaffoldMessenger.of(context);
    final uid = ref.read(authStateProvider).valueOrNull?.id;
    if (uid == null || uid.isEmpty) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final userSnap = await userRef.get();
    if (!context.mounted) return;
    final userData = userSnap.data() ?? <String, dynamic>{};

    String firstName = (userData['firstName'] as String? ?? '').trim();
    String lastName = (userData['lastName'] as String? ?? '').trim();
    if (firstName.isEmpty && lastName.isEmpty && displayName.isNotEmpty) {
      final parts = displayName.trim().split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        firstName = parts.first;
        if (parts.length > 1) {
          lastName = parts.sublist(1).join(' ');
        }
      }
    }

    final firstNameController = TextEditingController(text: firstName);
    final lastNameController = TextEditingController(text: lastName);
    final emailController = TextEditingController(
      text: (userData['email'] as String? ?? email).trim(),
    );
    final phoneController = TextEditingController(
      text: (userData['phoneNumber'] as String? ?? '').trim(),
    );

    final didSave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Future<void> saveProfile() async {
          final first = firstNameController.text.trim();
          final last = lastNameController.text.trim();
          final userEmail = emailController.text.trim();
          final phone = phoneController.text.trim();

          if (first.isEmpty && last.isEmpty) {
            rootMessenger.showSnackBar(
              const SnackBar(content: Text('Vui lòng nhập tên người dùng.')),
            );
            return;
          }
          if (userEmail.isEmpty || !userEmail.contains('@')) {
            rootMessenger.showSnackBar(
              const SnackBar(content: Text('Email không hợp lệ.')),
            );
            return;
          }

          try {
            await userRef.set({
              'firstName': first,
              'lastName': last,
              'email': userEmail,
              'phoneNumber': phone,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop(true);
            }
          } catch (_) {
            rootMessenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Không thể lưu hồ sơ. Vui lòng kiểm tra quyền Firestore.',
                ),
              ),
            );
          }
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                CircleAvatar(
                  radius: 30,
                  backgroundColor: scheme.primaryContainer,
                  backgroundImage: photoUrl != null
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl == null
                      ? Text(
                          _initialsFromEmail(emailController.text.trim()),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: firstNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Tên',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lastNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Họ',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: saveProfile,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Lưu thông tin'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop(false);
                      await ref.read(authServiceProvider).signOut();
                    },
                    icon: Icon(Icons.logout, color: scheme.error),
                    label: Text(
                      'Đăng xuất',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (didSave == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu thông tin tài khoản lên Firebase.'),
        ),
      );
      ref.invalidate(dashboardStatsProvider);
    }
  }

  Widget _buildHomeDrawer(
    BuildContext context,
    WidgetRef ref,
    String displayName,
    String email,
    String? photoUrl,
  ) {
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: scheme.primaryContainer,
                  backgroundImage: photoUrl != null
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl == null
                      ? Text(
                          _initialsFromEmail(email),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email.isEmpty ? 'Chưa đăng nhập' : email,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _showAccountSheet(
                            context,
                            ref,
                            displayName,
                            email,
                            photoUrl,
                          );
                        },
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Hồ sơ tài khoản'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                  child: Text(
                    'Tiện ích bổ sung',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  tileColor: scheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  leading: const Icon(Icons.mic_none),
                  title: const Text('Nhật ký giọng nói'),
                  subtitle: const Text('Ghi chú bằng văn bản hoặc giọng nói'),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/voice-diary');
                  },
                ),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  tileColor: scheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  leading: const Icon(Icons.favorite_outline),
                  title: const Text('Đo nhịp tim trực tiếp'),
                  subtitle: const Text('Đặt ngón tay lên camera để đo'),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/hardware');
                  },
                ),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  tileColor: scheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Cài đặt'),
                  subtitle: const Text('Tùy chỉnh ứng dụng'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showSettingsSheet(context, ref);
                  },
                ),
                const SizedBox(height: 10),
                Divider(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      foregroundColor: scheme.error,
                      backgroundColor: scheme.errorContainer,
                    ),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await ref.read(authServiceProvider).signOut();
                    },
                    icon: Icon(Icons.logout, color: scheme.error),
                    label: Text(
                      'Đăng xuất',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
    required Color backgroundColor,
    required Color borderColor,
    bool compact = false,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(icon, size: compact ? 16 : 18, color: accent),
          SizedBox(width: compact ? 6 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: compact ? 11 : 12,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 12 : 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepGaugeCard({
    required BuildContext context,
    required WidgetRef ref,
    required DashboardStats stats,
    required double progress,
  }) {
    final targetSteps = stats.targetSteps;
    final percent = (progress * 100).toStringAsFixed(0);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: scheme.primaryContainer,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bước hôm nay',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    InkWell(
                      onTap: () =>
                          _showStepTargetSheet(context, ref, targetSteps),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Mục tiêu ${_formatStepNumber(targetSteps)} bước',
                              style: TextStyle(
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: scheme.onPrimaryContainer,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt,
                      size: 16,
                      color: scheme.onSecondaryContainer,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Đang theo dõi',
                      style: TextStyle(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 240,
                  height: 240,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 18,
                    strokeCap: StrokeCap.round,
                    backgroundColor: scheme.primary.withValues(alpha: 0.18),
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${stats.steps}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'bước',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$percent% mục tiêu',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.78,
                        ),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildMetricChip(
                  context: context,
                  icon: Icons.local_drink_outlined,
                  label: 'Nước',
                  value: '${stats.waterLiters.toStringAsFixed(2)} L',
                  accent: const Color(0xFFBFE3FF),
                  backgroundColor: scheme.surfaceContainerHighest,
                  borderColor: scheme.outlineVariant.withValues(alpha: 0.7),
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricChip(
                  context: context,
                  icon: Icons.local_fire_department_outlined,
                  label: 'Calories',
                  value: '${stats.calories} kcal',
                  accent: const Color(0xFFFFD18A),
                  backgroundColor: scheme.surfaceContainerHighest,
                  borderColor: scheme.outlineVariant.withValues(alpha: 0.7),
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricChip(
                  context: context,
                  icon: Icons.favorite_outline,
                  label: 'Nhịp tim',
                  value: stats.heartRate != null
                      ? '${stats.heartRate} bpm'
                      : '-- bpm',
                  accent: const Color(0xFFFFB4C9),
                  backgroundColor: scheme.surfaceContainerHighest,
                  borderColor: scheme.outlineVariant.withValues(alpha: 0.7),
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bạn đã hoàn thành $percent% mục tiêu ngày · mục tiêu: ${_formatStepNumber(targetSteps)} bước',
            style: TextStyle(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardActionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
    required ColorScheme scheme,
  }) {
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsSheet(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Cài đặt',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Chế độ hiển thị'),
                    subtitle: Text(_themeModeLabel(themeMode)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showThemeModeSheet(context, ref);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    leading: const Icon(Icons.alarm_outlined),
                    title: const Text('Nhắc giấc ngủ & thói quen'),
                    subtitle: const Text(
                      'Số lần nhắc uống nước/vận động và giờ ngủ sớm',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showReminderSettingsSheet(context, ref);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Sáng';
      case ThemeMode.dark:
        return 'Tối';
      case ThemeMode.system:
        return 'Theo thiết bị';
    }
  }

  void _showThemeModeSheet(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Chế độ hiển thị',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                _buildThemeModeOption(
                  context: context,
                  label: 'Sáng',
                  icon: Icons.light_mode_outlined,
                  mode: ThemeMode.light,
                  currentMode: themeMode,
                  onSelect: () {
                    ref
                        .read(themeModeProvider.notifier)
                        .setThemeMode(ThemeMode.light);
                    Navigator.pop(sheetContext);
                  },
                ),
                const SizedBox(height: 10),
                _buildThemeModeOption(
                  context: context,
                  label: 'Tối',
                  icon: Icons.dark_mode_outlined,
                  mode: ThemeMode.dark,
                  currentMode: themeMode,
                  onSelect: () {
                    ref
                        .read(themeModeProvider.notifier)
                        .setThemeMode(ThemeMode.dark);
                    Navigator.pop(sheetContext);
                  },
                ),
                const SizedBox(height: 10),
                _buildThemeModeOption(
                  context: context,
                  label: 'Theo thiết bị',
                  icon: Icons.settings_brightness_outlined,
                  mode: ThemeMode.system,
                  currentMode: themeMode,
                  onSelect: () {
                    ref
                        .read(themeModeProvider.notifier)
                        .setThemeMode(ThemeMode.system);
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThemeModeOption({
    required BuildContext context,
    required String label,
    required IconData icon,
    required ThemeMode mode,
    required ThemeMode currentMode,
    required VoidCallback onSelect,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = currentMode == mode;

    return Material(
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.secondaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? scheme.secondary
                  : scheme.outlineVariant.withValues(alpha: 0.5),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
              if (isSelected) Icon(Icons.check_circle, color: scheme.secondary),
            ],
          ),
        ),
      ),
    );
  }

  String _formatReminderTime(TimeOfDay timeOfDay) {
    final hour = timeOfDay.hour.toString().padLeft(2, '0');
    final minute = timeOfDay.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _showReminderSettingsSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final service = SleepHabitReminderService();
    await service.initialize();
    final uid = ref.read(authStateProvider).valueOrNull?.id;
    final current = await service.loadConfigForUid(uid);
    await service.applyConfig(
      uid: uid,
      configOverride: current,
      requestPermission: false,
    );

    if (!context.mounted) return;

    var enabled = current.enabled;
    var reminderCount = current.dailyReminderCount;
    var sleepTime = current.sleepReminderTime;
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickSleepTime() async {
              final picked = await showTimePicker(
                context: sheetContext,
                initialTime: sleepTime,
              );
              if (picked == null) return;
              setModalState(() {
                sleepTime = picked;
              });
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.of(sheetContext).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Nhắc giấc ngủ & thói quen',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: enabled,
                      onChanged: (value) {
                        setModalState(() {
                          enabled = value;
                        });
                      },
                      title: const Text('Bật nhắc nhở'),
                      subtitle: const Text(
                        'Bật để nhận nhắc uống nước, vận động và ngủ sớm.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: reminderCount,
                      decoration: const InputDecoration(
                        labelText: 'Số lần nhắc uống nước/vận động mỗi ngày',
                        prefixIcon: Icon(Icons.notifications_active_outlined),
                      ),
                      items: List.generate(6, (index) => index + 1)
                          .map(
                            (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value lần/ngày'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          reminderCount = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Giờ nhắc ngủ sớm'),
                      subtitle: Text(_formatReminderTime(sleepTime)),
                      trailing: FilledButton.tonalIcon(
                        onPressed: pickSleepTime,
                        icon: const Icon(Icons.schedule),
                        label: const Text('Chọn giờ'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        if (isSaving) return;
                        setModalState(() {
                          isSaving = true;
                        });

                        try {
                          final currentUid = ref
                              .read(authStateProvider)
                              .valueOrNull
                              ?.id;
                          if (currentUid == null || currentUid.isEmpty) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Bạn cần đăng nhập để lưu cấu hình.',
                                ),
                              ),
                            );
                            return;
                          }

                          await service.saveConfigForUid(
                            currentUid,
                            SleepHabitReminderConfig(
                              enabled: enabled,
                              dailyReminderCount: reminderCount,
                              sleepReminderTime: sleepTime,
                            ),
                          );

                          final savedConfig = SleepHabitReminderConfig(
                            enabled: enabled,
                            dailyReminderCount: reminderCount,
                            sleepReminderTime: sleepTime,
                          );

                          if (enabled) {
                            final applied = await service.applyConfig(
                              uid: currentUid,
                              configOverride: savedConfig,
                            );
                            if (!applied) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Bạn cần cho phép thông báo và lịch chính xác để nhắc ngủ hoạt động.',
                                  ),
                                ),
                              );
                              return;
                            }
                          } else {
                            await service.cancelAll();
                          }

                          if (!sheetContext.mounted) return;
                          Navigator.of(sheetContext).pop();
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Đã cập nhật nhắc giấc ngủ & thói quen.',
                              ),
                            ),
                          );
                        } catch (error) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Không lưu được cấu hình: $error'),
                            ),
                          );
                        } finally {
                          if (sheetContext.mounted) {
                            setModalState(() {
                              isSaving = false;
                            });
                          }
                        }
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: isSaving
                            ? const SizedBox(
                                key: ValueKey('saving'),
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                key: ValueKey('saveText'),
                                'Lưu cấu hình',
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nhắc nước/vận động sẽ được chia đều trong khung 09:00 - 18:30.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final authUser = ref.watch(authStateProvider).valueOrNull;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final stats = statsAsync.valueOrNull ?? DashboardStats.empty;
    final targetSteps = stats.targetSteps;
    final progress = math.min(1.0, stats.steps / targetSteps);
    final email = authUser?.email ?? '';
    final displayName = authUser?.fullName.isNotEmpty == true
        ? authUser!.fullName
        : 'Người dùng';
    final photoUrl = authUser?.photoUrl;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        scrolledUnderElevation: 0,
        toolbarHeight: 72,
        centerTitle: false,
        leadingWidth: 68,
        leading: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(left: 12),
            child: IconButton.filledTonal(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
          ),
        ),
        title: const Text('Nhật ký sức khỏe'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton.filledTonal(
              onPressed: () =>
                  _showAccountSheet(context, ref, displayName, email, photoUrl),
              icon: CircleAvatar(
                radius: 14,
                backgroundColor: scheme.primaryContainer,
                backgroundImage: photoUrl != null
                    ? NetworkImage(photoUrl)
                    : null,
                child: photoUrl == null
                    ? Text(
                        _initialsFromEmail(email),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      drawer: _buildHomeDrawer(context, ref, displayName, email, photoUrl),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardStatsProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.favorite_outline,
                          color: scheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Xin chào!',
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Sẵn sàng ghi lại hành trình sức khỏe hôm nay?',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildStepGaugeCard(
                context: context,
                ref: ref,
                stats: stats,
                progress: progress,
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.02,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildDashboardActionCard(
                    context: context,
                    title: 'Chỉ số & biểu đồ',
                    subtitle: 'Theo dõi cân nặng và nhịp tim',
                    icon: Icons.show_chart,
                    accent: const Color(0xFF1E66F5),
                    onTap: () => context.push('/vitals'),
                    scheme: scheme,
                  ),
                  _buildDashboardActionCard(
                    context: context,
                    title: 'Quét món ăn AI',
                    subtitle: 'Chụp ảnh hoặc chọn ảnh có sẵn',
                    icon: Icons.camera_alt,
                    accent: const Color(0xFF7C5CFF),
                    onTap: () => context.push('/ai-food'),
                    scheme: scheme,
                  ),
                  _buildDashboardActionCard(
                    context: context,
                    title: 'Ngủ & thói quen',
                    subtitle: 'Nhắc nhở và streak mỗi ngày',
                    icon: Icons.bedtime,
                    accent: const Color(0xFF15A34A),
                    onTap: () => context.push('/sleep-habit'),
                    scheme: scheme,
                  ),
                  _buildDashboardActionCard(
                    context: context,
                    title: 'SOS',
                    subtitle: 'Gửi vị trí khi cần hỗ trợ',
                    icon: Icons.sos,
                    accent: const Color(0xFFEF4444),
                    onTap: () => context.push('/sos'),
                    scheme: scheme,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.flash_on_outlined,
                            color: scheme.onSecondaryContainer,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Thao tác nhanh',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await _addQuickWaterNutritionLog(ref);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Đã thêm 250ml nước vào nhật ký dinh dưỡng',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.local_drink),
                      label: const Text('+250ml nước'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _showQuickUpdateSheet(context, ref),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Cập nhật chỉ số'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (statsAsync.isLoading) ...[
                const SizedBox(height: 12),
                const Center(child: CircularProgressIndicator()),
              ],
              if (statsAsync.hasError) ...[
                const SizedBox(height: 12),
                Text(
                  'Không tải được dữ liệu dashboard. Kéo xuống để thử lại.',
                  style: TextStyle(color: scheme.error),
                ),
              ],
              if (stats.recentActivities.isNotEmpty) ...[
                Row(
                  children: [
                    Text(
                      'Hoạt động gần đây',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.history,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...stats.recentActivities.reversed
                    .take(5)
                    .map(
                      (item) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: scheme.tertiary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
