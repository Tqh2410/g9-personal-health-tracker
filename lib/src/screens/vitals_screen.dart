import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/vital_entry.dart';
import '../providers/auth_provider.dart';
import '../services/vitals_service.dart';

final _vitalsServiceProvider = Provider<VitalsService>(
  (ref) => VitalsService(),
);

final vitalsStreamProvider = StreamProvider<List<VitalEntry>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.id;
  if (uid == null) return const Stream.empty();
  return ref.watch(_vitalsServiceProvider).watchVitals(uid);
});

class VitalsScreen extends ConsumerWidget {
  const VitalsScreen({super.key});

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('HH:mm • dd/MM/yyyy').format(dateTime);
  }

  String _formatShortDate(DateTime dateTime) {
    return DateFormat('dd/MM').format(dateTime);
  }

  DateTime _dayKey(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day);
  }

  Map<DateTime, List<VitalEntry>> _groupByDay(List<VitalEntry> items) {
    final grouped = <DateTime, List<VitalEntry>>{};
    for (final item in items) {
      final key = _dayKey(item.createdAt);
      grouped.putIfAbsent(key, () => <VitalEntry>[]).add(item);
    }
    return grouped;
  }

  String _dayHeaderLabel(DateTime day) {
    return DateFormat('dd/MM/yyyy').format(day);
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final weightController = TextEditingController();
    final heartRateController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm chỉ số'),
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: scheme.surfaceContainerLow,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Cân nặng (kg)'),
            ),
            TextField(
              controller: heartRateController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Nhịp tim (bpm)'),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () async {
              final uid = ref.read(authStateProvider).valueOrNull?.id;
              if (uid == null) return;
              await ref
                  .read(_vitalsServiceProvider)
                  .addVital(
                    uid,
                    VitalEntry(
                      id: '',
                      weightKg:
                          double.tryParse(weightController.text.trim()) ?? 0,
                      heartRate:
                          int.tryParse(heartRateController.text.trim()) ?? 0,
                      createdAt: DateTime.now(),
                    ),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final data = ref.watch(vitalsStreamProvider);

    Future<bool> confirmDeleteVital() async {
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Xóa nhật ký chỉ số'),
          content: const Text('Bạn có chắc muốn xóa bản ghi này không?'),
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

      return shouldDelete ?? false;
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        scrolledUnderElevation: 0,
        title: const Text('Chỉ số & biểu đồ'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: FilledButton.icon(
          onPressed: () => _showAddDialog(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Thêm chỉ số'),
        ),
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
                        Icons.monitor_heart_outlined,
                        size: 32,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Chưa có dữ liệu chỉ số',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nhấn nút Thêm chỉ số để bắt đầu theo dõi.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          final chartItems = [...items]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final heartItems = [...chartItems.reversed];
          final weightItems = chartItems
              .where((e) => e.weightKg > 0)
              .toList(growable: false)
              .reversed
              .toList(growable: false);

          final groupedHeart = _groupByDay(heartItems);
          final heartDays = groupedHeart.keys.toList()
            ..sort((a, b) => b.compareTo(a));
          final groupedWeight = _groupByDay(weightItems);
          final weightDays = groupedWeight.keys.toList()
            ..sort((a, b) => b.compareTo(a));

          final latest = chartItems.last;
          final heartRates = chartItems
              .map((e) => e.heartRate.toDouble())
              .toList(growable: false);
          final weights = weightItems
              .map((e) => e.weightKg)
              .toList(growable: false);

          final minHeartRate = heartRates.reduce((a, b) => a < b ? a : b);
          final maxHeartRate = heartRates.reduce((a, b) => a > b ? a : b);
          final minHeartY = (minHeartRate - 6).clamp(30, 220).toDouble();
          final maxHeartY = (maxHeartRate + 6).clamp(30, 220).toDouble();

          final latestWeight = weightItems.isNotEmpty
              ? weightItems.first
              : null;
          final minWeight = weights.isNotEmpty
              ? weights.reduce((a, b) => a < b ? a : b)
              : 0.0;
          final maxWeight = weights.isNotEmpty
              ? weights.reduce((a, b) => a > b ? a : b)
              : 0.0;
          final minWeightY = weights.isNotEmpty
              ? (minWeight - 1.0).clamp(20, 300).toDouble()
              : 20.0;
          final maxWeightY = weights.isNotEmpty
              ? (maxWeight + 1.0).clamp(20, 300).toDouble()
              : 120.0;

          Widget buildHeartChartCard() {
            final chartSpots = <FlSpot>[];
            for (var i = 0; i < chartItems.length; i++) {
              chartSpots.add(
                FlSpot(i.toDouble(), chartItems[i].heartRate.toDouble()),
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.favorite_outline, color: scheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'Xu hướng nhịp tim',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${latest.heartRate} bpm',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 210,
                      child: LineChart(
                        LineChartData(
                          minY: minHeartY,
                          maxY: maxHeartY,
                          lineTouchData: LineTouchData(enabled: true),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: 10,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.45,
                              ),
                              strokeWidth: 1,
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 36,
                                interval: 10,
                                getTitlesWidget: (value, meta) => Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 24,
                                getTitlesWidget: (value, meta) {
                                  if (weightItems.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  final middle = (chartItems.length - 1) / 2;
                                  final isFirst = value.toInt() == 0;
                                  final isMiddle =
                                      value.roundToDouble() ==
                                      middle.roundToDouble();
                                  final isLast =
                                      value.toInt() == chartItems.length - 1;

                                  if (!isFirst && !isMiddle && !isLast) {
                                    return const SizedBox.shrink();
                                  }

                                  final index = value.toInt().clamp(
                                    0,
                                    chartItems.length - 1,
                                  );
                                  return Text(
                                    _formatShortDate(
                                      chartItems[index].createdAt,
                                    ),
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: chartSpots,
                              isCurved: true,
                              color: scheme.primary,
                              barWidth: 3,
                              dotData: FlDotData(
                                show: true,
                                getDotPainter: (spot, percent, bar, index) {
                                  return FlDotCirclePainter(
                                    radius: 3.2,
                                    color: scheme.primary,
                                    strokeWidth: 1.5,
                                    strokeColor: scheme.surface,
                                  );
                                },
                              ),
                              belowBarData: BarAreaData(
                                show: true,
                                color: scheme.primary.withValues(alpha: 0.15),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          Widget buildWeightChartCard() {
            if (weightItems.isEmpty) {
              return Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.monitor_weight_outlined,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Xu hướng cân nặng',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Chưa có dữ liệu cân nặng. Hãy thêm chỉ số có cân nặng để hiển thị biểu đồ.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            }

            final chartSpots = <FlSpot>[];
            for (var i = 0; i < weightItems.length; i++) {
              chartSpots.add(FlSpot(i.toDouble(), weightItems[i].weightKg));
            }

            return Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.monitor_weight_outlined,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Xu hướng cân nặng',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${latestWeight!.weightKg.toStringAsFixed(1)} kg',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 210,
                      child: LineChart(
                        LineChartData(
                          minY: minWeightY,
                          maxY: maxWeightY,
                          lineTouchData: LineTouchData(enabled: true),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: 1,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.45,
                              ),
                              strokeWidth: 1,
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                interval: 1,
                                getTitlesWidget: (value, meta) => Text(
                                  value.toStringAsFixed(0),
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 24,
                                getTitlesWidget: (value, meta) {
                                  if (chartItems.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  final middle = (weightItems.length - 1) / 2;
                                  final isFirst = value.toInt() == 0;
                                  final isMiddle =
                                      value.roundToDouble() ==
                                      middle.roundToDouble();
                                  final isLast =
                                      value.toInt() == weightItems.length - 1;

                                  if (!isFirst && !isMiddle && !isLast) {
                                    return const SizedBox.shrink();
                                  }

                                  final index = value.toInt().clamp(
                                    0,
                                    weightItems.length - 1,
                                  );
                                  return Text(
                                    _formatShortDate(
                                      weightItems[index].createdAt,
                                    ),
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: chartSpots,
                              isCurved: true,
                              color: scheme.tertiary,
                              barWidth: 3,
                              dotData: FlDotData(
                                show: true,
                                getDotPainter: (spot, percent, bar, index) {
                                  return FlDotCirclePainter(
                                    radius: 3.2,
                                    color: scheme.tertiary,
                                    strokeWidth: 1.5,
                                    strokeColor: scheme.surface,
                                  );
                                },
                              ),
                              belowBarData: BarAreaData(
                                show: true,
                                color: scheme.tertiary.withValues(alpha: 0.15),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          Widget buildHeartListItem(VitalEntry e) {
            return Dismissible(
              key: ValueKey('heart-${e.id}'),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => confirmDeleteVital(),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: scheme.onErrorContainer,
                ),
              ),
              onDismissed: (_) async {
                final uid = ref.read(authStateProvider).valueOrNull?.id;
                if (uid == null) {
                  return;
                }

                await ref.read(_vitalsServiceProvider).deleteVital(uid, e.id);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã xóa nhật ký chỉ số')),
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
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.favorite,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text('${e.heartRate} bpm'),
                  subtitle: Text(_formatDateTime(e.createdAt)),
                  trailing: Text(
                    '${e.weightKg.toStringAsFixed(1)} kg',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }

          Widget buildWeightListItem(VitalEntry e) {
            return Dismissible(
              key: ValueKey('weight-${e.id}'),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => confirmDeleteVital(),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: scheme.onErrorContainer,
                ),
              ),
              onDismissed: (_) async {
                final uid = ref.read(authStateProvider).valueOrNull?.id;
                if (uid == null) {
                  return;
                }

                await ref.read(_vitalsServiceProvider).deleteVital(uid, e.id);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã xóa nhật ký chỉ số')),
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
                      Icons.monitor_weight_outlined,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  title: Text('${e.weightKg.toStringAsFixed(1)} kg'),
                  subtitle: Text(_formatDateTime(e.createdAt)),
                  trailing: Text(
                    '${e.heartRate} bpm',
                    style: TextStyle(
                      color: scheme.tertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }

          Widget buildTabContent({
            required Widget chart,
            required Widget Function(VitalEntry) itemBuilder,
            required List<DateTime> days,
            required Map<DateTime, List<VitalEntry>> grouped,
          }) {
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  sliver: SliverToBoxAdapter(child: chart),
                ),
                for (final day in days) ...[
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _VitalsDateHeaderDelegate(
                      label: _dayHeaderLabel(day),
                      colorScheme: scheme,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    sliver: SliverList.builder(
                      itemCount: grouped[day]!.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: itemBuilder(grouped[day]![i]),
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            );
          }

          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  alignment: Alignment.centerLeft,
                  child: const TabBar(
                    tabs: [
                      Tab(text: 'Nhịp tim'),
                      Tab(text: 'Cân nặng'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      buildTabContent(
                        chart: buildHeartChartCard(),
                        itemBuilder: buildHeartListItem,
                        days: heartDays,
                        grouped: groupedHeart,
                      ),
                      buildTabContent(
                        chart: buildWeightChartCard(),
                        itemBuilder: buildWeightListItem,
                        days: weightDays,
                        grouped: groupedWeight,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
      ),
    );
  }
}

class _VitalsDateHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  final ColorScheme colorScheme;

  const _VitalsDateHeaderDelegate({
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
  bool shouldRebuild(covariant _VitalsDateHeaderDelegate oldDelegate) {
    return oldDelegate.label != label || oldDelegate.colorScheme != colorScheme;
  }
}
