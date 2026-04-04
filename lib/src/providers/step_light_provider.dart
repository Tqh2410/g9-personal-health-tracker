import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/step_light_monitor_service.dart';

final stepLightMonitorProvider =
    ChangeNotifierProvider<StepLightMonitorService>((ref) {
      final service = StepLightMonitorService();
      service.initialize();
      ref.onDispose(service.dispose);
      return service;
    });
