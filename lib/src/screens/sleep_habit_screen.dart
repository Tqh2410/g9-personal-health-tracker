import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/sleep_habit_reminder_service.dart';
import '../utils/user_friendly_error.dart';

class SleepHabitScreen extends ConsumerStatefulWidget {
  const SleepHabitScreen({super.key});

  @override
  ConsumerState<SleepHabitScreen> createState() => _SleepHabitScreenState();
}

class _SleepHabitScreenState extends ConsumerState<SleepHabitScreen> {
  final SleepHabitReminderService _reminderService =
      SleepHabitReminderService();

  bool _reminderEnabled = false;
  bool _reminderBusy = false;
  int _dailyReminderCount =
      SleepHabitReminderConfig.defaultConfig.dailyReminderCount;
  TimeOfDay _sleepReminderTime =
      SleepHabitReminderConfig.defaultConfig.sleepReminderTime;

  @override
  void initState() {
    super.initState();
    _loadReminderState();
  }

  Future<void> _loadReminderState() async {
    await _reminderService.initialize();
    final config = await _reminderService.loadConfigForUid(_uid);
    await _reminderService.applyConfig(
      uid: _uid,
      configOverride: config,
      requestPermission: false,
    );
    if (!mounted) return;
    setState(() {
      _reminderEnabled = config.enabled;
      _dailyReminderCount = config.dailyReminderCount;
      _sleepReminderTime = config.sleepReminderTime;
    });
  }

  Future<bool> _ensureNotificationPermission() async {
    return _reminderService.requestPermission();
  }

  InputDecoration _dialogFieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  String get _uid => ref.read(authStateProvider).valueOrNull?.id ?? '';

