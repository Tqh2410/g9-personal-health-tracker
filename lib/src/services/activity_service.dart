import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/activity_entry.dart';

class ActivityService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) {
    return _db.collection('users').doc(uid).collection('activities');
  }

  Stream<List<ActivityEntry>> watchActivities(String uid) {
    return _col(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => ActivityEntry.fromMap(d.id, d.data()))
              .toList(growable: false),
        );
  }

  Future<void> addActivity(String uid, ActivityEntry entry) async {
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

  String _activitySummary(ActivityEntry entry) {
    return '${entry.type}: ${entry.durationMinutes} phút, ${entry.distanceKm.toStringAsFixed(2)} km, ${entry.calories} kcal';
  }

  Future<void> addActivityAndUpdateDailyStats(
    String uid,
    ActivityEntry entry,
  ) async {
    final todayKey = _todayKey();
    final activityRef = _col(uid).doc();
    final dailyStatsRef = _db
        .collection('users')
        .doc(uid)
        .collection('dailyStats')
        .doc(todayKey);

    final batch = _db.batch();
    batch.set(activityRef, <String, dynamic>{
      ...entry.toMap(),
      'id': activityRef.id,
    });
    batch.set(dailyStatsRef, <String, dynamic>{
      'calories': FieldValue.increment(entry.calories),
      'updatedAt': FieldValue.serverTimestamp(),
      'date': todayKey,
      'recentActivities': FieldValue.arrayUnion([
        '${entry.type}: ${entry.durationMinutes} phút, ${entry.distanceKm.toStringAsFixed(2)} km, ${entry.calories} kcal',
      ]),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> deleteActivity(String uid, String id) async {
    await _col(uid).doc(id).delete();
  }

  Future<void> deleteActivityAndUpdateDailyStats(
    String uid,
    ActivityEntry entry,
  ) async {
    final dayKey = _dateKey(entry.createdAt);
    final activityRef = _col(uid).doc(entry.id);
    final dailyStatsRef = _db
        .collection('users')
        .doc(uid)
        .collection('dailyStats')
        .doc(dayKey);

    await activityRef.delete();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(dailyStatsRef);
      if (!snap.exists) {
        return;
      }

      final data = snap.data() ?? <String, dynamic>{};
      final currentCalories = ((data['calories'] ?? 0) as num).toInt();
      final newCalories = (currentCalories - entry.calories).clamp(0, 1 << 31);

      tx.set(dailyStatsRef, <String, dynamic>{
        'calories': newCalories,
        'updatedAt': FieldValue.serverTimestamp(),
        'recentActivities': FieldValue.arrayRemove([_activitySummary(entry)]),
      }, SetOptions(merge: true));
    });
  }
}
