import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DatabaseKeyService {
  static const String _dbKeyStorageKey = 'local_db_encryption_key';
  final FlutterSecureStorage _secureStorage;

  DatabaseKeyService({FlutterSecureStorage? secureStorage}) 
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Возвращает ключ шифрования для БД. Если ключа нет, генерирует новый и сохраняет.
  Future<String> getEncryptionKey() async {
    String? existingKey = await _secureStorage.read(key: _dbKeyStorageKey);
    
    if (existingKey != null && existingKey.isNotEmpty) {
      return existingKey;
    }

    // Генерируем 256-битный ключ (32 байта)
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final newKey = base64UrlEncode(keyBytes);

    await _secureStorage.write(key: _dbKeyStorageKey, value: newKey);
    return newKey;
  }
}
