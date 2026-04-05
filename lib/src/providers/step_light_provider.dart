import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/step_light_monitor_service.dart';

final stepLightMonitorProvider = Provider<StepLightMonitorService>((ref) {
  final service = StepLightMonitorService();
  unawaited(service.initialize());
  ref.onDispose(service.dispose);
  return service;
});
