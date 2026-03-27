import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../config/app_config.dart';

/// Безопасное хранение токенов авторизации
/// 
/// Использует flutter_secure_storage:
/// - iOS: Keychain
/// - Android: EncryptedSharedPreferences (AES-256)
/// 
/// Особенности:
/// - Токены хранятся в зашифрованном виде
/// - Автоматическое удаление при деинсталляции (Android)
/// - Защита от чтения на рутованных устройствах (iOS)
class TokenStorage {
  late final FlutterSecureStorage _storage;

  /// Конструктор с настройками безопасности
  TokenStorage() {
    _storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
  }

  /// Сохранить access токен
  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: AppConfig.accessTokenKey, value: token);
  }

  /// Получить access токен
  Future<String?> getAccessToken() async {
    return await _storage.read(key: AppConfig.accessTokenKey);
  }

  /// Сохранить refresh токен
  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: AppConfig.refreshTokenKey, value: token);
  }

  /// Получить refresh токен
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: AppConfig.refreshTokenKey);
  }

  /// Сохранить данные пользователя
  Future<void> saveUserData(Map<String, dynamic> userData) async {
    await _storage.write(
      key: AppConfig.userDataKey,
      value: jsonEncode(userData),
    );
  }

  /// Получить данные пользователя
  Future<Map<String, dynamic>?> getUserData() async {
    final data = await _storage.read(key: AppConfig.userDataKey);
    if (data == null) return null;
    
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Проверить наличие access токена
  Future<bool> hasAccessToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Проверить наличие refresh токена
  Future<bool> hasRefreshToken() async {
    final token = await getRefreshToken();
    return token != null && token.isNotEmpty;
  }

  /// Проверить, авторизован ли пользователь
  Future<bool> isAuthenticated() async {
    return await hasAccessToken() || await hasRefreshToken();
  }

  /// Удалить все токены (выход из аккаунта)
  Future<void> clearAll() async {
    await _storage.delete(key: AppConfig.accessTokenKey);
    await _storage.delete(key: AppConfig.refreshTokenKey);
    await _storage.delete(key: AppConfig.userDataKey);
  }

  /// Удалить только access токен (для принудительного обновления)
  Future<void> clearAccessToken() async {
    await _storage.delete(key: AppConfig.accessTokenKey);
  }

  /// Удалить только refresh токен
  Future<void> clearRefreshToken() async {
    await _storage.delete(key: AppConfig.refreshTokenKey);
  }
}
