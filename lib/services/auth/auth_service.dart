import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../config/app_config.dart';
import '../../models/auth/api_error.dart';
import '../../models/auth/auth_response.dart';
import '../../models/auth/recent_account.dart';
import '../../models/auth/user_model.dart';
import 'token_storage.dart';
import '../api/api_client.dart';

/// Сервис авторизации
///
/// Отвечает за:
/// - Вход в систему (с поддержкой 2FA)
/// - Регистрацию
/// - Проверку доступности username/email
/// - Отправку и проверку кодов верификации
/// - Обновление токенов
/// - Выход из системы
class AuthService {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  AuthService({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
  }) : _apiClient = apiClient, _tokenStorage = tokenStorage;

  /// Вход в систему через mobile-login API
  ///
  /// Возвращает MobileLoginResult:
  /// - Если у пользователя включен 2FA: requiresTfa = true, tempToken для верификации
  /// - Если вход успешен: isSuccess = true, userInfo содержит данные пользователя
  /// 
  /// ВАЖНО: mobile-login API НЕ возвращает JWT токены!
  /// Для получения токенов нужно использовать обычный login endpoint.
  Future<MobileLoginResult> mobileLogin({
    required String username,
    required String password,
  }) async {
    try {
      debugPrint('=== Mobile Login Request ===');
      debugPrint('Username: $username');
      
      final response = await _apiClient.post(
        AppConfig.authMobileLogin,
        data: {
          'username': username,
          'password': password,
        },
      );

      debugPrint('=== Mobile Login Response ===');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Data: ${response.data}');
      
      final mobileResponse = MobileLoginResponse.fromJson(response.data);
      
      debugPrint('Parsed response:');
      debugPrint('  authSuccess: ${mobileResponse.authSuccess}');
      debugPrint('  tfaRequired: ${mobileResponse.tfaRequired}');
      debugPrint('  requiresTfa: ${mobileResponse.requiresTfa}');
      debugPrint('  isSuccess: ${mobileResponse.isSuccess}');
      debugPrint('  userInfo: ${mobileResponse.userInfo}');
      debugPrint('  message: ${mobileResponse.message}');

      // Если требуется 2FA
      if (mobileResponse.requiresTfa) {
        debugPrint('=> 2FA Required');
        return MobileLoginResult.fromTfaRequired(mobileResponse);
      }

      // Если вход успешен (без 2FA)
      if (mobileResponse.isSuccess) {
        debugPrint('=> Login Success');
        // Сохраняем данные пользователя (без токенов)
        if (mobileResponse.userInfo != null) {
          await _tokenStorage.saveUserData(mobileResponse.userInfo!.toJson());
        }
        return MobileLoginResult.fromSuccess(mobileResponse);
      }

      // Ошибка авторизации
      debugPrint('=> Login Error: ${mobileResponse.message}');
      return MobileLoginResult.fromError(
        mobileResponse.message ?? 'Ошибка авторизации',
      );
    } on DioException catch (e) {
      debugPrint('=== Mobile Login DioException ===');
      debugPrint('Type: ${e.type}');
      debugPrint('Message: ${e.message}');
      debugPrint('Response: ${e.response?.data}');
      throw _handleDioError(e);
    }
  }

  /// Вход в систему через обычный login endpoint (возвращает JWT токены)
  ///
  /// Использовать только если mobile-login успешен и не требуется 2FA
  Future<AuthResponse> loginWithTokens({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.authLogin,
        data: {
          'username': username,
          'password': password,
        },
      );

      final authResponse = AuthResponse.fromJson(response.data);
      await _saveAuthData(authResponse);
      return authResponse;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Вход в систему (старый метод для совместимости)
  ///
  /// Возвращает LoginResult:
  /// - Если у пользователя включен 2FA: requiresTfa = true
  /// - Если вход успешен: isSuccess = true, authResponse содержит токены
  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.authMobileLogin,
        data: {
          'username': username,
          'password': password,
        },
      );

      // Проверяем, требуется ли 2FA
      if (response.data['tfa_required'] == true) {
        return LoginResult.fromTfaRequired(
          TfaRequiredResponse.fromJson(response.data),
        );
      }

