import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/activity_entry.dart';

import '../providers/auth_provider.dart';
import '../providers/dashboard_refresh_provider.dart';
import '../services/activity_service.dart';
import '../utils/user_friendly_error.dart';

final _activityServiceProvider = Provider<ActivityService>(
  (ref) => ActivityService(),
);

final activityStreamProvider = StreamProvider<List<ActivityEntry>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.id;
  if (uid == null) return const Stream.empty();
  return ref.watch(_activityServiceProvider).watchActivities(uid);
});

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  static const double _defaultWeightKg = 65;

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('HH:mm • dd/MM/yyyy').format(dateTime);
  }

  DateTime _dayKey(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day);
  }

  Map<DateTime, List<ActivityEntry>> _groupByDay(List<ActivityEntry> items) {
    final grouped = <DateTime, List<ActivityEntry>>{};
    for (final item in items) {
      final key = _dayKey(item.createdAt);
      grouped.putIfAbsent(key, () => <ActivityEntry>[]).add(item);
    }
    return grouped;
  }

  String _dayHeaderLabel(DateTime day) {
    return DateFormat('dd/MM/yyyy').format(day);
  }

  IconData _activityIcon(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('chay') || normalized.contains('run')) {
      return Icons.directions_run;
    }
    if (normalized.contains('gym') || normalized.contains('tap')) {
      return Icons.fitness_center;
    }
    if (normalized.contains('dap') || normalized.contains('bike')) {
      return Icons.pedal_bike;
    }
    return Icons.directions_walk;
  }

  String _foldVietnamese(String input) {
    const replacements = <String, String>{
      'à': 'a',
      'á': 'a',
      'ạ': 'a',
      'ả': 'a',
      'ã': 'a',
      'â': 'a',
      'ầ': 'a',
      'ấ': 'a',
      'ậ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'ă': 'a',
      'ằ': 'a',
      'ắ': 'a',
      'ặ': 'a',
      'ẳ': 'a',
      'ẵ': 'a',
      'è': 'e',
      'é': 'e',
      'ẹ': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ê': 'e',
      'ề': 'e',
      'ế': 'e',
      'ệ': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ì': 'i',
      'í': 'i',
      'ị': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ò': 'o',
      'ó': 'o',
      'ọ': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ô': 'o',
      'ồ': 'o',
      'ố': 'o',
      'ộ': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ơ': 'o',
      'ờ': 'o',
      'ớ': 'o',
      'ợ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ù': 'u',
      'ú': 'u',
      'ụ': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ư': 'u',
      'ừ': 'u',
      'ứ': 'u',
      'ự': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ỳ': 'y',
      'ý': 'y',
      'ỵ': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
      'đ': 'd',
    };

    var text = input.toLowerCase();
    replacements.forEach((from, to) {
      text = text.replaceAll(from, to);
    });
    text = text.replaceAll(RegExp(r'[^a-z0-9\s,.-]'), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _detectActivityType(String text) {
    if (text.contains('chay') || text.contains('run')) {
      return 'chạy bộ';
    }
    if (text.contains('di bo') || text.contains('walk')) {
      return 'đi bộ';
    }
    if (text.contains('dap xe') ||
        text.contains('bike') ||
        text.contains('cycle')) {
      return 'đạp xe';
    }
    if (text.contains('boi') || text.contains('swim')) {
      return 'bơi';
    }
    if (text.contains('tap gym') ||
        text.contains('gym') ||
        text.contains('workout') ||
        text.contains('tap')) {
      return 'tập gym';
    }
    return 'hoạt động';
  }

  int _parseDurationMinutes(String text) {
    final hoursMatch = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(gio|h)\b',
    ).firstMatch(text);
    final minutesMatch = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(phut|p|m)\b',
    ).firstMatch(text);

    final hours = hoursMatch == null
        ? 0
        : (double.tryParse(hoursMatch.group(1)!.replaceAll(',', '.')) ?? 0)
              .round();
    final minutes = minutesMatch == null
        ? 0
        : (double.tryParse(minutesMatch.group(1)!.replaceAll(',', '.')) ?? 0)
              .round();

    return hours * 60 + minutes;
  }

  double _parseDistanceKm(String text) {
    final kmMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*km\b').firstMatch(text);
    if (kmMatch == null) return 0;
    return double.tryParse(kmMatch.group(1)!.replaceAll(',', '.')) ?? 0;
  }

  int _estimateCalories({
    required String type,
    required int durationMinutes,
    required double distanceKm,
  }) {
    final normalizedType = _foldVietnamese(type);
    final met = switch (normalizedType) {
      'chay bo' => 8.3,
      'di bo' => 3.8,
      'dap xe' => 6.8,
      'boi' => 7.0,
      'tap gym' => 5.0,
      _ => 4.5,
    };

    final durationCalories = durationMinutes > 0
        ? met * 3.5 * _defaultWeightKg / 200 * durationMinutes
        : 0.0;

    final distanceCalories = distanceKm > 0
        ? switch (normalizedType) {
            'chay bo' => distanceKm * 65,
            'di bo' => distanceKm * 45,
            'dap xe' => distanceKm * 35,
            'boi' => distanceKm * 80,
            'tap gym' => distanceKm * 55,
            _ => distanceKm * 50,
          }
        : 0.0;

    final calories = durationCalories > 0 && distanceCalories > 0
        ? (durationCalories * 0.6 + distanceCalories * 0.4)
        : (durationCalories > 0 ? durationCalories : distanceCalories);

    return calories.round();
  }

  String _formatTranscriptPreview(String text) {
    if (text.isEmpty) return 'Hãy nói ví dụ: “nay chạy bộ 30 phút được 2km”';
    return 'Đã nhận: $text';
  }

  void _applyVoiceText(
    String text,
    TextEditingController typeController,
    TextEditingController durationController,
    TextEditingController caloriesController,
    TextEditingController distanceController,
    void Function(void Function()) setModalState,
  ) {
    final normalized = _foldVietnamese(text);
    final type = _detectActivityType(normalized);
    final duration = _parseDurationMinutes(normalized);
    final distance = _parseDistanceKm(normalized);
    final calories = _estimateCalories(
      type: type,
      durationMinutes: duration,
      distanceKm: distance,
    );

    setModalState(() {
      if (type.isNotEmpty) typeController.text = type;
      if (duration > 0) durationController.text = '$duration';
      if (distance > 0) {
        distanceController.text = distance.toStringAsFixed(
          distance % 1 == 0 ? 0 : 2,
        );
      }
      if (calories > 0) caloriesController.text = '$calories';
    });
  }

  void _tryAutoEstimateFromText(
    TextEditingController typeController,
    TextEditingController durationController,
    TextEditingController distanceController,
    TextEditingController caloriesController,
    void Function(void Function()) setModalState,
  ) {
    final type = typeController.text.trim();
    final durationMinutes = int.tryParse(durationController.text.trim()) ?? 0;
    final distanceKm = double.tryParse(distanceController.text.trim()) ?? 0;

    if (type.isEmpty || durationMinutes <= 0 || distanceKm <= 0) {
      return;
    }

    final estimated = _estimateCalories(
      type: type,
      durationMinutes: durationMinutes,
      distanceKm: distanceKm,
    );

    if (estimated <= 0) {
      return;
    }

    if (caloriesController.text.trim() == '$estimated') {
      return;
    }

    setModalState(() {
      caloriesController.text = '$estimated';
    });
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final typeController = TextEditingController();
    final durationController = TextEditingController();
    final caloriesController = TextEditingController();
    final distanceController = TextEditingController();
    final speech = stt.SpeechToText();
    var isListening = false;
    var transcript = '';
    var speechReady = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> startListening() async {
            if (isListening) return;

            final available = await speech.initialize(
              onStatus: (status) {
                if (!dialogContext.mounted) return;
                if (status == 'done' || status == 'notListening') {
                  setModalState(() => isListening = false);
                }
              },
              onError: (error) {
                if (!dialogContext.mounted) return;
                setModalState(() {
                  isListening = false;
                  transcript =
                      'Không thể nhận giọng nói lúc này. Vui lòng thử lại.';
                });
              },
            );

            if (!available) {
              setModalState(() {
                transcript = 'Thiết bị chưa sẵn sàng cho nhận giọng nói.';
              });
              return;
            }

            setModalState(() {
              speechReady = true;
              isListening = true;
              transcript = '';
            });

            await speech.listen(
              localeId: 'vi_VN',
              onResult: (result) {
                final words = result.recognizedWords.trim();
                setModalState(() {
                  transcript = words;
                });
                if (words.isNotEmpty) {
                  _applyVoiceText(
                    words,
                    typeController,
                    durationController,
                    caloriesController,
                    distanceController,
                    setModalState,
                  );
                }
                if (result.finalResult) {
                  speech.stop();
                  setModalState(() => isListening = false);
                }
              },
            );
          }

          Future<void> stopListening() async {
            await speech.stop();
            if (!dialogContext.mounted) return;
            setModalState(() => isListening = false);
          }

          return AlertDialog(
            title: const Text('Thêm hoạt động'),
            scrollable: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            backgroundColor: scheme.surfaceContainerLow,
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.mic_none,
                              color: scheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Nhập hoạt động bằng giọng nói',
                                style: TextStyle(
                                  color: scheme.onTertiaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatTranscriptPreview(transcript),
                          style: TextStyle(
                            color: scheme.onTertiaryContainer.withValues(
                              alpha: 0.82,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isListening ? stopListening : startListening,
                      icon: Icon(isListening ? Icons.stop : Icons.mic),
                      label: Text(
                        isListening
                            ? 'Dừng ghi âm'
                            : speechReady
                            ? 'Nhập lại bằng giọng nói'
                            : 'Nhập bằng giọng nói',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: typeController,
                    decoration: const InputDecoration(
                      labelText: 'Loại (đi bộ/chạy bộ/tập gym)',
                    ),
                    onChanged: (_) {
                      _tryAutoEstimateFromText(
                        typeController,
                        durationController,
                        distanceController,
                        caloriesController,
                        setModalState,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Thời gian (phút)',
                    ),
                    onChanged: (_) {
                      _tryAutoEstimateFromText(
                        typeController,
                        durationController,
                        distanceController,
                        caloriesController,
                        setModalState,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: distanceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quãng đường (km)',
                    ),
                    onChanged: (_) {
                      _tryAutoEstimateFromText(
                        typeController,
                        durationController,
                        distanceController,
                        caloriesController,
                        setModalState,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: caloriesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Calories ước tính',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () async {
                  final uid = ref.read(authStateProvider).valueOrNull?.id;
                  if (uid == null) return;

                  final typeText = typeController.text.trim();
                  final durationMinutes =
                      int.tryParse(durationController.text.trim()) ?? 0;
                  final distanceKm =
                      double.tryParse(distanceController.text.trim()) ?? 0;
                  final caloriesText = caloriesController.text.trim();
                  final estimatedCalories =
                      int.tryParse(caloriesText) ??
                      _estimateCalories(
                        type: typeText,
                        durationMinutes: durationMinutes,
                        distanceKm: distanceKm,
                      );

                  final entry = ActivityEntry(
                    id: '',
                    type: typeText.isEmpty ? 'hoạt động' : typeText,
                    durationMinutes: durationMinutes,
                    calories: estimatedCalories,
                    distanceKm: distanceKm,
                    createdAt: DateTime.now(),
                  );

                  await ref
                      .read(_activityServiceProvider)
                      .addActivityAndUpdateDailyStats(uid, entry);
                  triggerDashboardRefresh(ref);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final data = ref.watch(activityStreamProvider);

    Widget buildActivityTile(ActivityEntry item) {
      return Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
        ),
        onDismissed: (_) async {
          final uid = ref.read(authStateProvider).valueOrNull?.id;
          if (uid == null) {
            return;
          }

          await ref
              .read(_activityServiceProvider)
              .deleteActivityAndUpdateDailyStats(uid, item);
          triggerDashboardRefresh(ref);

          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Đã xóa hoạt động')));
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.tertiaryContainer,
              child: Icon(
                _activityIcon(item.type),
                color: scheme.onTertiaryContainer,
              ),
            ),
            title: Text(
              item.type,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${item.durationMinutes} phút • ${item.distanceKm.toStringAsFixed(2)} km\n${_formatDateTime(item.createdAt)}',
            ),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.calories}',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'kcal',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        scrolledUnderElevation: 0,
        title: const Text('Nhật ký hoạt động'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'activity-fab',
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Thêm hoạt động'),
      ),
      body: data.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.directions_run,
                        size: 32,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Chưa có hoạt động nào',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nhấn Thêm hoạt động để bắt đầu ghi lại vận động mỗi ngày.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }
          final grouped = _groupByDay(items);
          final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

          return CustomScrollView(
            slivers: [
              for (final day in days) ...[
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ActivityDateHeaderDelegate(
                    label: _dayHeaderLabel(day),
                    colorScheme: scheme,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  sliver: SliverList.builder(
                    itemCount: grouped[day]!.length,
                    itemBuilder: (context, i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: buildActivityTile(grouped[day]![i]),
                      );
                    },
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 88)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              UserFriendlyError.message(
                e,
                fallback: 'Không thể tải nhật ký hoạt động lúc này.',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityDateHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  final ColorScheme colorScheme;

  const _ActivityDateHeaderDelegate({
    required this.label,
    required this.colorScheme,
  });

  @override
  double get minExtent => 44;

  @override
  double get maxExtent => 44;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      color: colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ActivityDateHeaderDelegate oldDelegate) {
    return oldDelegate.label != label || oldDelegate.colorScheme != colorScheme;
  }
}
