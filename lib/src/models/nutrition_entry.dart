import 'package:cloud_firestore/cloud_firestore.dart';

class NutritionEntry {
  final String id;
  final String mealType;
  final String food;
  final int calories;
  final double waterLiters;
  final String? imageUrl;
  final DateTime createdAt;

  const NutritionEntry({
    required this.id,
    required this.mealType,
    required this.food,
    required this.calories,
    required this.waterLiters,
    required this.createdAt,
    this.imageUrl,
  });

  factory NutritionEntry.fromMap(String id, Map<String, dynamic> map) {
    return NutritionEntry(
      id: id,
      mealType: (map['mealType'] ?? '') as String,
      food: (map['food'] ?? '') as String,
      calories: ((map['calories'] ?? 0) as num).toInt(),
      waterLiters: ((map['waterLiters'] ?? 0) as num).toDouble(),
      imageUrl: map['imageUrl'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mealType': mealType,
      'food': food,
      'calories': calories,
      'waterLiters': waterLiters,
      'imageUrl': imageUrl,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
