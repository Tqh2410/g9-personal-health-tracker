import 'dart:typed_data';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/food_recognition_result.dart';

class CloudflareAiService {
  static const String _accountId = String.fromEnvironment(
    'CLOUDFLARE_ACCOUNT_ID',
  );
  static const String _apiToken = String.fromEnvironment(
    'CLOUDFLARE_API_TOKEN',
  );
  static const String _endpoint = String.fromEnvironment(
    'CLOUDFLARE_AI_ENDPOINT',
  );
  static const String _modelName = String.fromEnvironment(
    'CLOUDFLARE_AI_MODEL',
    defaultValue: '@cf/llava-hf/llava-1.5-7b-hf',
  );

  static const Duration _timeout = Duration(seconds: 60);
  static const String _visionPrompt =
      'Identify the main dish in this food image and estimate calories. '
      'Return ONLY valid JSON (no markdown, no extra text) with keys: '
      'foodName, estimatedCalories, notes. '
      'foodName: natural dish name (English or Vietnamese). '
      'estimatedCalories: integer kcal estimate. '
      'notes: one short, practical sentence.';

  Uri _resolveUri() {
    final customEndpoint = _endpoint.trim();
    if (customEndpoint.isNotEmpty) {
      return Uri.parse(customEndpoint);
    }

    if (_accountId.trim().isEmpty || _apiToken.trim().isEmpty) {
      throw StateError(
        'Chua cau hinh Cloudflare Workers AI. Hay dien Account ID va API Token trong env/cloudflare.local.json, sau do chay profile Flutter (Workers AI).',
      );
    }

    return Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/${_accountId.trim()}/ai/run/$_modelName',
    );
  }

  Map<String, String> _headersJson() {
    final headers = <String, String>{'Content-Type': 'application/json'};

    final token = _apiToken.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  Map<String, dynamic> _buildVisionPayload(Uint8List imageBytes) {
    return {
      'prompt': _visionPrompt,
      'image': imageBytes.toList(),
      'max_tokens': 400,
      'temperature': 0.2,
    };
  }

  int _extractCaloriesFromText(String text) {
    final matches = RegExp(
      r'(\d{2,4})\s*(kcal|calo|cal)',
      caseSensitive: false,
    ).allMatches(text);
    if (matches.isEmpty) {
      return 0;
    }

    final value = int.tryParse(matches.first.group(1) ?? '');
    return value ?? 0;
  }

  String _pickFirstNonEmptyString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  Map<String, dynamic> _normalizeResultMap(Map<String, dynamic> map) {
    var foodName = _pickFirstNonEmptyString(map, [
      'foodName',
      'food',
      'dish',
      'name',
      'tenMon',
    ]);

    final caloriesRaw =
        map['estimatedCalories'] ?? map['calories'] ?? map['kcal'];
    final calories = caloriesRaw is num
        ? caloriesRaw.toInt()
        : int.tryParse(caloriesRaw?.toString() ?? '') ?? 0;

    var notes = _pickFirstNonEmptyString(map, [
      'notes',
      'note',
      'description',
      'moTa',
      'reasoning',
    ]);

    final lowerFoodName = foodName.toLowerCase();
    if (lowerFoodName.contains('ten mon') ||
        lowerFoodName.contains('food name') ||
        lowerFoodName.contains('dish name')) {
      foodName = '';
    }

    final lowerNotes = notes.toLowerCase();
    if (lowerNotes.contains('1 cau ngan') ||
        lowerNotes.contains('one short sentence') ||
        lowerNotes.contains('bang tieng viet')) {
      notes = '';
    }

    return {
      'foodName': foodName.isEmpty ? 'Mon an chua xac dinh' : foodName,
      'estimatedCalories': calories,
      'notes': notes.isEmpty
          ? 'Ket qua la uoc tinh tu anh, gia tri kcal co the thay doi theo khau phan.'
          : notes,
    };
  }

  Map<String, dynamic> _buildFallbackResultFromText(String rawResponse) {
    final cleaned = rawResponse.trim();
    var firstLine = cleaned
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere(
          (line) => line.isNotEmpty,
          orElse: () => 'Mon an chua xac dinh',
        );

    final lowerFirstLine = firstLine.toLowerCase();
    if (lowerFirstLine.contains('ten mon') ||
        lowerFirstLine.contains('food name') ||
        lowerFirstLine.contains('dish name')) {
      firstLine = 'Mon an chua xac dinh';
    }

    return {
      'foodName': firstLine,
      'estimatedCalories': _extractCaloriesFromText(cleaned),
      'notes': cleaned.isEmpty
          ? 'AI khong tra ve mo ta chi tiet. Hay thu anh ro hon.'
          : cleaned,
    };
  }

  String _extractResponseText(dynamic result) {
    if (result is Map<String, dynamic>) {
      final response = result['response'];
      if (response is String) return response;
      if (response != null) return response.toString();

      final description = result['description'];
      if (description is String) return description;
      if (description != null) return description.toString();
    }
    if (result is String) return result;
    return result?.toString() ?? '';
  }

  Map<String, dynamic> _parseJsonPayload(String rawResponse) {
    final cleaned = rawResponse
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start >= 0 && end > start) {
        final jsonSlice = cleaned.substring(start, end + 1);
        return jsonDecode(jsonSlice) as Map<String, dynamic>;
      }

      throw FormatException('Workers AI did not return valid JSON.', cleaned);
    }
  }

  Future<FoodRecognitionResult> estimateFoodFromImageBytes(
    Uint8List imageBytes,
  ) async {
    final url = _resolveUri();

    final response = await http
        .post(
          url,
          headers: _headersJson(),
          body: jsonEncode(_buildVisionPayload(imageBytes)),
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Cloudflare AI request failed: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final result = decoded['result'];
    final rawResponse = _extractResponseText(result);
    if (rawResponse.trim().isEmpty) {
      throw Exception('Khong nhan duoc phan hoi tu Workers AI.');
    }

    Map<String, dynamic> parsed;
    try {
      parsed = _normalizeResultMap(_parseJsonPayload(rawResponse));
    } catch (_) {
      parsed = _buildFallbackResultFromText(rawResponse);
    }

    return FoodRecognitionResult.fromMap(parsed);
  }

  Future<String> generateDietAdvice({
    required int consumedCalories,
    required int activeCalories,
    required int tdee,
  }) async {
    final url = _resolveUri();
    final deficit = consumedCalories - (tdee + activeCalories);

    final response = await http.post(
      url,
      headers: _headersJson(),
      body: jsonEncode({
        'prompt':
            'Consumed: $consumedCalories kcal, active: $activeCalories kcal, TDEE: $tdee kcal, surplus/deficit: $deficit kcal. Give short diet and workout advice in Vietnamese.',
        'max_tokens': 250,
        'temperature': 0.4,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Cloudflare AI request failed: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = json['result'];
    if (result is Map<String, dynamic> && result['response'] is String) {
      return result['response'] as String;
    }

    return 'Khong lay duoc goi y AI.';
  }
}
