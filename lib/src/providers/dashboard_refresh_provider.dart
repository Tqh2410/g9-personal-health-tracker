import 'package:flutter_riverpod/flutter_riverpod.dart';

final dashboardRefreshTriggerProvider = StateProvider<int>((ref) => 0);

void triggerDashboardRefresh(WidgetRef ref) {
  ref.read(dashboardRefreshTriggerProvider.notifier).state++;
}
