class UserFriendlyError {
  static String message(Object error, {required String fallback}) {
    final raw = error.toString().trim();
    final lower = raw.toLowerCase();

    if (lower.contains('socketexception') ||
        lower.contains('network') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('failed host lookup')) {
      return 'Không thể kết nối mạng. Vui lòng kiểm tra Internet và thử lại.';
    }

    if (lower.contains('permission') ||
        lower.contains('denied') ||
        lower.contains('unauthorized')) {
      return 'Bạn chưa cấp quyền cần thiết. Vui lòng kiểm tra lại quyền trong cài đặt.';
    }

    if (lower.contains('null') ||
        lower.contains('typeerror') ||
        lower.contains('nosuchmethoderror') ||
        lower.contains('stack')) {
      return fallback;
    }

    final cleaned = raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('AuthException: ', '')
        .trim();

    if (cleaned.isEmpty || cleaned.toLowerCase() == 'null') {
      return fallback;
    }

    if (cleaned.length > 180) {
      return fallback;
    }

    return cleaned;
  }
}
