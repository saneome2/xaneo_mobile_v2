import 'package:flutter/foundation.dart';
import '../models/auth/user_model.dart';
import '../models/auth/auth_response.dart';
import '../models/auth/api_error.dart';
import '../models/auth/recent_account.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/recent_accounts_service.dart';
import '../services/auth/token_storage.dart';
import '../services/api/api_client.dart';

/// Состояние авторизации
enum AuthStatus {
  /// Начальное состояние, проверка не выполнена
  initial,

  /// Проверка авторизации в процессе
  checking,

  /// Пользователь не авторизован
  unauthenticated,

  /// Требуется 2FA
  tfaRequired,

  /// Пользователь авторизован
  authenticated,
}

/// Provider для управления состоянием авторизации
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final RecentAccountsService _recentAccountsService;

  AuthStatus _status = AuthStatus.initial;
  UserModel? _user;
  String? _tfaToken; // Временный токен для 2FA
  String? _pendingUsername; // Для повторного входа после 2FA
  String? _pendingPassword; // Для повторного входа после 2FA
  ApiError? _error;
  bool _isLoading = false;

  AuthProvider({
    required AuthService authService,
    required RecentAccountsService recentAccountsService,
  })  : _authService = authService,
        _recentAccountsService = recentAccountsService;

  // ========== Getters ==========

  AuthStatus get status => _status;
  UserModel? get user => _user;
  String? get tfaToken => _tfaToken;
  ApiError? get error => _error;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get requiresTfa => _status == AuthStatus.tfaRequired;

  // ========== Public Methods ==========

  /// Проверка авторизации при запуске приложения
  Future<void> checkAuthStatus() async {
    _status = AuthStatus.checking;
    notifyListeners();

    try {
      final isAuth = await _authService.isAuthenticated();
      if (isAuth) {
        _user = await _authService.getCurrentUser();
        _status = _user != null
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
    }

    notifyListeners();
  }

  /// Вход в систему через mobile-login API
  ///
  /// Возвращает:
  /// - true если вход успешен (без 2FA)
  /// - false если требуется 2FA или ошибка
  ///
  /// При успешном входе автоматически получает JWT токены
  Future<bool> login({
    required String username,
    required String password,
  }) async {
    debugPrint('=== AuthProvider.login() ===');
    _setLoading(true);
    _clearError();

    try {
      // Шаг 1: Проверяем credentials через mobile-login
      debugPrint('Step 1: Calling mobileLogin...');
      final result = await _authService.mobileLogin(
        username: username,
        password: password,
      );
      
      debugPrint('MobileLogin result:');
      debugPrint('  isSuccess: ${result.isSuccess}');
      debugPrint('  requiresTfa: ${result.requiresTfa}');
      debugPrint('  isError: ${result.isError}');
      debugPrint('  message: ${result.message}');

      // Если требуется 2FA
      if (result.requiresTfa) {
        debugPrint('=> Setting status to tfaRequired');
        _status = AuthStatus.tfaRequired;
        _tfaToken = result.tempToken;
        _pendingUsername = username;
        _pendingPassword = password;
        _user = result.userInfo;
        _setLoading(false);
        notifyListeners();
        return false;
      }

      // Если вход успешен (без 2FA) - получаем JWT токены
      if (result.isSuccess) {
        debugPrint('=> Getting JWT tokens...');
        // Получаем JWT токены через обычный login endpoint
        final authResponse = await _authService.loginWithTokens(
          username: username,
          password: password,
        );
        
        debugPrint('JWT tokens received:');
        debugPrint('  user: ${authResponse.user.username}');

        _user = authResponse.user;
        _status = AuthStatus.authenticated;

        // Сохраняем аккаунт в недавних
        await _saveRecentAccount(_user!);

        _setLoading(false);
        debugPrint('=> Setting status to authenticated, calling notifyListeners()');
        notifyListeners();
        return true;
      }

      // Ошибка авторизации
      debugPrint('=> Login failed: ${result.message}');
      _error = ApiError(message: result.message ?? 'Ошибка авторизации');
      _status = AuthStatus.unauthenticated;
      _setLoading(false);
      notifyListeners();
      return false;
    } on ApiError catch (e) {
      debugPrint('=> ApiError: ${e.message}');
      _error = e;
      _status = AuthStatus.unauthenticated;
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// Подтверждение 2FA кода
  /// 
  /// После успешной верификации получает JWT токены
  Future<bool> verifyTfaCode(String code) async {
    if (_tfaToken == null || _pendingUsername == null || _pendingPassword == null) {
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      // Шаг 1: Верифицируем 2FA код
      final authResponse = await _authService.verifyTfaCode(
        tfaCodeId: _tfaToken!,
        code: code,
      );

      // Шаг 2: Получаем JWT токены через обычный login
      final tokenResponse = await _authService.loginWithTokens(
        username: _pendingUsername!,
        password: _pendingPassword!,
      );

      _user = tokenResponse.user;
      _status = AuthStatus.authenticated;
      _tfaToken = null;
      _pendingUsername = null;
      _pendingPassword = null;
      _setLoading(false);
      notifyListeners();
      return true;
    } on ApiError catch (e) {
      _error = e;
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// Отмена процесса 2FA и очистка временных данных
  void cancelTfa() {
    _tfaToken = null;
    _pendingUsername = null;
    _pendingPassword = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Регистрация
  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required String passwordConfirm,
    String? birthDate,
    String? realname,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final registerResponse = await _authService.register(
        username: username,
        email: email,
        password: password,
        passwordConfirm: passwordConfirm,
        birthDate: birthDate,
        realname: realname,
      );

      if (registerResponse.success) {
        // Создаем UserModel из ответа регистрации
        _user = UserModel(
          id: registerResponse.userId ?? 0,
          username: registerResponse.username ?? '',
          email: registerResponse.email ?? '',
          emailVerified: true, // Email уже верифицирован
          createdAt: DateTime.now(),
        );
        _status = AuthStatus.authenticated;
        _setLoading(false);
        notifyListeners();
        return true;
      } else {
        _error = ApiError(message: registerResponse.message ?? 'Ошибка регистрации');
        _status = AuthStatus.unauthenticated;
        _setLoading(false);
        notifyListeners();
        return false;
      }
    } on ApiError catch (e) {
      _error = e;
      _status = AuthStatus.unauthenticated;
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// Выход из системы
  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    _tfaToken = null;
    _pendingUsername = null;
    _pendingPassword = null;
    _error = null;
    notifyListeners();
  }

  /// Очистка ошибки
  void clearError() {
    _clearError();
    notifyListeners();
  }

  /// Сброс состояния 2FA (для возврата к экрану входа)
  void resetTfaState() {
    _status = AuthStatus.unauthenticated;
    _tfaToken = null;
    _pendingUsername = null;
    _pendingPassword = null;
    notifyListeners();
  }

  // ========== Registration Validation Methods ==========

  /// Проверка доступности username
  Future<AvailabilityResponse> checkUsername(String username) async {
    try {
      return await _authService.checkUsername(username);
    } on ApiError catch (e) {
      _error = e;
      notifyListeners();
      rethrow;
    }
  }

  /// Проверка доступности email
  Future<AvailabilityResponse> checkEmail(String email) async {
    try {
      return await _authService.checkEmail(email);
    } on ApiError catch (e) {
      _error = e;
      notifyListeners();
      rethrow;
    }
  }

  /// Отправка кода верификации на email
  Future<VerificationCodeResponse> sendVerificationCode(String email, {String? username}) async {
    try {
      return await _authService.sendVerificationCode(email, username: username);
    } on ApiError catch (e) {
      _error = e;
      notifyListeners();
      rethrow;
    }
  }

  /// Проверка кода верификации email
  Future<VerifyCodeResponse> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    try {
      return await _authService.verifyEmailCode(email: email, code: code);
    } on ApiError catch (e) {
      _error = e;
      notifyListeners();
      rethrow;
    }
  }

  // ========== Recent Accounts Methods ==========

  /// Получение недавних аккаунтов для устройства
  Future<RecentAccountsResponse> getRecentAccounts() async {
    try {
      return await _authService.getRecentAccounts();
    } on ApiError catch (e) {
      _error = e;
      notifyListeners();
      rethrow;
    }
  }

  /// Быстрый вход в аккаунт
  /// 
  /// Параметры:
  /// - userId: ID пользователя для быстрого входа
  /// - tfaCode: код 2FA (если требуется)
  /// 
  /// Возвращает:
  /// - true если вход успешен
  /// - false если требуется 2FA или ошибка
  Future<bool> quickLogin({
    required int userId,
    String? tfaCode,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await _authService.quickLogin(
        userId: userId,
        tfaCode: tfaCode,
      );

      // Если требуется 2FA
      if (response.requiresTfa) {
        _status = AuthStatus.tfaRequired;
        _tfaToken = response.code; // tfa_code_id
        _setLoading(false);
        notifyListeners();
        return false;
      }

      // Если вход успешен
    if (response.success) {
      // Создаем UserModel из ответа
      if (response.userInfo != null) {
        _user = UserModel(
          id: response.userInfo!.id ?? 0,
          username: response.userInfo!.username ?? '',
          email: response.userInfo!.email ?? '',
          emailVerified: response.userInfo!.isVerified ?? false,
          tfaEnabled: response.userInfo!.tfaEnabled ?? false,
          avatar: response.userInfo!.avatarUrl,
          createdAt: DateTime.now(),
        );
        
        // Сохраняем аккаунт в недавних
        await _saveRecentAccount(_user!);
      }
      _status = AuthStatus.authenticated;
      _setLoading(false);
      notifyListeners();
      return true;
    }

      // Ошибка
      _error = ApiError(message: response.errorMessage ?? 'Ошибка быстрого входа');
      _status = AuthStatus.unauthenticated;
      _setLoading(false);
      notifyListeners();
      return false;
    } on ApiError catch (e) {
      _error = e;
      _status = AuthStatus.unauthenticated;
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  // ========== Private Methods ==========

  void _setLoading(bool value) {
    _isLoading = value;
  }

  void _clearError() {
    _error = null;
  }

  /// Сохранение аккаунта в недавних
  Future<void> _saveRecentAccount(UserModel user) async {
    try {
      final account = RecentAccount(
        id: user.id,
        username: user.username,
        email: user.email,
        avatar: user.avatar,
        avatarGradient: user.avatarGradient,
        hasAvatar: user.avatar != null,
        lastLogin: DateTime.now(),
        firstLogin: DateTime.now(),
      );
      await _recentAccountsService.saveAccountLocally(account);
    } catch (e) {
      // Ошибка сохранения не должна блокировать вход
      debugPrint('Error saving recent account: $e');
    }
  }
}

/// Фабрика для создания AuthProvider
class AuthProviderFactory {
  static AuthProvider create() {
    final tokenStorage = TokenStorage();
    final apiClient = ApiClient(tokenStorage: tokenStorage);
    final authService = AuthService(
      apiClient: apiClient,
      tokenStorage: tokenStorage,
    );
    final recentAccountsService = RecentAccountsService(
      apiClient: apiClient,
    );

    return AuthProvider(
      authService: authService,
      recentAccountsService: recentAccountsService,
    );
  }
}
