import 'package:firebase_auth/firebase_auth.dart';

class AuthException implements Exception {
  final String message;
  final String? code;

  AuthException({required this.message, this.code});

  factory AuthException.fromFirebaseException(Object exception) {
    if (exception is FirebaseAuthException) {
      return AuthException(
        message: _getErrorMessage(exception.code),
        code: exception.code,
      );
    }
    return AuthException(
      message: 'An unexpected error occurred',
      code: 'unknown_error',
    );
  }

  static String _getErrorMessage(String code) {
    switch (code) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account with that email already exists.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'operation-not-allowed':
        return 'Operation is not allowed.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-credential':
        return 'Invalid credentials. Please try again.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'An error occurred: $code';
    }
  }

  @override
  String toString() => 'AuthException: $message';
}
