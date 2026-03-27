import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../config/app_config.dart';
import '../auth/token_storage.dart';
import 'dart:io';

/// API клиент на базе Dio
///
/// Особенности:
/// - Автоматическое добавление заголовков авторизации
/// - Автоматическое обновление токенов при истечении
/// - Обработка ошибок и rate limiting
/// - Логирование в debug режиме
/// - Поддержка самоподписанных SSL сертификатов (для разработки)
/// - Поддержка cookies для Django-сессий (верификация email)
class ApiClient {
  late final Dio _dio;
  final TokenStorage _tokenStorage;
  late final CookieJar _cookieJar;
  
  /// Флаг для предотвращения множественных обновлений токена
  bool _isRefreshing = false;

  /// Очередь запросов, ожидающих обновления токена
  final List<_PendingRequest> _pendingRequests = [];

  ApiClient({required TokenStorage tokenStorage}) : _tokenStorage = tokenStorage {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.apiTimeout,
      receiveTimeout: AppConfig.apiTimeout,
      sendTimeout: AppConfig.apiTimeout,
      headers: {
        'User-Agent': AppConfig.userAgent,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));

    // Поддержка самоподписанных SSL сертификатов для разработки
    // ВНИМАНИЕ: Отключить в продакшене!
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return client;
      },
    );

    // Инициализируем CookieJar для хранения cookies (Django-сессии)
    _cookieJar = CookieJar();
    
    // Добавляем интерцепторы
    _dio.interceptors.addAll([
      CookieManager(_cookieJar), // Управление cookies
      _AuthInterceptor(this, _tokenStorage),
      _LoggingInterceptor(),
    ]);
  }

  /// GET запрос
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.get(path, queryParameters: queryParameters, options: options);
  }

  /// POST запрос
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.post(path, data: data, queryParameters: queryParameters, options: options);
  }

  /// PUT запрос
  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.put(path, data: data, queryParameters: queryParameters, options: options);
  }

  /// DELETE запрос
  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.delete(path, data: data, queryParameters: queryParameters, options: options);
  }

  /// Обновление access токена
  Future<String?> refreshToken() async {
    if (_isRefreshing) {
      // Если уже обновляем, ждём завершения
      final completer = Completer<String?>();
      _pendingRequests.add(_PendingRequest(completer));
      return completer.future;
    }

    _isRefreshing = true;
    try {
      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken == null) {
        _resolvePendingRequests(null);
        return null;
      }

      final response = await _dio.post(
        AppConfig.authTokenRefresh,
        data: {'refresh': refreshToken},
        options: Options(headers: {'Authorization': ''}), // Без авторизации
      );

      if (response.statusCode == 200 && response.data['access'] != null) {
        final newAccessToken = response.data['access'] as String;
        await _tokenStorage.saveAccessToken(newAccessToken);
        
        // Если есть новый refresh токен, сохраняем его тоже
        if (response.data['refresh'] != null) {
          await _tokenStorage.saveRefreshToken(response.data['refresh'] as String);
        }
        
        _resolvePendingRequests(newAccessToken);
        return newAccessToken;
      }
      
      _resolvePendingRequests(null);
      return null;
    } catch (e) {
      _resolvePendingRequests(null);
      return null;
    } finally {
      _isRefreshing = false;
    }
  }

  void _resolvePendingRequests(String? token) {
    for (final pending in _pendingRequests) {
      pending.completer.complete(token);
    }
    _pendingRequests.clear();
  }

  /// Очистка при выходе из аккаунта
  void clearAuth() {
    // Ничего не делаем с Dio, просто очищаем токены через TokenStorage
  }
}

/// Вспомогательный класс для ожидающих запросов
class _PendingRequest {
  final Completer<String?> completer;
  _PendingRequest(this.completer);
}

/// Интерцептор для авторизации
class _AuthInterceptor extends Interceptor {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  _AuthInterceptor(this._apiClient, this._tokenStorage);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Пропускаем запросы без авторизации
    if (_shouldSkipAuth(options)) {
      return handler.next(options);
    }

    final accessToken = await _tokenStorage.getAccessToken();
    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Если 401 и это не запрос на обновление токена
    if (err.response?.statusCode == 401 && 
        !_isRefreshRequest(err.requestOptions.path)) {
      
      final newToken = await _apiClient.refreshToken();
      if (newToken != null) {
        // Повторяем запрос с новым токеном
        err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
        try {
          final response = await _apiClient._dio.fetch(err.requestOptions);
          return handler.resolve(response);
        } catch (e) {
          return handler.next(err);
        }
      }
    }
    
    handler.next(err);
  }

  bool _shouldSkipAuth(RequestOptions options) {
    final path = options.path;
    return path == AppConfig.authMobileLogin ||
        path == AppConfig.authRegister ||
        path == AppConfig.authMobileRegister ||
        path == AppConfig.authCheckUsername ||
        path == AppConfig.authCheckEmail ||
        path == AppConfig.authSendVerificationCode ||
        path == AppConfig.authVerifyEmailCode ||
        path == AppConfig.authTokenRefresh ||
        path == AppConfig.authTokenVerify ||
        path == AppConfig.authRecentAccounts ||
        path == AppConfig.authQuickLogin;
  }

  bool _isRefreshRequest(String path) {
    return path == AppConfig.authTokenRefresh;
  }
}

/// Интерцептор для логирования
class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('🌐 API Request: ${options.method} ${options.baseUrl}${options.path}');
      if (options.data != null) {
        // Sanitize sensitive data in logs
        final data = options.data is Map ? Map<String, dynamic>.from(options.data) : options.data;
        if (data is Map<String, dynamic>) {
          if (data.containsKey('password')) data['password'] = '***';
          if (data.containsKey('token')) data['token'] = '***';
          if (data.containsKey('refresh')) data['refresh'] = '***';
          if (data.containsKey('access')) data['access'] = '***';
          if (data.containsKey('code')) data['code'] = '***';
        }
        debugPrint(' Data: $data');
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('✅ API Response: ${response.statusCode} ${response.requestOptions.path}');
      if (response.data != null) {
        final data = response.data is Map ? Map<String, dynamic>.from(response.data) : response.data;
        if (data is Map<String, dynamic>) {
          if (data.containsKey('access')) data['access'] = '***';
          if (data.containsKey('refresh')) data['refresh'] = '***';
          if (data.containsKey('temp_token')) data['temp_token'] = '***';
        }
        debugPrint(' Response data: $data');
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('❌ API Error: ${err.response?.statusCode} ${err.requestOptions.path}');
      debugPrint(' Error type: ${err.type}');
      debugPrint(' Error message: ${err.message}');
      if (err.response?.data != null) {
        debugPrint(' Error data: ${err.response?.data}');
      }
    }
    handler.next(err);
  }
}

/// Класс для Completer (нужен для ожидания обновления токена)
class Completer<T> {
  final _future = <Future<T>>[];
  T? _value;
  bool _isCompleted = false;

  Future<T> get future => _future.isEmpty ? Future.value(_value as T) : _future.first;
  
  void complete([T? value]) {
    _value = value;
    _isCompleted = true;
  }
}
