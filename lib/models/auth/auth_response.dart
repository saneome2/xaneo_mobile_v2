import 'user_model.dart';

/// Ответ на успешную авторизацию (обычный login endpoint)
class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final UserModel user;

  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['access'] as String,
      refreshToken: json['refresh'] as String,
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access': accessToken,
      'refresh': refreshToken,
      'user': user.toJson(),
    };
  }
}

/// Ответ на mobile-login запрос
/// 
/// Mobile-login API возвращает другую структуру:
/// - auth_success: true/false
/// - user_info: информация о пользователе
/// - tfa_required: true/false (если требуется 2FA)
/// - token: временный токен для 2FA
class MobileLoginResponse {
  final bool authSuccess;
  final String? message;
  final UserModel? userInfo;
  final bool? tfaRequired;
  final String? tempToken; // Для 2FA верификации

  const MobileLoginResponse({
    required this.authSuccess,
    this.message,
    this.userInfo,
    this.tfaRequired,
    this.tempToken,
  });

  factory MobileLoginResponse.fromJson(Map<String, dynamic> json) {
    // Парсим user_info если есть
    UserModel? user;
    if (json['user_info'] != null) {
      user = UserModel.fromUserInfoJson(json['user_info'] as Map<String, dynamic>);
    }

    return MobileLoginResponse(
      authSuccess: json['auth_success'] as bool? ?? false,
      message: json['message'] as String?,
      userInfo: user,
      tfaRequired: json['tfa_required'] as bool?,
      tempToken: json['token'] as String?,
    );
  }

  /// Требуется ли 2FA
  bool get requiresTfa => tfaRequired == true;

  /// Успешный ли вход (без 2FA)
  bool get isSuccess => authSuccess && !requiresTfa;
}

/// Ответ на запрос проверки username/email
class AvailabilityResponse {
  final bool available;
  final String? message;

  const AvailabilityResponse({
    required this.available,
    this.message,
  });

  factory AvailabilityResponse.fromJson(Map<String, dynamic> json) {
    return AvailabilityResponse(
      available: json['available'] as bool? ?? false,
      message: json['message'] as String?,
    );
  }
}

/// Ответ на отправку кода верификации
class VerificationCodeResponse {
  final bool success;
  final String? message;
  final int? expiresIn;

  const VerificationCodeResponse({
    required this.success,
    this.message,
    this.expiresIn,
  });

  factory VerificationCodeResponse.fromJson(Map<String, dynamic> json) {
    return VerificationCodeResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      expiresIn: json['expires_in'] as int?,
    );
  }
}

/// Ответ на проверку кода верификации
class VerifyCodeResponse {
final bool success;
final String? message;

const VerifyCodeResponse({
required this.success,
this.message,
});

factory VerifyCodeResponse.fromJson(Map<String, dynamic> json) {
return VerifyCodeResponse(
// API возвращает 'verified' или 'success'
success: (json['verified'] as bool? ?? json['success'] as bool? ?? false),
message: json['message'] as String?,
);
}
}

/// Ответ при необходимости 2FA
class TfaRequiredResponse {
  final bool tfaRequired;
  final String? message;
  final String? tfaCodeId;

  const TfaRequiredResponse({
    required this.tfaRequired,
    this.message,
    this.tfaCodeId,
  });

  factory TfaRequiredResponse.fromJson(Map<String, dynamic> json) {
    return TfaRequiredResponse(
      tfaRequired: json['tfa_required'] as bool? ?? false,
      message: json['message'] as String?,
      tfaCodeId: json['tfa_code_id'] as String?,
    );
  }
}

/// Результат входа (может быть либо успешный вход, либо требование 2FA)
class LoginResult {
  final AuthResponse? authResponse;
  final TfaRequiredResponse? tfaRequired;

  const LoginResult({
    this.authResponse,
    this.tfaRequired,
  });

  bool get requiresTfa => tfaRequired != null && tfaRequired!.tfaRequired;
  bool get isSuccess => authResponse != null;

  factory LoginResult.fromAuthResponse(AuthResponse response) {
    return LoginResult(authResponse: response);
  }

  factory LoginResult.fromTfaRequired(TfaRequiredResponse response) {
    return LoginResult(tfaRequired: response);
  }
}

/// Результат mobile-login запроса
///
/// Может быть:
/// - Успешный вход (без 2FA) - isSuccess = true
/// - Требуется 2FA - requiresTfa = true, tempToken для верификации
/// - Ошибка - isError = true
class MobileLoginResult {
  final MobileLoginResponse? response;
  final String? errorMessage;
  final bool isSuccess;
  final bool requiresTfa;
  final bool isError;

