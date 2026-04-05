import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityEntry {
  final String id;
  final String type;
  final int durationMinutes;
  final int calories;
  final double distanceKm;
  final DateTime createdAt;

  const ActivityEntry({
    required this.id,
    required this.type,
    required this.durationMinutes,
    required this.calories,
    required this.distanceKm,
    required this.createdAt,
  });

  factory ActivityEntry.fromMap(String id, Map<String, dynamic> map) {
    return ActivityEntry(
      id: id,
      type: (map['type'] ?? '') as String,
      durationMinutes: ((map['durationMinutes'] ?? 0) as num).toInt(),
      calories: ((map['calories'] ?? 0) as num).toInt(),
      distanceKm: ((map['distanceKm'] ?? 0) as num).toDouble(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'durationMinutes': durationMinutes,
      'calories': calories,
      'distanceKm': distanceKm,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
