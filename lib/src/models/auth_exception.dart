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
      message: 'Đã xảy ra sự cố xác thực. Vui lòng thử lại sau.',
      code: 'unknown_error',
    );
  }

  static String _getErrorMessage(String code) {
    switch (code) {
      case 'weak-password':
        return 'Mật khẩu quá yếu. Vui lòng chọn mật khẩu mạnh hơn.';
      case 'email-already-in-use':
        return 'Email này đã được sử dụng. Vui lòng dùng email khác.';
      case 'invalid-email':
        return 'Email không hợp lệ. Vui lòng kiểm tra lại.';
      case 'operation-not-allowed':
        return 'Tính năng này hiện chưa được bật. Vui lòng thử lại sau.';
      case 'user-disabled':
        return 'Tài khoản này đã bị vô hiệu hóa. Vui lòng liên hệ hỗ trợ.';
      case 'user-not-found':
        return 'Không tìm thấy tài khoản với email này.';
      case 'wrong-password':
        return 'Mật khẩu chưa đúng. Vui lòng thử lại.';
      case 'invalid-credential':
        return 'Thông tin đăng nhập không hợp lệ. Vui lòng thử lại.';
      case 'network-request-failed':
        return 'Không thể kết nối mạng. Vui lòng kiểm tra Internet.';
      default:
        return 'Không thể xác thực lúc này. Vui lòng thử lại sau.';
    }
  }

  @override
  String toString() => 'AuthException: $message';
}
