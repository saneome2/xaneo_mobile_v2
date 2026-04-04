import 'package:flutter/foundation.dart';
import '../models/auth/user_model.dart';
import '../models/auth/auth_response.dart';
import '../models/auth/api_error.dart';
import '../models/auth/recent_account.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/recent_accounts_service.dart';
import '../services/auth/token_storage.dart';
import '../services/api/api_client.dart';
import '../services/crypto/crypto_service.dart';
import '../services/crypto/xsec2_service.dart';

/// Состояние авторизации
enum AuthStatus {
  initial,
  checking,
  unauthenticated,
  tfaRequired,
  authenticated,
}

/// Provider для управления состоянием авторизации
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final RecentAccountsService _recentAccountsService;
  final Xsec2Service? _xsec2Service;
  CryptoService? _cryptoService;

  AuthStatus _status = AuthStatus.initial;
  UserModel? _user;
  String? _tfaToken;
  String? _pendingUsername;
  String? _pendingPassword;
  ApiError? _error;
  bool _isLoading = false;

  AuthProvider({
    required AuthService authService,
    required RecentAccountsService recentAccountsService,
    Xsec2Service? xsec2Service,
    CryptoService? cryptoService,
  }) : _authService = authService,
       _recentAccountsService = recentAccountsService,
       _xsec2Service = xsec2Service,
       _cryptoService = cryptoService;

  void setCryptoService(CryptoService cryptoService) {
    _cryptoService = cryptoService;
  }

  void _syncCryptoServiceFromXsec2() {
    if (_cryptoService == null && _xsec2Service != null) {
      _cryptoService = _xsec2Service!.cryptoService;
    }
  }
  
  void _syncCryptoUserId() {
    final crypto = _cryptoService;
    final user = _user;
    if (crypto == null || user == null || user.id <= 0) return;
    
    crypto.setCurrentUserId(user.id.toString());
    debugPrint('XSEC-2: synced current user id=${user.id} to CryptoService');
  }

  AuthStatus get status => _status;
  UserModel? get user => _user;
  String? get tfaToken => _tfaToken;
  ApiError? get error => _error;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get requiresTfa => _status == AuthStatus.tfaRequired;

  Future<void> checkAuthStatus({CryptoService? cryptoService}) async {
    if (cryptoService != null) {
      _cryptoService = cryptoService;
    }

    _syncCryptoServiceFromXsec2();

    if (_cryptoService != null) {
      try {
        await _cryptoService!.init();
        debugPrint('XSEC-2: CryptoService initialized, hasKeys=${_cryptoService!.hasKeys}');
      } catch (e) {
        debugPrint('XSEC-2: CryptoService init error: $e');
      }
    }

    _status = AuthStatus.checking;
    notifyListeners();

    try {
      final isAuth = await _authService.isAuthenticated();
      if (isAuth) {
        _user = await _authService.getCurrentUser();
        _syncCryptoUserId();
        _status = _user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;

        if (_status == AuthStatus.authenticated && _cryptoService != null) {
          try {
            await _cryptoService!.ensureLocalKeyMatchesServer();
            if (!_cryptoService!.hasKeys) {
              final restored = await _cryptoService!.restoreKeysFromServerIfPossible();
              if (restored) {
                debugPrint('XSEC-2: Restored keys from server payload');
              } else if (_cryptoService!.serverKeysPresentWithoutRecovery) {
                debugPrint('XSEC-2: Server keys detected, skip regeneration to avoid key rotation');
              } else {
                debugPrint('XSEC-2: No keys found anywhere, generating...');
                final keys = await _cryptoService!.generateUserKeys();
                await _cryptoService!.saveUserKeys(keys);
                await _cryptoService!.uploadKeysToServer();
              }
            }
          } catch (e) {
            debugPrint('XSEC-2: Error: $e');
          }
        }
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
    }

    notifyListeners();
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    debugPrint('=== AuthProvider.login() ===');
    _syncCryptoServiceFromXsec2();
    _setLoading(true);
    _clearError();

    try {
      final result = await _authService.mobileLogin(
        username: username,
        password: password,
      );

      if (result.requiresTfa) {
        _status = AuthStatus.tfaRequired;
        _tfaToken = result.tempToken;
        _pendingUsername = username;
        _pendingPassword = password;
        _user = result.userInfo;
        _setLoading(false);
        notifyListeners();
        return false;
      }

      if (result.isSuccess) {
        final authResponse = await _authService.loginWithTokens(
          username: username,
          password: password,
        );

        _user = authResponse.user;
        _syncCryptoUserId();
        _status = AuthStatus.authenticated;

        // Init XSEC-2 keys after successful login
        if (_cryptoService != null) {
          try {
            await _cryptoService!.init();
            await _cryptoService!.ensureLocalKeyMatchesServer();
            if (!_cryptoService!.hasKeys) {
              final restoredFromMobile = await _cryptoService!
                  .tryRestoreKeysFromServerPayload(
                    result.response?.xsec2,
                    password: password,
                    username: username,
                  );

              final restored = restoredFromMobile ||
                  await _cryptoService!.restoreKeysFromServerIfPossible(
                    password: password,
                    username: username,
                  );

              if (restored) {
                debugPrint('XSEC-2: Restored keys from server payload after login');
              } else if (_cryptoService!.serverKeysPresentWithoutRecovery) {
                debugPrint('XSEC-2: Server keys detected, skip regeneration to avoid key rotation');
              } else {
                debugPrint('XSEC-2: No keys after login, generating...');
                final keys = await _cryptoService!.generateUserKeys();
                await _cryptoService!.saveUserKeys(keys);
                await _cryptoService!.uploadKeysToServer();
              }
            } else {
              debugPrint('XSEC-2: Keys exist after login');
            }
          } catch (e) {
            debugPrint('XSEC-2: Error after login: $e');
          }
        }

        await _saveRecentAccount(_user!);
        _setLoading(false);
        notifyListeners();
        return true;
      }

      _error = ApiError(message: result.message ?? 'Login failed');
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

  Future<bool> verifyTfaCode(String code) async {
    if (_tfaToken == null || _pendingUsername == null || _pendingPassword == null) {
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      await _authService.verifyTfaCode(
        tfaCodeId: _tfaToken!,
        code: code,
      );

      final tokenResponse = await _authService.loginWithTokens(
        username: _pendingUsername!,
        password: _pendingPassword!,
      );

      _user = tokenResponse.user;
      _syncCryptoUserId();
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

  void cancelTfa() {
    _tfaToken = null;
    _pendingUsername = null;
    _pendingPassword = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

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
        _user = UserModel(
          id: registerResponse.userId ?? 0,
          username: registerResponse.username ?? '',
          email: registerResponse.email ?? '',
          emailVerified: true,
          createdAt: DateTime.now(),
        );
        _syncCryptoUserId();
        _status = AuthStatus.authenticated;
        _setLoading(false);
        notifyListeners();
        return true;
      } else {
        _error = ApiError(message: registerResponse.message ?? 'Registration failed');
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

  Future<void> logout() async {
    await _authService.logout();
    if (_cryptoService != null) {
      _cryptoService!.setCurrentUserId('');
      await _cryptoService!.clearAllKeys();
    }
    _user = null;
    _status = AuthStatus.unauthenticated;
    _tfaToken = null;
    _pendingUsername = null;
    _pendingPassword = null;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _clearError();
    notifyListeners();
  }

  void resetTfaState() {
    _status = AuthStatus.unauthenticated;
    _tfaToken = null;
    _pendingUsername = null;
    _pendingPassword = null;
    notifyListeners();
  }

  Future<AvailabilityResponse> checkUsername(String username) async {
    try {
      return await _authService.checkUsername(username);
    } on ApiError catch (e) {
      _error = e;
      notifyListeners();
      rethrow;
    }
  }

  Future<AvailabilityResponse> checkEmail(String email) async {
    try {
      return await _authService.checkEmail(email);
    } on ApiError catch (e) {
      _error = e;
      notifyListeners();
      rethrow;
    }
  }

  Future<VerificationCodeResponse> sendVerificationCode(String email, {String? username}) async {
    try {
      return await _authService.sendVerificationCode(email, username: username);
    } on ApiError catch (e) {
      _error = e;
      notifyListeners();
      rethrow;
    }
  }

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

  Future<RecentAccountsResponse> getRecentAccounts() async {
    try {
      return await _authService.getRecentAccounts();
    } on ApiError catch (e) {
      _error = e;
      notifyListeners();
      rethrow;
    }
  }

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

      if (response.requiresTfa) {
        _status = AuthStatus.tfaRequired;
        _tfaToken = response.code;
        _setLoading(false);
        notifyListeners();
        return false;
      }

      if (response.success) {
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
          _syncCryptoUserId();
          await _saveRecentAccount(_user!);
        }
        _status = AuthStatus.authenticated;
        _setLoading(false);
        notifyListeners();
        return true;
      }

      _error = ApiError(message: response.errorMessage ?? 'Quick login failed');
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

  void _setLoading(bool value) {
    _isLoading = value;
  }

  void _clearError() {
    _error = null;
  }

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
      debugPrint('Error saving recent account: $e');
    }
  }
}

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

  static AuthProvider createWithCryptoService(ApiClient apiClient, CryptoService cryptoService) {
    final authService = AuthService(
      apiClient: apiClient,
      tokenStorage: TokenStorage(),
    );
    final recentAccountsService = RecentAccountsService(
      apiClient: apiClient,
    );

    return AuthProvider(
      authService: authService,
      recentAccountsService: recentAccountsService,
      cryptoService: cryptoService,
    );
  }
}