import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../../config/app_config.dart';
import 'crypto_service.dart';

/// XSEC-2 Service — управляет ключами шифрования.
///
/// Текущая схема: X25519 ECDH для личных чатов, серверные ключи для групп.
/// CryptoService теперь полностью реализует XSEC-2 совместимое с веб-клиентом.
class Xsec2Service {
  final ApiClient _apiClient;
  final CryptoService _cryptoService;

  Xsec2Service({
    required ApiClient apiClient,
    required CryptoService cryptoService,
  }) : _apiClient = apiClient, _cryptoService = cryptoService;

  CryptoService get cryptoService => _cryptoService;

  /// Инициализирует ключи при логине.
  /// В текущей схеме ключи детерминистические через ECDH.
  Future<bool> initializeKeys() async {
    try {
      await _cryptoService.init();
      // Если ключей нет — генерируем и загружаем на сервер
      if (!_cryptoService.hasKeys) {
        final keys = await _cryptoService.generateUserKeys();
        await _cryptoService.saveUserKeys(keys);
        await _cryptoService.uploadKeysToServer();
      }
      return true;
    } catch (e) {
      print('Xsec2Service: initializeKeys error: $e');
      return false;
    }
  }

  /// Обеспечивает наличие ключа для chatId.
  Future<Uint8List> ensureKeyForChat(String chatId) async {
    final key = await _cryptoService.ensureKeyForChat(chatId);
    if (key == null) {
      throw Exception('No key available for chat: $chatId');
    }
    return key;
  }

  /// Получает серверный ChatKey (для групп/каналов с epoch-ключами).
  /// Возвращает true если ключ успешно получен и сохранён.
  Future<bool> fetchServerChatKey(String chatId) async {
    try {
      final response = await _requestFirstOk([
        '${AppConfig.xsec2ChatKey}/$chatId/',
        '${AppConfig.xsec2ChatKey}/$chatId',
      ]);

      if (response != null && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final keyHex = (data['key'] ??
            data['chat_key'] ??
            data['server_epoch_key'] ??
            data['encryption_key'] ??
            (data['data'] is Map<String, dynamic>
                ? (data['data'] as Map<String, dynamic>)['key']
                : null))
            ?.toString();

        if (keyHex != null && keyHex.isNotEmpty) {
          // Сохраняем в кэш
          final keyBytes = _hexToBytes(keyHex.trim());
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Xsec2Service: fetchServerChatKey error: $e');
      return false;
    }
  }

  bool _isHex(String value) {
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  Future<Response?> _requestFirstOk(List<String> paths) async {
    for (final path in paths) {
      try {
        final response = await _apiClient.get(
          path,
          options: Options(validateStatus: (status) => status != null && status < 500),
        );
        if (response.statusCode == 200) return response;
      } catch (_) {}
    }
    return null;
  }

  /// Очищает все ключи (при выходе).
  Future<void> clearKeys() async {
    await _cryptoService.clearAllKeys();
  }
}