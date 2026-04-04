import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/nutrition_entry.dart';

class NutritionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _activityMealTypeLabel(String mealType) {
    final normalized = mealType.trim().toLowerCase();
    if (normalized == 'ai-recognized') {
      return '(AI)';
    }
    if (normalized == 'thao tác nhanh') {
      return '';
    }
    return mealType;
  }

  CollectionReference<Map<String, dynamic>> _col(String uid) {
    return _db.collection('users').doc(uid).collection('nutrition');
  }

  Stream<List<NutritionEntry>> watchNutrition(String uid) {
    return _col(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => NutritionEntry.fromMap(d.id, d.data()))
              .toList(growable: false),
        );
  }

  Future<void> addNutrition(String uid, NutritionEntry entry) async {
    await _col(uid).add(entry.toMap());
  }

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _nutritionSummary(NutritionEntry entry) {
    final label = _activityMealTypeLabel(entry.mealType).trim();
    final prefix = label.isEmpty ? '' : '$label: ';
    return '$prefix${entry.food}, ${entry.calories} kcal, ${entry.waterLiters.toStringAsFixed(2)} L nước';
  }

  Future<void> addNutritionAndUpdateDailyStats(
    String uid,
    NutritionEntry entry,
  ) async {
    final todayKey = _todayKey();
    final nutritionRef = _col(uid).doc();
    final dailyStatsRef = _db
        .collection('users')
        .doc(uid)
        .collection('dailyStats')
        .doc(todayKey);

    final batch = _db.batch();
    batch.set(nutritionRef, <String, dynamic>{
      ...entry.toMap(),
      'id': nutritionRef.id,
    });
    batch.set(dailyStatsRef, <String, dynamic>{
      'calories': FieldValue.increment(entry.calories),
      'waterLiters': FieldValue.increment(entry.waterLiters),
      'updatedAt': FieldValue.serverTimestamp(),
      'date': todayKey,
      'recentActivities': FieldValue.arrayUnion([_nutritionSummary(entry)]),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> deleteNutritionAndUpdateDailyStats(
    String uid,
    NutritionEntry entry,
  ) async {
    final dayKey = _dateKey(entry.createdAt);
    final nutritionRef = _col(uid).doc(entry.id);
    final dailyStatsRef = _db
        .collection('users')
        .doc(uid)
        .collection('dailyStats')
        .doc(dayKey);

    await nutritionRef.delete();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(dailyStatsRef);
      if (!snap.exists) {
        return;
      }

      final data = snap.data() ?? <String, dynamic>{};
      final currentCalories = ((data['calories'] ?? 0) as num).toInt();
      final currentWater = ((data['waterLiters'] ?? 0) as num).toDouble();

      final newCalories = (currentCalories - entry.calories).clamp(0, 1 << 31);
      final newWater = (currentWater - entry.waterLiters);

      tx.set(dailyStatsRef, <String, dynamic>{
        'calories': newCalories,
        'waterLiters': newWater < 0 ? 0 : newWater,
        'updatedAt': FieldValue.serverTimestamp(),
        'recentActivities': FieldValue.arrayRemove([_nutritionSummary(entry)]),
      }, SetOptions(merge: true));
    });
  }
}
