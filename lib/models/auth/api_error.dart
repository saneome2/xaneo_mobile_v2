/// Ошибка API
class ApiError implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, dynamic>? details;

  const ApiError({
    required this.message,
    this.statusCode,
    this.code,
    this.details,
  });

  factory ApiError.fromJson(Map<String, dynamic> json, {int? statusCode}) {
    // Обработка разных форматов ошибок от Django
    String message = 'Произошла ошибка';
    String? code;
    Map<String, dynamic>? details;

    if (json['detail'] != null) {
      message = json['detail'] as String;
    } else if (json['message'] != null) {
      message = json['message'] as String;
    } else if (json['error'] != null) {
      if (json['error'] is String) {
        message = json['error'] as String;
      } else if (json['error'] is Map) {
        final errorMap = json['error'] as Map<String, dynamic>;
        message = errorMap['message'] as String? ?? 'Произошла ошибка';
        code = errorMap['code'] as String?;
      }
    }

    // Обработка ошибок валидации (field errors)
    if (json['errors'] != null) {
      details = json['errors'] as Map<String, dynamic>;
      final errorValues = details.values;
      if (errorValues.isNotEmpty) {
        final firstError = errorValues.first;
        if (firstError is List && firstError.isNotEmpty) {
          message = firstError.first.toString();
        } else if (firstError is String) {
          message = firstError;
        }
      }
    }

    // Обработка ошибок полей напрямую (username: ["error"], email: ["error"])
    final fieldErrors = <String, dynamic>{};
    for (final entry in json.entries) {
      if (entry.key != 'detail' && 
          entry.key != 'message' && 
          entry.key != 'error' && 
          entry.key != 'code' &&
          entry.key != 'errors') {
        fieldErrors[entry.key] = entry.value;
      }
    }
    if (fieldErrors.isNotEmpty) {
      details = fieldErrors;
      final firstField = fieldErrors.values.first;
      if (firstField is List && firstField.isNotEmpty) {
        message = firstField.first.toString();
      }
    }

    return ApiError(
      message: message,
      statusCode: statusCode,
      code: code ?? json['code'] as String?,
      details: details,
    );
  }

  /// Проверяет, является ли ошибка ошибкой сети
  bool get isNetworkError => statusCode == null;

  /// Проверяет, является ли ошибка ошибкой авторизации
  bool get isAuthError => statusCode == 401;

  /// Проверяет, является ли ошибка ошибкой доступа
  bool get isForbiddenError => statusCode == 403;

  /// Проверяет, является ли ошибка ошибкой "не найдено"
  bool get isNotFoundError => statusCode == 404;

  /// Проверяет, является ли ошибка ошибкой валидации
  bool get isValidationError => statusCode == 400;

  /// Проверяет, является ли ошибка ошибкой rate limit
  bool get isRateLimitError => statusCode == 429;

  /// Проверяет, является ли ошибка ошибкой сервера
  bool get isServerError => statusCode != null && statusCode! >= 500;

  @override
  String toString() {
    if (statusCode != null) {
      return 'ApiError($statusCode): $message';
    }
    return 'ApiError: $message';
  }
}

/// Ошибка сети
class NetworkError extends ApiError {
  const NetworkError({String? message}) 
      : super(message: message ?? 'Ошибка сети. Проверьте подключение.');
}

/// Ошибка таймаута
class TimeoutError extends ApiError {
  const TimeoutError({String? message}) 
      : super(message: message ?? 'Превышено время ожидания.');
}

/// Ошибка отмены запроса
class CancelError extends ApiError {
  const CancelError() : super(message: 'Запрос отменён');
}

/// Ошибка rate limit
class RateLimitError extends ApiError {
  final Duration? retryAfter;

  const RateLimitError({
    String? message,
    this.retryAfter,
  }) : super(
    message: message ?? 'Слишком много попыток. Попробуйте позже.',
    statusCode: 429,
  );
}