  const MobileLoginResult._({
    this.response,
    this.errorMessage,
    this.isSuccess = false,
    this.requiresTfa = false,
    this.isError = false,
  });

  /// Успешный вход (без 2FA)
  factory MobileLoginResult.fromSuccess(MobileLoginResponse response) {
    return MobileLoginResult._(
      response: response,
      isSuccess: true,
    );
  }

  /// Требуется 2FA
  factory MobileLoginResult.fromTfaRequired(MobileLoginResponse response) {
    return MobileLoginResult._(
      response: response,
      requiresTfa: true,
    );
  }

  /// Ошибка
  factory MobileLoginResult.fromError(String message) {
    return MobileLoginResult._(
      errorMessage: message,
      isError: true,
    );
  }

  /// Временный токен для 2FA верификации
  String? get tempToken => response?.tempToken;

  /// Информация о пользователе
  UserModel? get userInfo => response?.userInfo;

  /// Сообщение от сервера
  String? get message => response?.message ?? errorMessage;
}

/// Ответ на мобильную регистрацию (mobile-register endpoint)
///
/// Возвращает:
/// - success: true/false
/// - message: сообщение с результатом
/// - user_id: ID созданного пользователя
/// - username: имя пользователя
/// - email: email пользователя
/// - first_name: реальное имя
/// - has_avatar: есть ли аватар
class MobileRegisterResponse {
  final bool success;
  final String? message;
  final int? userId;
  final String? username;
  final String? email;
  final String? firstName;
  final bool? hasAvatar;
  final String? timestamp;

  const MobileRegisterResponse({
    required this.success,
    this.message,
    this.userId,
    this.username,
    this.email,
    this.firstName,
    this.hasAvatar,
    this.timestamp,
  });

  factory MobileRegisterResponse.fromJson(Map<String, dynamic> json) {
    return MobileRegisterResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      userId: json['user_id'] as int?,
      username: json['username'] as String?,
      email: json['email'] as String?,
      firstName: json['first_name'] as String?,
      hasAvatar: json['has_avatar'] as bool?,
      timestamp: json['timestamp'] as String?,
    );
  }

  /// Сообщение об ошибке (если есть)
  String? get errorMessage => success ? null : message;
}

/// Ответ на быстрый вход (quick-login endpoint)
///
/// Возвращает:
/// - success: true/false
/// - requires_2fa: true/false (если требуется 2FA)
/// - message: сообщение с результатом
/// - user_info: информация о пользователе
/// - error: код ошибки
/// - code: код ошибки
class QuickLoginResponse {
  final bool success;
  final bool? requires2fa;
  final String? message;
  final QuickLoginUserInfo? userInfo;
  final String? error;
  final String? code;

  const QuickLoginResponse({
    required this.success,
    this.requires2fa,
    this.message,
    this.userInfo,
    this.error,
    this.code,
  });

  factory QuickLoginResponse.fromJson(Map<String, dynamic> json) {
    return QuickLoginResponse(
      success: json['success'] as bool? ?? false,
      requires2fa: json['requires_2fa'] as bool?,
      message: json['message'] as String?,
      userInfo: json['user_info'] != null
          ? QuickLoginUserInfo.fromJson(json['user_info'] as Map<String, dynamic>)
          : null,
      error: json['error'] as String?,
      code: json['code'] as String?,
    );
  }

  /// Требуется ли 2FA
  bool get requiresTfa => requires2fa == true;

  /// Сообщение об ошибке
  String? get errorMessage => error ?? (success ? null : message);
}

/// Информация о пользователе для быстрого входа
class QuickLoginUserInfo {
  final int? id;
  final String? username;
  final String? email;
  final String? firstName;
  final bool? isVerified;
  final bool? tfaEnabled;
  final bool? hasAvatar;
  final String? avatarUrl;

  const QuickLoginUserInfo({
    this.id,
    this.username,
    this.email,
    this.firstName,
    this.isVerified,
    this.tfaEnabled,
    this.hasAvatar,
    this.avatarUrl,
  });

  factory QuickLoginUserInfo.fromJson(Map<String, dynamic> json) {
    return QuickLoginUserInfo(
      id: json['id'] as int?,
      username: json['username'] as String?,
      email: json['email'] as String?,
      firstName: json['first_name'] as String?,
      isVerified: json['is_verified'] as bool?,
      tfaEnabled: json['tfa_enabled'] as bool?,
      hasAvatar: json['has_avatar'] as bool?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
