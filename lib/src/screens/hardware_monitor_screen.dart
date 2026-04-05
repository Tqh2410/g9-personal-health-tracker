import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/router.dart';
import '../providers/auth_provider.dart';
import '../services/vitals_service.dart';

final _vitalsServiceProvider = Provider<VitalsService>(
  (ref) => VitalsService(),
);

class HeartRateMeasurementScreen extends ConsumerStatefulWidget {
  const HeartRateMeasurementScreen({super.key});

  @override
  ConsumerState<HeartRateMeasurementScreen> createState() =>
      _HeartRateMeasurementScreenState();
}

class _PulseSample {
  final DateTime timestamp;
  final double intensity;

  const _PulseSample(this.timestamp, this.intensity);
}

class _HeartRateMeasurementScreenState
    extends ConsumerState<HeartRateMeasurementScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  bool _loadingCamera = true;
  bool _cameraPermissionDenied = false;
  bool _isMeasuring = false;
  bool _isSaving = false;
  bool _processingFrame = false;
  int? _heartRate;
  String _status = 'Cho phép camera, sau đó đặt ngón tay lên camera sau.';
  DateTime? _measurementStartedAt;
  Timer? _autoStopTimer;
  final List<_PulseSample> _samples = <_PulseSample>[];
  final List<DateTime> _peakTimes = <DateTime>[];
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _prepareCamera();
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _stopStreamAndFlash();
    _pulseController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepareCamera() async {
    setState(() {
      _loadingCamera = true;
      _cameraPermissionDenied = false;
    });

    final cameraPermission = await Permission.camera.request();
    if (!cameraPermission.isGranted) {
      if (mounted) {
        setState(() {
          _loadingCamera = false;
          _cameraPermissionDenied = true;
        });
      }
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera available');
      }

      final preferredCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        preferredCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _loadingCamera = false;
        _status = 'Đặt ngón tay phủ kín camera sau và đèn flash.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingCamera = false;
          _status = 'Không thể khởi tạo camera trên thiết bị này.';
        });
      }
    }
  }

  Future<void> _startMeasurement() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    _samples.clear();
    _peakTimes.clear();

    setState(() {
      _heartRate = null;
      _isMeasuring = true;
      _status = 'Giữ yên ngón tay trong 12-15 giây để lấy nhịp.';
      _measurementStartedAt = DateTime.now();
    });

    try {
      await controller.setFlashMode(FlashMode.torch);
      await controller.startImageStream(_onCameraImage);
      _autoStopTimer?.cancel();
      _autoStopTimer = Timer(const Duration(seconds: 15), () {
        if (mounted && _isMeasuring) {
          _finishMeasurement(save: true);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isMeasuring = false;
          _status = 'Không thể bật đo trực tiếp trên camera này.';
        });
      }
    }
  }

  Future<void> _finishMeasurement({required bool save}) async {
    if (!_isMeasuring) {
      if (save) {
        await _saveMeasurement();
      }
      return;
    }

    _autoStopTimer?.cancel();
    await _stopStreamAndFlash();

    if (mounted) {
      setState(() {
        _isMeasuring = false;
        _status = save
            ? 'Đã dừng đo. Đang lưu kết quả...'
            : 'Đã dừng đo. Bạn có thể đo lại.';
      });
    }

    if (save) {
      await _saveMeasurement();
    }
  }

  Future<void> _stopStreamAndFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Ignore stop errors while disposing.
    }

    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {
      // Some devices do not allow toggling flash after stream stop.
    }
  }

  void _onCameraImage(CameraImage image) {
    if (!_isMeasuring || _processingFrame) {
      return;
    }

    _processingFrame = true;
    try {
      final now = DateTime.now();
      final intensity = _averageLuma(image);
      final sample = _PulseSample(now, intensity);

      _samples.add(sample);
      _samples.removeWhere(
        (item) => now.difference(item.timestamp).inSeconds > 12,
      );

      if (_samples.length < 4) {
        return;
      }

      final previous = _samples[_samples.length - 3];
      final middle = _samples[_samples.length - 2];
      final current = _samples[_samples.length - 1];

      final values = _samples
          .map((item) => item.intensity)
          .toList(growable: false);
      final mean = values.reduce((a, b) => a + b) / values.length;
      final variance =
          values.fold<double>(
            0,
            (sum, value) => sum + math.pow(value - mean, 2).toDouble(),
          ) /
          values.length;
      final threshold = mean + math.sqrt(variance) * 0.12;

      final looksLikePeak =
          middle.intensity > previous.intensity &&
          middle.intensity > current.intensity &&
          middle.intensity > threshold;

      if (looksLikePeak) {
        final lastAccepted = _peakTimes.isNotEmpty ? _peakTimes.last : null;
        if (lastAccepted == null ||
            middle.timestamp.difference(lastAccepted).inMilliseconds > 320) {
          _peakTimes.add(middle.timestamp);
          _peakTimes.removeWhere((item) => now.difference(item).inSeconds > 12);

          if (_peakTimes.length >= 2) {
            final intervals = <double>[];
            for (var i = 1; i < _peakTimes.length; i++) {
              intervals.add(
                _peakTimes[i].difference(_peakTimes[i - 1]).inMilliseconds /
                    1000,
              );
            }

            final recentIntervals = intervals.length > 5
                ? intervals.sublist(intervals.length - 5)
                : intervals;
            final averageInterval =
                recentIntervals.reduce((a, b) => a + b) /
                recentIntervals.length;
            final computedHeartRate = (60 / averageInterval).round();

            if (computedHeartRate >= 35 &&
                computedHeartRate <= 220 &&
                mounted) {
              setState(() {
                _heartRate = computedHeartRate;
                _status = 'Đã bắt được nhịp mạch. Giữ yên thêm vài giây.';
              });
            }
          }
        }
      }

      if (mounted) {
        final elapsedSeconds = _measurementStartedAt == null
            ? 0
            : now.difference(_measurementStartedAt!).inSeconds;
        if (_isMeasuring &&
            elapsedSeconds >= 4 &&
            _heartRate != null &&
            _status != 'Đang tinh chỉnh kết quả đo...') {
          setState(() {
            _status = 'Đang tinh chỉnh kết quả đo...';
          });
        }
      }
    } finally {
      _processingFrame = false;
    }
  }

  double _averageLuma(CameraImage image) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final width = image.width;
    final height = image.height;
    final rowStride = plane.bytesPerRow;

    final startX = (width * 0.32).floor();
    final endX = (width * 0.68).ceil();
    final startY = (height * 0.32).floor();
    final endY = (height * 0.68).ceil();

    var total = 0;
    var count = 0;

    for (var y = startY; y < endY; y += 3) {
      final rowOffset = y * rowStride;
      for (var x = startX; x < endX; x += 3) {
        total += bytes[rowOffset + x];
        count++;
      }
    }

    if (count == 0) {
      return 0;
    }

    return total / count;
  }

  Future<void> _saveMeasurement() async {
    final bpm = _heartRate;
    final uid = ref.read(authStateProvider).valueOrNull?.id;

    if (bpm == null) {
      if (mounted) {
        setState(() {
          _status = 'Chưa đủ dữ liệu để lưu. Hãy đo lâu hơn một chút.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa đủ dữ liệu để lưu nhịp tim.')),
        );
      }
      return;
    }

    if (uid == null || uid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bạn cần đăng nhập để lưu nhịp tim.')),
        );
      }
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await ref.read(_vitalsServiceProvider).saveMeasuredHeartRate(uid, bpm);
      ref.invalidate(dashboardStatsProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã lưu nhịp tim $bpm bpm vào trang chủ và biểu đồ.'),
        ),
      );
      context.go('/home');
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = 'Không thể lưu kết quả. Hãy thử lại.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể lưu kết quả đo.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _formatElapsed() {
    final startedAt = _measurementStartedAt;
    if (startedAt == null) {
      return '00:00';
    }

    final elapsed = DateTime.now().difference(startedAt);
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildPulseCircle(ColorScheme scheme) {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulse = 0.82 + (_pulseController.value * 0.18);
          final hasReading = _heartRate != null;

          return Transform.scale(
            scale: pulse,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    scheme.errorContainer.withValues(alpha: 0.98),
                    scheme.primary.withValues(alpha: 0.94),
                    scheme.primary.withValues(alpha: 0.72),
                    scheme.primary.withValues(alpha: 0.08),
                  ],
                  stops: const [0.18, 0.52, 0.78, 1],
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.42),
                    blurRadius: 36,
                    spreadRadius: 8,
                  ),
                  BoxShadow(
                    color: scheme.errorContainer.withValues(alpha: 0.22),
                    blurRadius: 60,
                    spreadRadius: 20,
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.34),
                  width: 2,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasReading ? Icons.favorite : Icons.fingerprint,
                        color: Colors.white,
                        size: 44,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        hasReading ? '${_heartRate!} bpm' : 'Đặt ngón tay',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'lên camera sau',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSave = _heartRate != null && !_isSaving;
    final controller = _controller;
    final progressValue = _measurementStartedAt == null
        ? null
        : math
              .min(
                1.0,
                DateTime.now()
                        .difference(_measurementStartedAt!)
                        .inMilliseconds /
                    15000,
              )
              .toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đo nhịp tim trực tiếp'),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: _loadingCamera
            ? const Center(child: CircularProgressIndicator())
            : _cameraPermissionDenied
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.videocam_off_outlined,
                        size: 54,
                        color: scheme.error,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Ứng dụng cần quyền camera để đo nhịp tim.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Bạn có thể bật lại quyền trong Cài đặt để sử dụng chức năng này.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: openAppSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Mở cài đặt'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: LinearGradient(
                              colors: [scheme.primary, scheme.tertiary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: 0.18),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Đặt ngón tay vào vòng sáng',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Úp ngón tay phủ kín camera sau và đèn flash. Giữ yên trong 12-15 giây để ứng dụng ước tính nhịp tim.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _buildInfoChip(
                                    icon: Icons.timer_outlined,
                                    label: 'Thời gian',
                                    value: _formatElapsed(),
                                  ),
                                  _buildInfoChip(
                                    icon: Icons.favorite_outline,
                                    label: 'Nhịp tim',
                                    value: _heartRate != null
                                        ? '$_heartRate bpm'
                                        : '-- bpm',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildPulseCircle(scheme),
                        const SizedBox(height: 18),
                        Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.monitor_heart_outlined,
                                      color: scheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Trạng thái đo',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _status,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                                if (_isMeasuring) ...[
                                  const SizedBox(height: 14),
                                  LinearProgressIndicator(value: progressValue),
                                ],
                                if (controller != null &&
                                    controller.value.isInitialized) ...[
                                  const SizedBox(height: 14),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: AspectRatio(
                                      aspectRatio: controller.value.aspectRatio,
                                      child: CameraPreview(controller),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Lưu ý',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Kết quả là ước tính từ camera và đèn flash. Đặt tay thật ổn định, không che quá lỏng và không nhấn mạnh vào cảm biến.',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isMeasuring ? null : _prepareCamera,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Khởi tạo lại'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSaving
                                ? null
                                : _isMeasuring
                                ? () => _finishMeasurement(save: true)
                                : _startMeasurement,
                            icon: Icon(
                              _isMeasuring ? Icons.stop : Icons.play_arrow,
                            ),
                            label: Text(
                              _isMeasuring ? 'Dừng & lưu' : 'Bắt đầu đo',
                            ),
                          ),
                        ),
                        if (canSave) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _isSaving ? null : _saveMeasurement,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Lưu hồ sơ'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
