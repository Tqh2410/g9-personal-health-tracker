import '../models/auth_exception.dart';

class UserFriendlyError {
  static String message(Object? error, {required String fallback}) {
    if (error == null) {
      return fallback;
    }
    if (error is AuthException) {
      return error.message;
    }
    if (error is String && error.trim().isNotEmpty) {
      return error;
    }
    return fallback;
  }
}
