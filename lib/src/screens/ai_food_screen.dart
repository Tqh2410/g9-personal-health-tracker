import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/auth_provider.dart';
import '../providers/dashboard_refresh_provider.dart';
import '../services/cloudflare_ai_service.dart';
import '../services/nutrition_log_service.dart';

class AiFoodScreen extends ConsumerStatefulWidget {
  final String? initialSource;

  const AiFoodScreen({super.key, this.initialSource});

  @override
  ConsumerState<AiFoodScreen> createState() => _AiFoodScreenState();
}

class _AiFoodScreenState extends ConsumerState<AiFoodScreen> {
  final _picker = ImagePicker();
  final _aiService = CloudflareAiService();
  final _nutritionLogService = NutritionLogService();

  File? _image;
  String _result = 'Chưa có kết quả';
  bool _loading = false;
  String? _foodName;
  int? _estimatedCalories;
  String? _pickedSourceLabel;
  bool _autoLaunched = false;
  bool _awaitingNutritionDecision = false;
  bool _savingNutrition = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoLaunched) {
        return;
      }

      final source = _parseInitialSource(widget.initialSource);
      if (source != null) {
        _autoLaunched = true;
        _pickAndAnalyze(source);
      }
    });
  }

  ImageSource? _parseInitialSource(String? value) {
    switch (value?.toLowerCase()) {
      case 'camera':
        return ImageSource.camera;
      case 'gallery':
      case 'library':
        return ImageSource.gallery;
      default:
        return null;
    }
  }

  String _labelForSource(ImageSource source) {
    return source == ImageSource.camera ? 'máy ảnh' : 'từ thiết bị';
  }

  String _friendlyAiError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();

    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network')) {
      return 'Không thể kết nối mạng. Vui lòng kiểm tra internet và thử lại.';
    }

    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'Yêu cầu AI bị quá thời gian chờ. Vui lòng thử lại với ảnh nhỏ hơn.';
    }

    if (lower.contains('401') || lower.contains('403')) {
      return 'Token Cloudflare không hợp lệ hoặc không đủ quyền. Vui lòng kiểm tra cấu hình API token.';
    }

    if (lower.contains('3010') ||
        lower.contains('3016') ||
        lower.contains('unsupported image')) {
      return 'Ảnh chưa đúng định dạng cho AI. Hãy thử ảnh rõ nét hơn hoặc chụp lại trực tiếp trong ứng dụng.';
    }

    if (lower.contains('chua cau hinh cloudflare')) {
      return 'Chưa cấu hình Cloudflare Workers AI. Hãy chạy app với --dart-define-from-file=env/cloudflare.local.json.';
    }

    return 'Phân tích AI thất bại. Vui lòng thử lại sau.';
  }

  Future<void> _pickAndAnalyze(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (file == null) return;

    setState(() {
      _image = File(file.path);
      _loading = true;
      _foodName = null;
      _estimatedCalories = null;
      _awaitingNutritionDecision = false;
      _pickedSourceLabel = _labelForSource(source);
      _result = 'Đang gửi ảnh đến Workers AI...';
    });

    try {
      final bytes = await file.readAsBytes();
      final res = await _aiService.estimateFoodFromImageBytes(bytes);

      if (!mounted) return;

      setState(() {
        _foodName = res.foodName;
        _estimatedCalories = res.estimatedCalories;
        _awaitingNutritionDecision = true;
        _result = res.notes?.isNotEmpty == true
            ? res.notes!
            : 'Nhận diện hoàn tất. Bạn có muốn thêm món này vào nhật ký dinh dưỡng không?';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _result = _friendlyAiError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _addToNutritionDiary() async {
    final foodName = _foodName;
    final calories = _estimatedCalories;
    final uid = ref.read(authStateProvider).valueOrNull?.id;

    if (foodName == null || calories == null) {
      return;
    }

    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn cần đăng nhập để lưu nhật ký dinh dưỡng.'),
        ),
      );
      return;
    }

    setState(() {
      _savingNutrition = true;
    });

    try {
      await _nutritionLogService.saveRecognizedFood(
        uid: uid,
        foodName: foodName,
        calories: calories,
        mealType: 'ai-recognized',
      );
      triggerDashboardRefresh(ref);

      if (!mounted) return;
      setState(() {
        _savingNutrition = false;
        _awaitingNutritionDecision = false;
        _result = 'Đã thêm món ăn vào nhật ký dinh dưỡng.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu vào nhật ký dinh dưỡng.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingNutrition = false;
        _result = 'Không thể lưu vào nhật ký dinh dưỡng. Vui lòng thử lại.';
      });
    }
  }

  void _skipNutritionDiary() {
    setState(() {
      _awaitingNutritionDecision = false;
      _result = 'Bạn đã chọn không thêm món ăn này vào nhật ký dinh dưỡng.';
    });
  }

  Future<void> _showSourcePicker() async {
    final scheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                const SizedBox(height: 14),
                const Text(
                  'Chọn nguồn ảnh',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          _pickAndAnalyze(ImageSource.camera);
                        },
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Chụp ảnh trực tiếp'),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _loading
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          _pickAndAnalyze(ImageSource.gallery);
                        },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Chọn ảnh có sẵn'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImagePreview(ColorScheme scheme) {
    return SizedBox(
      height: 240,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: _image == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.restaurant_outlined,
                      size: 54,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Chưa có ảnh món ăn',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(_image!, fit: BoxFit.cover),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _pickedSourceLabel == null
                              ? 'Ảnh đã chọn'
                              : _pickedSourceLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhận diện món ăn bằng AI'),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Chụp ảnh trực tiếp hoặc chọn ảnh có sẵn, Workers AI sẽ phân tích món ăn và ước tính kcal.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _buildImagePreview(scheme),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _loading ? null : _showSourcePicker,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(
                _loading ? 'Đang phân tích...' : 'Chọn ảnh để phân tích',
              ),
            ),
            const SizedBox(height: 12),
            if (_foodName != null || _estimatedCalories != null)
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: ListTile(
                  leading: const Icon(Icons.restaurant),
                  title: Text(_foodName ?? 'Không xác định'),
                  subtitle: Text(
                    _pickedSourceLabel == null
                        ? 'Kết quả nhận diện từ Workers AI'
                        : 'Nguồn: $_pickedSourceLabel',
                  ),
                  trailing: Text(
                    '${_estimatedCalories ?? 0} kcal',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            if (_awaitingNutritionDecision || _savingNutrition) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _savingNutrition ? null : _addToNutritionDiary,
                      icon: _savingNutrition
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.playlist_add_check),
                      label: Text(
                        _savingNutrition
                            ? 'Đang lưu...'
                            : 'Thêm vào nhật ký dinh dưỡng',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _savingNutrition ? null : _skipNutritionDiary,
                      icon: const Icon(Icons.close),
                      label: const Text('Không thêm'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _result,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
