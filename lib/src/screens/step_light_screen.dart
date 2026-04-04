import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/step_light_provider.dart';
import '../services/step_light_monitor_service.dart';
import '../utils/user_friendly_error.dart';

class StepLightScreen extends ConsumerStatefulWidget {
  const StepLightScreen({super.key});

  @override
  ConsumerState<StepLightScreen> createState() => _StepLightScreenState();
}

class _StepLightScreenState extends ConsumerState<StepLightScreen> {
  StepLightMonitorService get _monitor => ref.watch(stepLightMonitorProvider);
  int get _steps => _monitor.steps;
  int get _syncedSteps => _monitor.syncedSteps;
  int get _lightLux => _monitor.lightLux;
  String get _status => _monitor.status;
  bool get _hasNotificationPermission => _monitor.hasNotificationPermission;
  bool get _hasActivityPermission => _monitor.hasActivityPermission;
  bool get _hasBatteryExemption => _monitor.hasBatteryExemption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalSteps = _syncedSteps > 0 ? _syncedSteps : _steps;
    final stepProgress = (totalSteps % 10000) / 10000;
    final lightIsLow = _lightLux < 15;
    final safeStatus = UserFriendlyError.message(
      _status,
      fallback: 'Theo dõi bước chân và ánh sáng đang hoạt động.',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Theo dõi bước chân & ánh sáng'),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user_outlined, color: scheme.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'Quyền hệ thống',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.tonal(
                        onPressed: () async {
                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Đang kiểm tra và xin quyền...'),
                              ),
                            );

                            final result = await _monitor
                                .requestRuntimePermissions();
                            if (!context.mounted) return;

                            if (result.hasPermanentDenied) {
                              final shouldOpenSettings = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Cần mở Cài đặt hệ thống'),
                                  content: const Text(
                                    'Một số quyền đã bị từ chối vĩnh viễn. Hãy mở Cài đặt ứng dụng để cấp quyền chạy nền và thông báo.',
                                  ),
                                  actions: [
                                    OutlinedButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      child: const Text('Để sau'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, true),
                                      child: const Text('Mở cài đặt'),
                                    ),
                                  ],
                                ),
                              );

                              if (shouldOpenSettings == true) {
                                await openAppSettings();
                                await _monitor.syncPermissionStates();
                                if (!context.mounted) return;
                              }
                            }

                            if (!context.mounted) return;

                            if (!result.hasNotificationPermission ||
                                !result.hasActivityPermission) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Chưa cấp đủ quyền. Vui lòng cấp quyền để tiếp tục.',
                                  ),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result.changed
                                        ? 'Đã cập nhật quyền thành công.'
                                        : 'Quyền đã được cấp trước đó.',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  UserFriendlyError.message(
                                    e,
                                    fallback:
                                        'Không thể cập nhật quyền lúc này. Vui lòng thử lại.',
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('Cấp quyền'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          _hasNotificationPermission
                              ? 'Thông báo: Đã cấp'
                              : 'Thông báo: Chưa cấp',
                        ),
                        avatar: Icon(
                          _hasNotificationPermission
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 18,
                        ),
                      ),
                      Chip(
                        label: Text(
                          _hasActivityPermission
                              ? 'Chạy nền: Đã cấp'
                              : 'Chạy nền: Chưa cấp',
                        ),
                        avatar: Icon(
                          _hasActivityPermission
                              ? Icons.directions_walk
                              : Icons.error_outline,
                          size: 18,
                        ),
                      ),
                      Chip(
                        label: Text(
                          _hasBatteryExemption
                              ? 'Pin nền: Đã tối ưu'
                              : 'Pin nền: Nên bật',
                        ),
                        avatar: Icon(
                          _hasBatteryExemption
                              ? Icons.battery_saver
                              : Icons.battery_alert_outlined,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
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
                  Row(
                    children: [
                      Icon(Icons.directions_walk, color: scheme.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'Theo dõi bước chân',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$totalSteps bước',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                  Text('Mục tiêu hôm nay: 10.000 bước'),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(value: stepProgress),
                  ),
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
                  Row(
                    children: [
                      Icon(
                        lightIsLow
                            ? Icons.wb_incandescent_outlined
                            : Icons.wb_sunny_outlined,
                        color: lightIsLow ? scheme.error : scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Ánh sáng môi trường',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_lightLux lux',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: lightIsLow ? scheme.error : scheme.primary,
                    ),
                  ),
                  Text(
                    lightIsLow
                        ? 'Cảnh báo: đôi mắt đang làm việc trong môi trường tối.'
                        : 'Ánh sáng ở mức ổn.',
                  ),
                ],
              ),
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
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(safeStatus)),
                ],
              ),
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Ghi chú',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tính năng chạy nền hoàn chỉnh và tích hợp HealthKit/Google Fit sẽ cần bổ sung theo từng nền tảng. Hiện tại đây là MVP theo dõi cảm biến cho ứng dụng.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () async {
              await _monitor.resetStepSession();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đã đặt lại phiên đếm trên thiết bị.'),
                ),
              );
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Đặt lại phiên trên thiết bị'),
          ),
        ],
      ),
    );
  }
}
