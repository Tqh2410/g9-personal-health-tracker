import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/nutrition_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_refresh_provider.dart';
import '../services/nutrition_service.dart';
import '../utils/user_friendly_error.dart';

final _nutritionServiceProvider = Provider<NutritionService>(
  (ref) => NutritionService(),
);

final nutritionStreamProvider = StreamProvider<List<NutritionEntry>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.id;
  if (uid == null) return const Stream.empty();
  return ref.watch(_nutritionServiceProvider).watchNutrition(uid);
});

class NutritionScreen extends ConsumerWidget {
  const NutritionScreen({super.key});

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('HH:mm • dd/MM/yyyy').format(dateTime);
  }

  IconData _mealIcon(String mealType) {
    final normalized = mealType.toLowerCase();
    if (normalized == 'ai-recognized') {
      return Icons.auto_awesome;
    }
    if (normalized.contains('sang') || normalized.contains('breakfast')) {
      return Icons.wb_sunny_outlined;
    }
    if (normalized.contains('toi') || normalized.contains('dinner')) {
      return Icons.nightlight_round;
    }
    return Icons.restaurant_outlined;
  }

  String _mealTypeLabel(String mealType) {
    final normalized = mealType.trim().toLowerCase();
    if (normalized == 'ai-recognized') {
      return '(AI)';
    }
    if (normalized == 'thao tác nhanh') {
      return '';
    }
    return mealType;
  }

  String _nutritionTitle(NutritionEntry item) {
    final label = _mealTypeLabel(item.mealType).trim();
    if (label.isEmpty) {
      return item.food;
    }
    return '$label • ${item.food}';
  }

  DateTime _dayKey(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day);
  }

  Map<DateTime, List<NutritionEntry>> _groupByDay(List<NutritionEntry> items) {
    final grouped = <DateTime, List<NutritionEntry>>{};
    for (final item in items) {
      final key = _dayKey(item.createdAt);
      grouped.putIfAbsent(key, () => <NutritionEntry>[]).add(item);
    }
    return grouped;
  }

  String _dayHeaderLabel(DateTime day) {
    return DateFormat('dd/MM/yyyy').format(day);
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

  String _detectMealType(String text) {
    if (text.contains('sang') || text.contains('breakfast')) return 'bữa sáng';
    if (text.contains('trua') || text.contains('lunch')) return 'bữa trưa';
    if (text.contains('toi') || text.contains('dinner')) return 'bữa tối';
    if (text.contains('phu') || text.contains('snack')) return 'bữa phụ';
    return 'bữa ăn';
  }

  int _parseCalories(String text) {
    final match = RegExp(r'(\d+)\s*(kcal|calo|calories|cal)').firstMatch(text);
    if (match == null) return 0;
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }

  double _parseWaterLiters(String text) {
    final literMatch = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(l|lit|litre)\b',
    ).firstMatch(text);
    if (literMatch != null) {
      return double.tryParse(literMatch.group(1)!.replaceAll(',', '.')) ?? 0;
    }

    final mlMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*(ml)\b').firstMatch(text);
    if (mlMatch != null) {
      final ml = double.tryParse(mlMatch.group(1)!.replaceAll(',', '.')) ?? 0;
      return ml / 1000;
    }

    return 0;
  }

  String _parseFood(String text) {
    final raw = text.trim().replaceAll(RegExp(r'\s+'), ' ');

    final afterEat = RegExp(
      r'\b(?:an|ăn|uong|uống)\s+(.+?)(?:$|\d+(?:[.,]\d+)?\s*(?:kcal|calo|calories|cal|l|lit|litre|ml)\b)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (afterEat != null) {
      final food = (afterEat.group(1) ?? '').trim();
      if (food.isNotEmpty) return food;
    }

    final cleaned = raw
        .replaceAll(
          RegExp(
            r'\d+(?:[.,]\d+)?\s*(kcal|calo|calories|cal|l|lit|litre|ml)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(sang|trua|toi|breakfast|lunch|dinner|snack|bua|sáng|trưa|tối|bữa|ăn|uống)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return cleaned.isEmpty ? 'món ăn' : cleaned;
  }

  String _transcriptHint(String text) {
    if (text.isEmpty) {
      return 'Ví dụ: “trưa nay ăn cơm gà 600 calo uống 500ml nước”';
    }
    return 'Đã nhận: $text';
  }

  Future<bool> _confirmDeleteNutrition(
    BuildContext context,
    String food,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa bản ghi dinh dưỡng'),
        content: Text('Bạn có chắc muốn xóa bản ghi "$food" không?'),
        actions: [
          OutlinedButton(
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

    return shouldDelete ?? false;
  }

  void _applyVoiceNutrition(
    String speechText,
    TextEditingController mealController,
    TextEditingController foodController,
    TextEditingController caloriesController,
    TextEditingController waterController,
    void Function(void Function()) setModalState,
  ) {
    final normalized = _foldVietnamese(speechText);
    final mealType = _detectMealType(normalized);
    final food = _parseFood(speechText);
    final spokenCalories = _parseCalories(normalized);
    final calories = spokenCalories > 0
        ? spokenCalories
        : _estimateCaloriesFromFoodText(mealType: mealType, food: food);
    final waterLiters = _parseWaterLiters(normalized);

    setModalState(() {
      mealController.text = mealType;
      foodController.text = food;
      if (calories > 0) {
        caloriesController.text = '$calories';
      }
      if (waterLiters > 0) {
        waterController.text = waterLiters.toStringAsFixed(
          waterLiters % 1 == 0 ? 0 : 2,
        );
      }
    });
  }

  int _estimateCaloriesFromFoodText({
    required String mealType,
    required String food,
  }) {
    final normalizedMeal = _foldVietnamese(mealType);
    final normalizedFood = _foldVietnamese(food);

    var baseCalories = 320;
    final presets = <Pattern, int>{
      'com ga': 620,
      'com suon': 680,
      'pho bo': 480,
      'bun bo': 540,
      'bun cha': 650,
      'banh mi': 360,
      'mi tom': 380,
      'salad': 240,
      'trung': 160,
      'ga ran': 520,
      'pizza': 700,
      'hamburger': 620,
      'sua': 150,
      'tra sua': 340,
      'sinh to': 280,
      'chuoi': 110,
      'tao': 95,
      'cam': 85,
      'ca hoi': 320,
      'thit bo': 360,
      'thit heo': 330,
      'sup': 220,
    };

    for (final entry in presets.entries) {
      if (normalizedFood.contains(entry.key.toString())) {
        baseCalories = entry.value;
        break;
      }
    }

    final quantityMatch = RegExp(
      r'\b(\d+(?:[.,]\d+)?)\b',
    ).firstMatch(normalizedFood);
    final quantity = quantityMatch == null
        ? 1.0
        : (double.tryParse(quantityMatch.group(1)!.replaceAll(',', '.')) ?? 1.0)
              .clamp(0.5, 3.0);

    final mealFactor = switch (normalizedMeal) {
      'bua sang' => 0.9,
      'bua trua' => 1.0,
      'bua toi' => 1.0,
      'bua phu' => 0.7,
      _ => 1.0,
    };

    return (baseCalories * quantity * mealFactor).round();
  }

  void _tryAutoEstimateFromText(
    TextEditingController mealController,
    TextEditingController foodController,
    TextEditingController waterController,
    TextEditingController caloriesController,
    void Function(void Function()) setModalState,
  ) {
    final mealType = mealController.text.trim();
    final food = foodController.text.trim();
    final waterLiters = double.tryParse(waterController.text.trim()) ?? 0;

    // Auto estimate after enough text context is provided.
    if (mealType.isEmpty || food.isEmpty || waterLiters <= 0) {
      return;
    }

    final estimated = _estimateCaloriesFromFoodText(
      mealType: mealType,
      food: food,
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
    final mealController = TextEditingController();
    final foodController = TextEditingController();
    final caloriesController = TextEditingController();
    final waterController = TextEditingController();
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
                  _applyVoiceNutrition(
                    words,
                    mealController,
                    foodController,
                    caloriesController,
                    waterController,
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
            title: const Text('Thêm bản ghi dinh dưỡng'),
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
                                'Nhập dinh dưỡng bằng giọng nói',
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
                          _transcriptHint(transcript),
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
                    controller: mealController,
                    decoration: const InputDecoration(labelText: 'Loại bữa ăn'),
                    onChanged: (_) {
                      _tryAutoEstimateFromText(
                        mealController,
                        foodController,
                        waterController,
                        caloriesController,
                        setModalState,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: foodController,
                    decoration: const InputDecoration(labelText: 'Món ăn'),
                    onChanged: (_) {
                      _tryAutoEstimateFromText(
                        mealController,
                        foodController,
                        waterController,
                        caloriesController,
                        setModalState,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: caloriesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Calories'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: waterController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Nước (L)'),
                    onChanged: (_) {
                      _tryAutoEstimateFromText(
                        mealController,
                        foodController,
                        waterController,
                        caloriesController,
                        setModalState,
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () async {
                  final uid = ref.read(authStateProvider).valueOrNull?.id;
                  if (uid == null) return;

                  final entry = NutritionEntry(
                    id: '',
                    mealType: mealController.text.trim().isEmpty
                        ? 'bữa ăn'
                        : mealController.text.trim(),
                    food: foodController.text.trim().isEmpty
                        ? 'món ăn'
                        : foodController.text.trim(),
                    calories: int.tryParse(caloriesController.text.trim()) ?? 0,
                    waterLiters:
                        double.tryParse(waterController.text.trim()) ?? 0,
                    createdAt: DateTime.now(),
                  );

                  await ref
                      .read(_nutritionServiceProvider)
                      .addNutritionAndUpdateDailyStats(uid, entry);
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
    final data = ref.watch(nutritionStreamProvider);

    Widget buildNutritionTile(NutritionEntry item) {
      return Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmDeleteNutrition(context, item.food),
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
              .read(_nutritionServiceProvider)
              .deleteNutritionAndUpdateDailyStats(uid, item);
          triggerDashboardRefresh(ref);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã xóa bản ghi dinh dưỡng')),
            );
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
                _mealIcon(item.mealType),
                color: scheme.onTertiaryContainer,
              ),
            ),
            title: Text(
              _nutritionTitle(item),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Nước: ${item.waterLiters.toStringAsFixed(2)} L\n${_formatDateTime(item.createdAt)}',
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
        title: const Text('Nhật ký dinh dưỡng'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nutrition-fab',
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Thêm dinh dưỡng'),
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
                        Icons.local_dining_outlined,
                        size: 32,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Chưa có bản ghi dinh dưỡng',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Thêm bữa ăn để theo dõi calories và lượng nước mỗi ngày.',
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
                  delegate: _DateHeaderDelegate(
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
                        child: buildNutritionTile(grouped[day]![i]),
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
                fallback: 'Không thể tải nhật ký dinh dưỡng lúc này.',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _DateHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  final ColorScheme colorScheme;

  const _DateHeaderDelegate({required this.label, required this.colorScheme});

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
  bool shouldRebuild(covariant _DateHeaderDelegate oldDelegate) {
    return oldDelegate.label != label || oldDelegate.colorScheme != colorScheme;
  }
}
