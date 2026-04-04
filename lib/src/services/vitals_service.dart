import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vital_entry.dart';

class VitalsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) {
    return _db.collection('users').doc(uid).collection('vitals');
  }

  Stream<List<VitalEntry>> watchVitals(String uid) {
    return _col(uid)
        .orderBy('createdAt', descending: false)
        .limit(30)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => VitalEntry.fromMap(d.id, d.data()))
              .toList(growable: false),
        );
  }

  Future<void> addVital(String uid, VitalEntry entry) async {
    await _col(uid).add(entry.toMap());
  }

  Future<void> deleteVital(String uid, String vitalId) async {
    await _col(uid).doc(vitalId).delete();
  }

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  Future<void> saveMeasuredHeartRate(String uid, int heartRate) async {
    final createdAt = DateTime.now();
    final todayKey = _todayKey();

    final userVitalRef = _db
        .collection('users')
        .doc(uid)
        .collection('vitals')
        .doc();
    final homeVitalRef = _db
        .collection('vitals')
        .doc(uid)
        .collection(todayKey)
        .doc();
    final dailyStatsRef = _db
        .collection('users')
        .doc(uid)
        .collection('dailyStats')
        .doc(todayKey);

    final entry = VitalEntry(
      id: userVitalRef.id,
      weightKg: 0,
      heartRate: heartRate,
      createdAt: createdAt,
    );

    final batch = _db.batch();
    batch.set(userVitalRef, entry.toMap());
    batch.set(homeVitalRef, <String, dynamic>{
      'heartRate': heartRate,
      'timestamp': Timestamp.fromDate(createdAt),
      'createdAt': Timestamp.fromDate(createdAt),
    });
    batch.set(dailyStatsRef, <String, dynamic>{
      'heartRate': heartRate,
      'updatedAt': FieldValue.serverTimestamp(),
      'date': todayKey,
    }, SetOptions(merge: true));

    await batch.commit();
  }
}