      // Успешный вход
      final authResponse = AuthResponse.fromJson(response.data);
      await _saveAuthData(authResponse);
      return LoginResult.fromAuthResponse(authResponse);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Подтверждение 2FA кода
  Future<AuthResponse> verifyTfaCode({
    required String tfaCodeId,
    required String code,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.authVerifyTfaCode,
        data: {
          'tfa_code_id': tfaCodeId,
          'code': code,
        },
      );

      final authResponse = AuthResponse.fromJson(response.data);
      await _saveAuthData(authResponse);
      return authResponse;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Регистрация нового пользователя (мобильный эндпоинт)
  ///
  /// Требует предварительной верификации email:
  /// 1. sendVerificationCode(email)
  /// 2. verifyEmailCode(email, code) - устанавливает флаг в сессии
  /// 3. register(...) - проверяет флаг в сессии
  ///
  /// Возвращает MobileRegisterResponse (без JWT токенов!)
  /// Для получения токенов нужно использовать loginWithTokens после регистрации.
  Future<MobileRegisterResponse> register({
    required String username,
    required String email,
    required String password,
    required String passwordConfirm,
    String? birthDate,
    String? realname,
    bool dataProcessingConsent = true,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.authMobileRegister,
        data: {
          'username': username,
          'email': email,
          'password': password,
          'password_confirm': passwordConfirm,
          'birth_date': birthDate,
          'data_processing_consent': dataProcessingConsent,
          if (realname != null) 'first_name': realname,
        },
      );

      final registerResponse = MobileRegisterResponse.fromJson(response.data);
      
      // Сохраняем данные пользователя
      if (registerResponse.success && registerResponse.userId != null) {
        await _tokenStorage.saveUserData({
          'id': registerResponse.userId,
          'username': registerResponse.username,
          'email': registerResponse.email,
          'first_name': registerResponse.firstName,
          'has_avatar': registerResponse.hasAvatar,
        });
      }
      
      return registerResponse;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Проверка доступности username
  Future<AvailabilityResponse> checkUsername(String username) async {
    try {
      final response = await _apiClient.get(
        AppConfig.authCheckUsername,
        queryParameters: {'username': username},
      );
      return AvailabilityResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Проверка доступности email
  Future<AvailabilityResponse> checkEmail(String email) async {
    try {
      final response = await _apiClient.get(
        AppConfig.authCheckEmail,
        queryParameters: {'email': email},
      );
      return AvailabilityResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Отправка кода верификации на email
  Future<VerificationCodeResponse> sendVerificationCode(String email, {String? username}) async {
    try {
      final data = <String, dynamic>{'email': email};
      if (username != null) {
        data['username'] = username;
      }
      final response = await _apiClient.post(
        AppConfig.authSendVerificationCode,
        data: data,
      );
      return VerificationCodeResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Проверка кода верификации email
  /// 
  /// После успешной проверки устанавливается флаг в сессии
  Future<VerifyCodeResponse> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.authVerifyEmailCode,
        data: {
          'email': email,
          'code': code,
        },
      );
      return VerifyCodeResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Обновление токена
  Future<bool> refreshToken() async {
    try {
      final newToken = await _apiClient.refreshToken();
      return newToken != null;
    } catch (_) {
      return false;
    }
  }

  /// Проверка авторизации
  Future<bool> isAuthenticated() async {
    return await _tokenStorage.isAuthenticated();
  }

  /// Получение текущего пользователя
  Future<UserModel?> getCurrentUser() async {
    final userData = await _tokenStorage.getUserData();
    if (userData == null) return null;
    
    try {
      return UserModel.fromJson(userData);
    } catch (_) {
      return null;
    }
  }

  /// Выход из системы
  Future<void> logout() async {
    await _tokenStorage.clearAll();
    _apiClient.clearAuth();
  }

  /// Сохранение данных авторизации
  Future<void> _saveAuthData(AuthResponse authResponse) async {
    await _tokenStorage.saveAccessToken(authResponse.accessToken);
    await _tokenStorage.saveRefreshToken(authResponse.refreshToken);
    await _tokenStorage.saveUserData(authResponse.user.toJson());
  }

  /// Обработка ошибок Dio
  ApiError _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const TimeoutError();

      case DioExceptionType.connectionError:
        return const NetworkError();

      case DioExceptionType.cancel:
        return const CancelError();

      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final data = e.response?.data;

        // Rate limit
        if (statusCode == 429) {
          final retryAfter = e.response?.headers.value('Retry-After');
          return RateLimitError(
            retryAfter: retryAfter != null
                ? Duration(seconds: int.parse(retryAfter))
                : null,
          );
        }

        // Парсим ошибку из ответа
        if (data is Map<String, dynamic>) {
          return ApiError.fromJson(data, statusCode: statusCode);
        }

        return ApiError(
          message: 'Ошибка сервера',
          statusCode: statusCode,
        );

      default:
        return ApiError(message: e.message ?? 'Неизвестная ошибка');
    }
  }

  // ==================== Недавние аккаунты ====================

  /// Получение недавних аккаунтов для устройства
  /// 
  /// Возвращает список аккаунтов, в которые ранее входили на этом устройстве
  Future<RecentAccountsResponse> getRecentAccounts() async {
    try {
      final response = await _apiClient.get(AppConfig.authRecentAccounts);
      return RecentAccountsResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Быстрый вход в аккаунт
  /// 
  /// Проверяет, входил ли пользователь с этого устройства ранее.
  /// Если да - позволяет войти без пароля.
  /// 
  /// Параметры:
  /// - userId: ID пользователя для быстрого входа
  /// - tfaCode: код 2FA (если включен)
  /// 
  /// Возвращает QuickLoginResponse:
  /// - success: true если вход успешен
  /// - requiresTfa: true если требуется код 2FA
  /// - userInfo: данные пользователя
  Future<QuickLoginResponse> quickLogin({
    required int userId,
    String? tfaCode,
  }) async {
    try {
      final data = <String, dynamic>{
        'user_id': userId,
        if (tfaCode != null) 'tfa_code': tfaCode,
      };

      final response = await _apiClient.post(
        AppConfig.authQuickLogin,
        data: data,
      );

      final quickLoginResponse = QuickLoginResponse.fromJson(response.data);

      // Если вход успешен, сохраняем данные пользователя
      if (quickLoginResponse.success && quickLoginResponse.userInfo != null) {
        await _tokenStorage.saveUserData({
          'id': quickLoginResponse.userInfo!.id,
          'username': quickLoginResponse.userInfo!.username,
          'email': quickLoginResponse.userInfo!.email,
          'first_name': quickLoginResponse.userInfo!.firstName,
          'is_verified': quickLoginResponse.userInfo!.isVerified,
          'tfa_enabled': quickLoginResponse.userInfo!.tfaEnabled,
          'has_avatar': quickLoginResponse.userInfo!.hasAvatar,
          if (quickLoginResponse.userInfo!.avatarUrl != null)
            'avatar': quickLoginResponse.userInfo!.avatarUrl,
        });
      }

      return quickLoginResponse;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Быстрый вход с получением JWT токенов
  /// 
  /// После успешного quickLogin нужно вызвать этот метод для получения токенов.
  /// Использует обычный login endpoint с сохранёнными credentials.
  /// 
  /// ВНИМАНИЕ: Этот метод не должен использоваться напрямую!
  /// Быстрый вход не требует пароля, поэтому токены выдаются сервером
  /// в ответе quickLogin если вход успешен.
  Future<AuthResponse?> getTokensAfterQuickLogin({
    required int userId,
    required String deviceToken,
  }) async {
    try {
      final response = await _apiClient.post(
        AppConfig.authQuickLogin,
        data: {
          'user_id': userId,
          'device_token': deviceToken,
          'get_tokens': true,
        },
      );

      // Если сервер вернул токены
      if (response.data['access'] != null && response.data['refresh'] != null) {
        final authResponse = AuthResponse.fromJson(response.data);
        await _saveAuthData(authResponse);
        return authResponse;
      }

      return null;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }
}
