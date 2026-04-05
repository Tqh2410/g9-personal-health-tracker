import 'package:cloud_firestore/cloud_firestore.dart';

class VitalEntry {
  final String id;
  final double weightKg;
  final int heartRate;
  final DateTime createdAt;

  const VitalEntry({
    required this.id,
    required this.weightKg,
    required this.heartRate,
    required this.createdAt,
  });

  factory VitalEntry.fromMap(String id, Map<String, dynamic> map) {
    return VitalEntry(
      id: id,
      weightKg: ((map['weightKg'] ?? 0) as num).toDouble(),
      heartRate: ((map['heartRate'] ?? 0) as num).toInt(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'weightKg': weightKg,
      'heartRate': heartRate,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