  Future<void> _addSleepLog() async {
    final uid = _uid;
    if (uid.isEmpty) return;

    final sleepController = TextEditingController();
    final wakeController = TextEditingController();
    final qualityController = TextEditingController(text: '3');
    final scheme = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.nights_stay_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Thêm nhật ký giấc ngủ',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: sleepController,
                decoration: _dialogFieldDecoration(
                  'Giờ ngủ (vd: 23:00)',
                  Icons.bedtime_outlined,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: wakeController,
                decoration: _dialogFieldDecoration(
                  'Giờ dậy (vd: 06:30)',
                  Icons.wb_sunny_outlined,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qualityController,
                keyboardType: TextInputType.number,
                decoration: _dialogFieldDecoration(
                  'Chất lượng giấc ngủ (1-5)',
                  Icons.stars_outlined,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .collection('sleepLogs')
                          .add({
                            'sleepTime': sleepController.text.trim(),
                            'wakeTime': wakeController.text.trim(),
                            'quality':
                                int.tryParse(qualityController.text.trim()) ??
                                3,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    },
                    child: const Text('Lưu'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleHabit(String id, Map<String, dynamic> habit) async {
    final uid = _uid;
    if (uid.isEmpty) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = (habit['lastCompletedDate'] as Timestamp?)?.toDate();
    final streak = (habit['streakDays'] ?? 0) as int;

    int nextStreak = streak;
    if (last == null) {
      nextStreak = 1;
    } else {
      final lastDay = DateTime(last.year, last.month, last.day);
      final diff = today.difference(lastDay).inDays;
      if (diff == 0) {
        return;
      } else if (diff == 1) {
        nextStreak = streak + 1;
      } else {
        nextStreak = 1;
      }
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('habits')
        .doc(id)
        .set({
          'streakDays': nextStreak,
          'lastCompletedDate': Timestamp.fromDate(today),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _addHabit() async {
    final uid = _uid;
    if (uid.isEmpty) return;

    final controller = TextEditingController();
    final scheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                      Icons.checklist_outlined,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Thêm thói quen',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                decoration: _dialogFieldDecoration(
                  'Tên thói quen',
                  Icons.flag_outlined,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final name = controller.text.trim();
                      if (name.isEmpty) return;
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .collection('habits')
                          .add({
                            'name': name,
                            'streakDays': 0,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    },
                    child: const Text('Lưu'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshReminderSchedule() async {
    if (_reminderBusy) return;

    setState(() {
      _reminderBusy = true;
    });

    if (_reminderEnabled) {
      try {
        await _reminderService.toggleEnabled(false, uid: _uid);
        await _loadReminderState();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã tắt lịch nhắc nhở.')));
      } finally {
        if (mounted) {
          setState(() {
            _reminderBusy = false;
          });
        }
      }
      return;
    }

    try {
      final granted = await _ensureNotificationPermission();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bạn cần cấp quyền thông báo để bật lịch nhắc.'),
          ),
        );
        return;
      }

      final applied = await _reminderService.toggleEnabled(true, uid: _uid);
      await _loadReminderState();

      if (!applied && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bạn cần cho phép thông báo và lịch chính xác để bật nhắc nhở.',
            ),
          ),
        );
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã bật nhắc nhở theo cấu hình hiện tại.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFriendlyError.message(
              error,
              fallback: 'Không thể bật lịch nhắc lúc này. Vui lòng thử lại.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _reminderBusy = false;
        });
      }
    }
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uid = _uid;
    if (uid.isEmpty) {
      return const Scaffold(body: Center(child: Text('Chưa đăng nhập')));
    }

    final sleepStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('sleepLogs')
        .orderBy('createdAt', descending: true)
        .limit(14)
        .snapshots();

    final habitStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('habits')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        scrolledUnderElevation: 0,
        title: const Text('Giấc ngủ & thói quen'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: (MediaQuery.of(context).size.width - 42) / 2,
              child: FilledButton.icon(
                onPressed: _addHabit,
                label: const Text('Thêm thói quen'),
                icon: const Icon(Icons.add_task),
              ),
            ),
            SizedBox(
              width: (MediaQuery.of(context).size.width - 42) / 2,
              child: FilledButton.icon(
                onPressed: _addSleepLog,
                label: const Text('Thêm giấc ngủ'),
                icon: const Icon(Icons.bedtime_outlined),
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: ListTile(
              title: const Text('Nhắc nhở'),
              subtitle: Text(
                'Uống nước + vận động $_dailyReminderCount lần/ngày, nhắc ngủ sớm lúc ${_sleepReminderTime.hour.toString().padLeft(2, '0')}:${_sleepReminderTime.minute.toString().padLeft(2, '0')}',
              ),
              trailing: FilledButton.tonalIcon(
                onPressed: _reminderBusy ? null : _refreshReminderSchedule,
                icon: const Icon(Icons.schedule),
                label: Text(
                  _reminderBusy
                      ? 'Đang xử lý...'
                      : (_reminderEnabled ? 'Tắt lịch' : 'Bật lịch'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Chuỗi thói quen',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: habitStream,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const LinearProgressIndicator();
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Text('Chưa có thói quen. Hãy thêm thói quen mới.');
              }
              return Column(
                children: docs
                    .map((d) {
                      final h = d.data();
                      final habitName = (h['name'] ?? 'Thói quen') as String;
                      return Dismissible(
                        key: ValueKey('habit-${d.id}'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmDelete(
                          title: 'Xóa thói quen',
                          message:
                              'Bạn có chắc muốn xóa thói quen "$habitName" không?',
                        ),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.delete_outline,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                        onDismissed: (_) async {
                          final messenger = ScaffoldMessenger.of(context);
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('habits')
                              .doc(d.id)
                              .delete();

                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Đã xóa thói quen')),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          child: ListTile(
                            title: Text(habitName),
                            subtitle: Text(
                              'Chuỗi: ${(h['streakDays'] ?? 0)} ngày',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.check_circle_outline),
                              onPressed: () => _toggleHabit(d.id, h),
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Nhật ký giấc ngủ',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: sleepStream,
            builder: (context, snap) {
              if (!snap.hasData) return const LinearProgressIndicator();
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Text('Chưa có nhật ký giấc ngủ.');
              return Column(
                children: docs
                    .map((d) {
                      final s = d.data();
                      final sleepLabel =
                          'Ngủ: ${s['sleepTime'] ?? '--'} - Dậy: ${s['wakeTime'] ?? '--'}';
                      return Dismissible(
                        key: ValueKey('sleep-${d.id}'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmDelete(
                          title: 'Xóa nhật ký giấc ngủ',
                          message:
                              'Bạn có chắc muốn xóa nhật ký giấc ngủ này không?',
                        ),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.delete_outline,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                        onDismissed: (_) async {
                          final messenger = ScaffoldMessenger.of(context);
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('sleepLogs')
                              .doc(d.id)
                              .delete();

                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Đã xóa nhật ký giấc ngủ'),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.nightlight_round),
                            title: Text(sleepLabel),
                            subtitle: Text(
                              'Chất lượng: ${s['quality'] ?? 3}/5',
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}
