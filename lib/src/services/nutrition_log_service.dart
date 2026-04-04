import '../models/nutrition_entry.dart';
import 'nutrition_service.dart';

class NutritionLogService {
  final NutritionService _nutritionService = NutritionService();

  Future<void> saveRecognizedFood({
    required String uid,
    required String foodName,
    required int calories,
    String? imageUrl,
    String mealType = 'lunch',
  }) async {
    final entry = NutritionEntry(
      id: '',
      mealType: mealType,
      food: foodName,
      calories: calories,
      waterLiters: 0,
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
    );

    await _nutritionService.addNutritionAndUpdateDailyStats(uid, entry);
  }
}
