class FoodRecognitionResult {
  final String foodName;
  final int estimatedCalories;
  final String? notes;

  const FoodRecognitionResult({
    required this.foodName,
    required this.estimatedCalories,
    this.notes,
  });

  factory FoodRecognitionResult.fromMap(Map<String, dynamic> map) {
    final caloriesValue = map['estimatedCalories'];
    return FoodRecognitionResult(
      foodName: (map['foodName'] ?? 'Unknown food') as String,
      estimatedCalories: caloriesValue is num
          ? caloriesValue.toInt()
          : int.tryParse(caloriesValue?.toString() ?? '') ?? 0,
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'foodName': foodName,
    'estimatedCalories': estimatedCalories,
    'notes': notes,
  };
}
