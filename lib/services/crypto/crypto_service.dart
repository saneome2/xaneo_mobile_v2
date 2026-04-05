import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:argon2/argon2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:pointycastle/digests/blake2b.dart';
import 'package:x25519/x25519.dart' as x25519;
import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../../config/app_config.dart';

/// 🔐 XSEC-2 Crypto Service
/// Реализует E2E шифрование с использованием X25519 ECDH + AES-256-GCM
/// Совместим с веб-клиентом (libsodium-wrappers)
class CryptoService {
  static const String _keysStorageKey = 'xsec2_user_keys';
  static const String _chatKeysCacheKey = 'xsec2_chat_keys_cache';
  static const String _rootKeyContext = 'XSEC-2 root key';
  static const bool _logKeyCandidates = false;

  final FlutterSecureStorage _storage;
  final ApiClient _apiClient;

  /// Кэш ключей чатов в памяти (chatId → Uint8List AES key)
  final Map<String, Uint8List> _chatKeyCache = {};

  /// Кэш epoch-ключей групп/каналов (chatId → Uint8List key)
  final Map<String, Uint8List> _groupEpochKeyCache = {};

  /// Временный negative-cache для epoch endpoint (chatId → не опрашивать до времени)
  final Map<String, DateTime> _groupEpochRetryAfter = {};

  /// Статус ответа epoch endpoint по чату (chatId → был ли HTTP 200)
  final Map<String, bool> _groupEpochEndpointOk = {};

  /// In-flight запросы legacy chat key (chatId → Future<key?>)
  final Map<String, Future<Uint8List?>> _legacyChatKeyInFlight = {};

  /// In-flight запросы epoch key-кандидатов (chatId → Future<keys>)
  final Map<String, Future<List<Uint8List>>> _groupEpochInFlight = {};

  /// Кэш публичных ключей пользователей (userId → payload / null)
  final Map<String, Map<String, dynamic>?> _userPublicKeyCache = {};

  /// In-flight запросы публичных ключей пользователей
  final Map<String, Future<Map<String, dynamic>?>> _userPublicKeyInFlight = {};

  /// Кэш ECDH shared secret (theirPublicKeyHex → shared bytes)
  final Map<String, Uint8List> _sharedSecretCache = {};

  /// Последний успешный decrypt-ключ по чату (chatId → key)
  final Map<String, Uint8List> _lastSuccessfulDecryptKey = {};

  /// Кэш сгенерированных candidate keys для stable-чатов (favorites/personal)
  final Map<String, List<Uint8List>> _candidateDecryptKeyCache = {};

  /// Наши ключи (загружаются при инициализации)
  Map<String, dynamic>? _userKeys;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// ID текущего пользователя (устанавливается извне)
  String? _currentUserId;

  bool _serverKeysPresentWithoutRecovery = false;
  bool get serverKeysPresentWithoutRecovery =>
      _serverKeysPresentWithoutRecovery;

  Uint8List? _sessionBlobRootKey;

  CryptoService({
    required ApiClient apiClient,
    FlutterSecureStorage? storage,
  })  : _apiClient = apiClient,
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  // ================================================================
  // Инициализация
  // ================================================================

  /// Инициализирует криптографию. Должен быть вызван перед использованием.
  Future<void> init() async {
    if (_initialized) return;

    // Загружаем наши ключи из secure storage
    await _loadUserKeys();

    _initialized = true;
  }

  // ================================================================
  // Управление ключами пользователя
  // ================================================================

  /// Проверяет, есть ли у нас ключи
  bool get hasKeys =>
      _userKeys != null && _userKeys!['x25519_private_key'] != null;

  /// Генерирует новую пару X25519 ключей
  Future<Map<String, dynamic>> generateUserKeys() async {
    // Приватный ключ — публичный результат сгенерированный при умножении
    // В Dart x25519 приватный ключ — это просто random bytes
    final privateKey = _generateRandomBytes(32);
    final publicKey = x25519.X25519(privateKey, x25519.basePoint);

    return {
      'x25519_private_key': _bytesToHex(privateKey),
      'x25519_public_key': _bytesToHex(publicKey),
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  /// Сохраняет ключи пользователя
  Future<void> saveUserKeys(Map<String, dynamic> keys) async {
    _userKeys = keys;
    await _storage.write(key: _keysStorageKey, value: jsonEncode(keys));
  }

  /// Загружает ключи пользователя из secure storage
  Future<void> _loadUserKeys() async {
    final keysJson = await _storage.read(key: _keysStorageKey);
    if (keysJson != null) {
      try {
        _userKeys = jsonDecode(keysJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('XSEC-2: Error loading user keys: $e');
      }
    }
  }

  /// Удаляет все ключи (при logout)
  Future<void> clearAllKeys() async {
    await _storage.delete(key: _keysStorageKey);
    await _storage.delete(key: _chatKeysCacheKey);
    _userKeys = null;
    _chatKeyCache.clear();
    _groupEpochKeyCache.clear();
    _groupEpochRetryAfter.clear();
    _groupEpochEndpointOk.clear();
    _legacyChatKeyInFlight.clear();
    _groupEpochInFlight.clear();
    _userPublicKeyCache.clear();
    _userPublicKeyInFlight.clear();
    _sharedSecretCache.clear();
    _lastSuccessfulDecryptKey.clear();
    _candidateDecryptKeyCache.clear();
    _sessionBlobRootKey = null;
  }

  /// Получает наш публичный ключ
  String? get myPublicKey => _userKeys?['x25519_public_key'];

  /// Устанавливает ID текущего пользователя
  void setCurrentUserId(String userId) {
    _currentUserId = userId;
  }

  // ================================================================
  // Сетевые операции для получения ключей
  // ================================================================

  /// Загружает публичные ключи пользователя с сервера
  Future<Map<String, dynamic>?> fetchUserPublicKey(String userId) async {
    if (_userPublicKeyCache.containsKey(userId)) {
      return _userPublicKeyCache[userId];
    }

    final inFlight = _userPublicKeyInFlight[userId];
    if (inFlight != null) {
      return await inFlight;
    }

    final future = () async {
    try {
      final response = await _apiClient.get(
        '/xsec2/keys/$userId/',
        options:
            Options(validateStatus: (status) => status != null && status < 500),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true) {
          _userPublicKeyCache[userId] = data;
          return data;
        }
      } else if (response.statusCode == 404) {
        debugPrint('XSEC-2: User key not found for userId=$userId');
        _userPublicKeyCache[userId] = null;
        return null;
      }
    } catch (e) {
      debugPrint('XSEC-2: Error fetching user public key: $e');
    }
    _userPublicKeyCache[userId] = null;
    return null;
    }();

    _userPublicKeyInFlight[userId] = future;
    try {
      return await future;
    } finally {
      _userPublicKeyInFlight.remove(userId);
    }
  }

  /// Загружает наш зашифрованный ключевой бандл с сервера
  Future<Map<String, dynamic>?> fetchMyKeys() async {
    try {
      final response = await _apiClient.get(AppConfig.xsec2MyKeys);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true) {
          debugPrint(
              'XSEC-2: fetchMyKeys success, root keys=${data.keys.toList()}');
          if (data['xsec2'] is Map<String, dynamic>) {
            final xsec2 = data['xsec2'] as Map<String, dynamic>;
            debugPrint('XSEC-2: fetchMyKeys xsec2 keys=${xsec2.keys.toList()}');
            return data['xsec2'] as Map<String, dynamic>;
          }
          return data;
        }
      }
    } catch (e) {
      debugPrint('XSEC-2: Error fetching my keys: $e');
    }
    return null;
  }

  /// Пытается восстановить локальные ключи из payload сервера.
  /// Возвращает true, если приватный ключ удалось восстановить.
  Future<bool> tryRestoreKeysFromServerPayload(
    Map<String, dynamic>? payload, {
    String? password,
    String? username,
  }) async {
    _serverKeysPresentWithoutRecovery = false;
    if (payload == null) return false;

    final normalizedPayload = (payload['xsec2'] is Map<String, dynamic>)
        ? payload['xsec2'] as Map<String, dynamic>
        : payload;

    debugPrint(
        'XSEC-2: restore payload keys=${normalizedPayload.keys.toList()}');

    final hasServerKeys = normalizedPayload['x25519_public_key'] != null ||
        normalizedPayload['encrypted_blob'] != null ||
        normalizedPayload['has_recovery'] == true;

    final serverPublic = normalizedPayload['x25519_public_key']?.toString();
    if (serverPublic != null && serverPublic.isNotEmpty) {
      final preview = serverPublic.length >= 8
          ? serverPublic.substring(0, 8)
          : serverPublic;
      debugPrint(
          'XSEC-2: server x25519_public_key starts with $preview..., len=${serverPublic.length}');
    }

    final rootPrivate = normalizedPayload['x25519_private_key']?.toString();
    final rootPublic = normalizedPayload['x25519_public_key']?.toString();
    if (rootPrivate != null && rootPrivate.isNotEmpty) {
      if (rootPublic != null && rootPublic.isNotEmpty) {
        final derivedPublic = _derivePublicFromPrivate(rootPrivate);
        if (derivedPublic != rootPublic) {
          debugPrint(
              'XSEC-2: root private/public mismatch in payload, skip restore');
          return false;
        }
      }

      final restored = <String, dynamic>{
        'x25519_private_key': rootPrivate,
        'x25519_public_key': (rootPublic != null && rootPublic.isNotEmpty)
            ? rootPublic
            : _bytesToHex(
                x25519.X25519(_hexToBytes(rootPrivate), x25519.basePoint)),
        'ed25519_public_key': normalizedPayload['ed25519_public_key'],
        'ed25519_private_key': normalizedPayload['ed25519_private_key'],
        'encrypted_blob': normalizedPayload['encrypted_blob'],
        'created_at':
            normalizedPayload['created_at'] ?? DateTime.now().toIso8601String(),
      };
      await saveUserKeys(restored);
      return true;
    }

    final blob = normalizedPayload['encrypted_blob'];
    if (blob is String && blob.isNotEmpty) {
      debugPrint(
          'XSEC-2: encrypted_blob is legacy string/base64 format, len=${blob.length}');
      final parsedBlob = _tryDecodeBase64Json(blob);
      if (parsedBlob != null) {
        debugPrint(
            'XSEC-2: legacy blob decoded JSON keys=${parsedBlob.keys.toList()}');
        final blobPriv = parsedBlob['x25519_private_key']?.toString();
        if (blobPriv != null && blobPriv.isNotEmpty) {
          final expectedPublic =
              normalizedPayload['x25519_public_key']?.toString();
          if (expectedPublic != null && expectedPublic.isNotEmpty) {
            final derivedPublic = _derivePublicFromPrivate(blobPriv);
            if (derivedPublic != expectedPublic) {
              debugPrint(
                  'XSEC-2: legacy blob private/public mismatch, skip restore');
              return false;
            }
          }

          final restored = <String, dynamic>{
            'x25519_private_key': blobPriv,
            'x25519_public_key': normalizedPayload['x25519_public_key'] ??
                parsedBlob['x25519_public_key'] ??
                _bytesToHex(
                    x25519.X25519(_hexToBytes(blobPriv), x25519.basePoint)),
            'ed25519_public_key': normalizedPayload['ed25519_public_key'] ??
                parsedBlob['ed25519_public_key'],
            'ed25519_private_key': parsedBlob['ed25519_private_key'],
            'encrypted_blob': blob,
            if (parsedBlob['chat_keys'] != null)
              'chat_keys': parsedBlob['chat_keys'],
            if (parsedBlob['chatKeys'] != null)
              'chatKeys': parsedBlob['chatKeys'],
            if (parsedBlob['favorites_key'] != null)
              'favorites_key': parsedBlob['favorites_key'],
            if (parsedBlob['favorites_chat_key'] != null)
              'favorites_chat_key': parsedBlob['favorites_chat_key'],
            if (parsedBlob['bookmarks_key'] != null)
              'bookmarks_key': parsedBlob['bookmarks_key'],
            if (parsedBlob['saved_messages_key'] != null)
              'saved_messages_key': parsedBlob['saved_messages_key'],
            'blob_payload': parsedBlob,
            'created_at':
                parsedBlob['created_at'] ?? DateTime.now().toIso8601String(),
          };
          await saveUserKeys(restored);
          return true;
        }
      }
    }

    // Новый формат сервера: encrypted_blob — объект с полями salt/nonce/encrypted_data.
    // Без мастер-пароля восстановить приватный ключ нельзя, но важно НЕ ротировать ключи.
    if (blob is Map<String, dynamic>) {
      debugPrint(
          'XSEC-2: encrypted_blob is structured map, keys=${blob.keys.toList()}');
      final decryptedBlob = await _tryDecryptStructuredBlob(
        blob,
        password: password,
        username: username,
      );
      if (decryptedBlob != null) {
        final blobPriv = decryptedBlob['x25519_private_key']?.toString();
        if (blobPriv != null && blobPriv.isNotEmpty) {
          final expectedPublic =
              normalizedPayload['x25519_public_key']?.toString();
          if (expectedPublic != null && expectedPublic.isNotEmpty) {
            final derivedPublic = _derivePublicFromPrivate(blobPriv);
            if (derivedPublic != expectedPublic) {
              debugPrint(
                  'XSEC-2: structured blob private/public mismatch, skip restore');
              return false;
            }
          }

          final restored = <String, dynamic>{
            'x25519_private_key': blobPriv,
            'x25519_public_key': normalizedPayload['x25519_public_key'] ??
                decryptedBlob['x25519_public_key'] ??
                _bytesToHex(
                    x25519.X25519(_hexToBytes(blobPriv), x25519.basePoint)),
            'ed25519_public_key': normalizedPayload['ed25519_public_key'] ??
                decryptedBlob['ed25519_public_key'],
            'ed25519_private_key': decryptedBlob['ed25519_private_key'],
            'encrypted_blob': blob,
            if (decryptedBlob['chat_keys'] != null)
              'chat_keys': decryptedBlob['chat_keys'],
            if (decryptedBlob['chatKeys'] != null)
              'chatKeys': decryptedBlob['chatKeys'],
            if (decryptedBlob['favorites_key'] != null)
              'favorites_key': decryptedBlob['favorites_key'],
            if (decryptedBlob['favorites_chat_key'] != null)
              'favorites_chat_key': decryptedBlob['favorites_chat_key'],
            if (decryptedBlob['bookmarks_key'] != null)
              'bookmarks_key': decryptedBlob['bookmarks_key'],
            if (decryptedBlob['saved_messages_key'] != null)
              'saved_messages_key': decryptedBlob['saved_messages_key'],
            if (decryptedBlob['blob_payload'] != null)
              'blob_payload': decryptedBlob['blob_payload'],
            'created_at':
                decryptedBlob['created_at'] ?? DateTime.now().toIso8601String(),
          };
          await saveUserKeys(restored);
          debugPrint(
              'XSEC-2: Restored local keys from structured encrypted_blob');
          return true;
        }
      }

      if ((blob['encrypted_data']?.toString().isNotEmpty ?? false) &&
          (normalizedPayload['x25519_public_key']?.toString().isNotEmpty ??
              false)) {
        _serverKeysPresentWithoutRecovery = true;
        debugPrint(
            'XSEC-2: Server encrypted_blob is structured and requires passphrase-based recovery; skip key regeneration');
        return false;
      }
    }

    if (hasServerKeys) {
      _serverKeysPresentWithoutRecovery = true;
      debugPrint(
          'XSEC-2: Server keys exist, but private key is not recoverable on client yet');
    }

    return false;
  }

  Future<bool> restoreKeysFromServerIfPossible(
      {String? password, String? username}) async {
    final payload = await fetchMyKeys();
    return tryRestoreKeysFromServerPayload(
      payload,
      password: password,
      username: username,
    );
  }

  Future<void> ensureLocalKeyMatchesServer() async {
    final payload = await fetchMyKeys();
    if (payload == null) return;

    final serverPublic = payload['x25519_public_key']?.toString();
    final localPublic = myPublicKey;

    if (serverPublic != null &&
        serverPublic.isNotEmpty &&
        localPublic != null &&
        localPublic.isNotEmpty &&
        serverPublic != localPublic) {
      debugPrint(
          'XSEC-2: Local key mismatch with server, clearing local keys to prevent invalid decryption');
      await clearAllKeys();
    }
  }

  Future<Map<String, dynamic>?> _tryDecryptStructuredBlob(
    Map<String, dynamic> blob, {
    String? password,
    String? username,
  }) async {
    final encryptedHex = blob['encrypted_data']?.toString();
    final nonceHex = blob['nonce']?.toString();
    final saltHex = blob['salt']?.toString();

    debugPrint(
        'XSEC-2: structured blob parse start, keys=${blob.keys.toList()}');

    if (encryptedHex == null ||
        nonceHex == null ||
        saltHex == null ||
        password == null ||
        password.isEmpty) {
      debugPrint('XSEC-2: structured blob missing required fields or password');
      return null;
    }

    Uint8List encryptedBytes;
    Uint8List nonce;
    Uint8List salt;
    try {
      encryptedBytes = _hexToBytes(encryptedHex);
      nonce = _hexToBytes(nonceHex);
      salt = _hexToBytes(saltHex);
    } catch (_) {
      debugPrint('XSEC-2: structured blob hex decode failed');
      return null;
    }

    debugPrint(
      'XSEC-2: structured blob decoded sizes encrypted=${encryptedBytes.length}, nonce=${nonce.length}, salt=${salt.length}',
    );

    if (encryptedBytes.length < 16) return null;
    if (nonce.length != 24) return null;

    final ciphertext = encryptedBytes.sublist(0, encryptedBytes.length - 16);
    final tag = encryptedBytes.sublist(encryptedBytes.length - 16);

    final xchacha20 = crypto.Xchacha20.poly1305Aead();
    final aesGcm = crypto.AesGcm.with256bits();

    final secretBoxes = <crypto.SecretBox>[
      crypto.SecretBox(
        ciphertext,
        nonce: nonce,
        mac: crypto.Mac(tag),
      ),
    ];

    // Некоторые реализации могут класть nonce внутрь encrypted_data повторно.
    if (encryptedBytes.length > nonce.length + 16) {
      final prefix = encryptedBytes.sublist(0, nonce.length);
      final sameNonce =
          _bytesToHex(Uint8List.fromList(prefix)) == _bytesToHex(nonce);
      if (sameNonce) {
        final withoutNonce = encryptedBytes.sublist(nonce.length);
        final ct = withoutNonce.sublist(0, withoutNonce.length - 16);
        final tg = withoutNonce.sublist(withoutNonce.length - 16);
        secretBoxes.add(
          crypto.SecretBox(
            ct,
            nonce: nonce,
            mac: crypto.Mac(tg),
          ),
        );
      }
    }

    // Веб использует raw password без нормализаций/комбинаций.
    final candidatePasswords = <String>{password};

    // Web/libsodium crypto_pwhash(ALG_ARGON2ID13)
    final candidateLanes = <int>{1};
    final candidateTypes = <int>{Argon2Parameters.ARGON2_id};
    final candidateVersions = <int>{Argon2Parameters.ARGON2_VERSION_13};
    final candidateIterations = <int>{3};
    // В xsec2.js ARGON2_MEMORY = 64 * 1024 (bytes).
    // Для dart argon2 memory задаётся блоками (≈KiB), поэтому основной профиль = 64.
    // Оставляем fallback 65536 для совместимости с ранними сборками/трактовками.
    final candidateMemoryBlocks = <int>{64, 65536};

    debugPrint(
      'XSEC-2: structured blob trying ${candidatePasswords.length} password variant(s), '
      'lanes=$candidateLanes, types=$candidateTypes, versions=$candidateVersions, '
      'iterations=$candidateIterations, memoryBlocks=$candidateMemoryBlocks',
    );

    for (final candidatePassword in candidatePasswords) {
      for (final lanes in candidateLanes) {
        for (final argonType in candidateTypes) {
          for (final argonVersion in candidateVersions) {
            for (final iterations in candidateIterations) {
              for (final memoryBlocks in candidateMemoryBlocks) {
                try {
                  debugPrint(
                    'XSEC-2: structured blob try argon2 '
                    'type=$argonType version=$argonVersion lanes=$lanes iterations=$iterations memoryBlocks=$memoryBlocks',
                  );
                  final params = Argon2Parameters(
                    argonType,
                    salt,
                    iterations: iterations,
                    memory: memoryBlocks,
                    lanes: lanes,
                    version: argonVersion,
                  );
                  final generator = Argon2BytesGenerator()..init(params);
                  final key = Uint8List(32);
                  generator.generateBytesFromString(candidatePassword, key);
                  final secretKey = crypto.SecretKey(key);

                  for (final box in secretBoxes) {
                    final decryptedVariants = <List<int>>[];

                    try {
                      decryptedVariants.add(
                          await xchacha20.decrypt(box, secretKey: secretKey));
                      debugPrint(
                          'XSEC-2: structured blob XChaCha decrypt success');
                    } catch (_) {}

                    // Fallback на случай исторических/ошибочных blob-схем.
                    if (nonce.length >= 12) {
                      final nonceHead = nonce.sublist(0, 12);
                      final nonceTail = nonce.sublist(nonce.length - 12);
                      final aesBoxHead = crypto.SecretBox(
                        box.cipherText,
                        nonce: nonceHead,
                        mac: box.mac,
                      );
                      final aesBoxTail = crypto.SecretBox(
                        box.cipherText,
                        nonce: nonceTail,
                        mac: box.mac,
                      );

                      try {
                        decryptedVariants.add(await aesGcm.decrypt(aesBoxHead,
                            secretKey: secretKey));
                        debugPrint(
                            'XSEC-2: structured blob AES-GCM(head nonce) decrypt success');
                      } catch (_) {}
                      try {
                        decryptedVariants.add(await aesGcm.decrypt(aesBoxTail,
                            secretKey: secretKey));
                        debugPrint(
                            'XSEC-2: structured blob AES-GCM(tail nonce) decrypt success');
                      } catch (_) {}
                    }

                    for (final decrypted in decryptedVariants) {
                      final parsed = _tryParseJsonMap(decrypted);
                      if (parsed != null) {
                        debugPrint(
                            'XSEC-2: structured blob decrypted JSON keys=${parsed.keys.toList()}');
                        final x25519PrivateRaw =
                            parsed['x25519_private']?.toString() ??
                                parsed['x25519_private_key']?.toString();
                        final ed25519PrivateRaw =
                            parsed['ed25519_private']?.toString() ??
                                parsed['ed25519_private_key']?.toString();

                        final x25519Private =
                            _normalizeKeyString(x25519PrivateRaw);
                        final ed25519Private =
                            _normalizeKeyString(ed25519PrivateRaw);

                        if (x25519Private == null || x25519Private.isEmpty) {
                          continue;
                        }

                        return {
                          // root-key сессии сохраняем только при успешном parse
                          ...() {
                            _sessionBlobRootKey = Uint8List.fromList(key);
                            return <String, dynamic>{};
                          }(),
                          'x25519_private_key': x25519Private,
                          if (ed25519Private != null &&
                              ed25519Private.isNotEmpty)
                            'ed25519_private_key': ed25519Private,
                          if (parsed['x25519_public'] != null)
                            'x25519_public_key': parsed['x25519_public'],
                          if (parsed['ed25519_public'] != null)
                            'ed25519_public_key': parsed['ed25519_public'],
                          if (parsed['chat_keys'] != null)
                            'chat_keys': parsed['chat_keys'],
                          if (parsed['chatKeys'] != null)
                            'chatKeys': parsed['chatKeys'],
                          if (parsed['favorites_key'] != null)
                            'favorites_key': parsed['favorites_key'],
                          if (parsed['favorites_chat_key'] != null)
                            'favorites_chat_key': parsed['favorites_chat_key'],
                          if (parsed['bookmarks_key'] != null)
                            'bookmarks_key': parsed['bookmarks_key'],
                          if (parsed['saved_messages_key'] != null)
                            'saved_messages_key': parsed['saved_messages_key'],
                          'blob_payload': parsed,
                          'created_at': parsed['created_at'],
                        };
                      }

                      // Fallback: бинарный payload 64 байта (x25519_private + ed25519_private)
                      if (decrypted.length >= 64) {
                        debugPrint(
                            'XSEC-2: structured blob decrypted binary payload len=${decrypted.length}');
                        final xPriv =
                            Uint8List.fromList(decrypted.sublist(0, 32));
                        final edPriv =
                            Uint8List.fromList(decrypted.sublist(32, 64));
                        return {
                          ...() {
                            _sessionBlobRootKey = Uint8List.fromList(key);
                            return <String, dynamic>{};
                          }(),
                          'x25519_private_key': _bytesToHex(xPriv),
                          'ed25519_private_key': _bytesToHex(edPriv),
                          'created_at': blob['created_at'],
                        };
                      }
                    }
                  }
                } catch (_) {}
              }
            }
          }
        }
      }
    }

    debugPrint(
        'XSEC-2: structured encrypted_blob decrypt failed (argon2/cipher variants exhausted)');
    return null;
  }

  Map<String, dynamic>? _tryParseJsonMap(List<int> raw) {
    try {
      final text = utf8.decode(raw);
      final parsed = jsonDecode(text);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    return null;
  }

  // ================================================================
  // X25519 ECDH и деривация ключа
  // ================================================================

  /// Вычисляет общий секрет через X25519 ECDH
  Future<Uint8List> _computeSharedSecret(String theirPublicKeyHex) async {
    if (_userKeys == null) {
      debugPrint('XSEC-2: _computeSharedSecret: _userKeys is null!');
      throw StateError('User keys not initialized');
    }

    final normalizedPublicKey = theirPublicKeyHex.trim().toLowerCase();
    final cached = _sharedSecretCache[normalizedPublicKey];
    if (cached != null) {
      return cached;
    }

    final myPrivateKeyHex = _userKeys!['x25519_private_key'] as String;
    debugPrint(
        'XSEC-2: _computeSharedSecret: myPrivKey=${myPrivateKeyHex.substring(0, 8)}...');

    final myPrivateKey = _hexToBytes(myPrivateKeyHex);
    final theirPublicKey = _hexToBytes(theirPublicKeyHex);

    try {
      final algorithm = crypto.X25519();
      final keyPair = crypto.SimpleKeyPairData(
        myPrivateKey,
        publicKey: crypto.SimplePublicKey(
          _hexToBytes(_userKeys!['x25519_public_key'] as String),
          type: crypto.KeyPairType.x25519,
        ),
        type: crypto.KeyPairType.x25519,
      );

      final remotePublicKey = crypto.SimplePublicKey(
        theirPublicKey,
        type: crypto.KeyPairType.x25519,
      );

      final sharedSecretKey = await algorithm.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: remotePublicKey,
      );
      final sharedBytes =
          Uint8List.fromList(await sharedSecretKey.extractBytes());
        _sharedSecretCache[normalizedPublicKey] = sharedBytes;
      debugPrint(
          'XSEC-2: _computeSharedSecret: sharedSecret computed (cryptography.X25519)');
      return sharedBytes;
    } catch (_) {
      final sharedSecret = x25519.X25519(myPrivateKey, theirPublicKey);
        _sharedSecretCache[normalizedPublicKey] = sharedSecret;
      debugPrint(
          'XSEC-2: _computeSharedSecret: sharedSecret computed (x25519 fallback)');
      return sharedSecret;
    }
  }

  /// Деривация корневого ключа из shared secret через HKDF-SHA256
  /// salt = info = "XSEC-2 root key"
  Future<Uint8List> _deriveRootKey(Uint8List sharedSecret) async {
    final context = Uint8List.fromList(utf8.encode(_rootKeyContext));
    final hkdf = crypto.Hkdf(
      hmac: crypto.Hmac.sha256(),
      outputLength: 32,
    );

    final derived = await hkdf.deriveKey(
      secretKey: crypto.SecretKey(sharedSecret),
      nonce: context,
      info: context,
    );

    return Uint8List.fromList(await derived.extractBytes());
  }

  /// Генерирует ключ для личного чата через ECDH
  Future<Uint8List?> _generatePersonalChatKey(
      String chatId, String theirPublicKey) async {
    try {
      final parts = chatId.split('_');
      final currentUserId = await _getCurrentUserId();
      if (parts.length >= 3 && currentUserId != null && currentUserId.isNotEmpty) {
        final otherUserId = parts[1] == currentUserId ? parts[2] : parts[1];
        final sharedSecret = await _computeSharedSecret(theirPublicKey);
        return _derivePersonalWebKey(sharedSecret, currentUserId, otherUserId);
      }

      final sharedSecret = await _computeSharedSecret(theirPublicKey);

      // Backend/web: HKDF-SHA256 with fixed root context
      return _deriveRootKey(sharedSecret);
    } catch (e) {
      debugPrint('XSEC-2: Error generating personal chat key: $e');
      return null;
    }
  }

  /// Точная web-деривация ключа favorites:
  /// shared = X25519(self, self)
  /// salt = blake2b("favorites:<userId>", 32)
  /// key = blake2b(shared, key=salt, 32)
  Uint8List _deriveFavoritesWebKey(Uint8List sharedSecret, String userId) {
    final context = Uint8List.fromList(utf8.encode('favorites:$userId'));
    final salt = _blake2bDigest(context, outputLength: 32);
    return _blake2bDigest(sharedSecret, key: salt, outputLength: 32);
  }

  /// Web-деривация ключа personal:
  /// context = personal:<minUserId>:<maxUserId>
  /// salt = blake2b(context, 32)
  /// key = blake2b(shared, key=salt, 32)
  Uint8List _derivePersonalWebKey(
    Uint8List sharedSecret,
    String userA,
    String userB,
  ) {
    final sorted = [userA, userB]..sort();
    final context = Uint8List.fromList(
      utf8.encode('personal:${sorted[0]}:${sorted[1]}'),
    );
    final salt = _blake2bDigest(context, outputLength: 32);
    return _blake2bDigest(sharedSecret, key: salt, outputLength: 32);
  }

  // ================================================================
  // Ключи чатов
  // ================================================================

  /// Обеспечивает наличие ключа для чата
  Future<Uint8List?> ensureKeyForChat(String chatId) async {
    // Проверяем кэш
    if (_chatKeyCache.containsKey(chatId)) {
      return _chatKeyCache[chatId];
    }

    // Проверяем тип чата
    final parts = chatId.split('_');

    if (parts[0] == 'personal' && parts.length >= 3) {
      // Личный чат: ECDH с собеседником
      final currentUserId = await _getCurrentUserId();
      if (currentUserId == null || currentUserId.isEmpty) {
        debugPrint('XSEC-2: personal: current user id is not set');
        return null;
      }
      final otherUserId = parts[1] == currentUserId ? parts[2] : parts[1];

      final theirKeyData = await fetchUserPublicKey(otherUserId);
      if (theirKeyData == null || theirKeyData['x25519_public_key'] == null) {
        return null;
      }

      // Бот — не используем E2E шифрование
      if (theirKeyData['is_bot'] == true) {
        return null;
      }

      final theirPublicKey = theirKeyData['x25519_public_key'] as String;
      final key = await _generatePersonalChatKey(chatId, theirPublicKey);
      if (key != null) {
        _chatKeyCache[chatId] = key;
      }
      return key;
    }

    if (parts[0] == 'favorites') {
      final localBlobKey = _extractFavoritesOrChatKeyFromUserKeys(chatId);
      if (localBlobKey != null) {
        debugPrint(
            'XSEC-2: favorites: using key from restored encrypted_blob payload');
        _chatKeyCache[chatId] = localBlobKey;
        return localBlobKey;
      }

      // Избранное: ECDH с самим собой
      debugPrint('XSEC-2: favorites: myPublicKey=${myPublicKey}');
      final myPub = myPublicKey;
      if (myPub == null) {
        debugPrint('XSEC-2: favorites: No public key, returning null');
        return null;
      }

      final currentUserId = await _getCurrentUserId();
      if (currentUserId == null || currentUserId.isEmpty) {
        debugPrint('XSEC-2: favorites: current user id is not set');
        return null;
      }

      final sharedSecret = await _computeSharedSecret(myPub);

      // Web-compatible favorites derivation (without root HKDF)
      final key = _deriveFavoritesWebKey(sharedSecret, currentUserId);
      _chatKeyCache[chatId] = key;
      return key;
    }

    if (parts[0] == 'group' || parts[0] == 'channel') {
      // Группы/каналы: mixed-модель — сначала epoch key, затем legacy fallback
      final epochCandidates = await _fetchGroupEpochKeyCandidates(chatId);
      if (epochCandidates.isNotEmpty) {
        _chatKeyCache[chatId] = epochCandidates.first;
        return epochCandidates.first;
      }

      final epochOk = _groupEpochEndpointOk[chatId] == true;
      if (epochOk) {
        debugPrint(
            'XSEC-2: group/channel: epoch endpoint responded 200 but no usable epoch key, skip legacy fallback');
        return null;
      }

      return await _fetchLegacyChatKey(chatId);
    }

    return null;
  }

  /// Получает серверный ключ чата (legacy ChatKey)
  Future<Uint8List?> _fetchLegacyChatKey(String chatId) async {
    final cached = _chatKeyCache[chatId];
    if (cached != null) return cached;

    final inFlight = _legacyChatKeyInFlight[chatId];
    if (inFlight != null) {
      return await inFlight;
    }

    final future = () async {
      try {
        final response = await _apiClient.get('/xsec2/keys/chat/$chatId/');

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data as Map<String, dynamic>;
          if (data['success'] == true && data['key'] != null) {
            final keyHex = data['key'] as String;
            final key = _hexToBytes(keyHex.trim());
            _chatKeyCache[chatId] = key;
            return key;
          }
        }
      } catch (e) {
        debugPrint('XSEC-2: Error fetching chat key: $e');
      }
      return null;
    }();

    _legacyChatKeyInFlight[chatId] = future;
    try {
      return await future;
    } finally {
      _legacyChatKeyInFlight.remove(chatId);
    }
  }

  Future<List<Uint8List>> _fetchGroupEpochKeyCandidates(String chatId) async {
    final cached = _groupEpochKeyCache[chatId];
    if (cached != null) {
      return [cached];
    }

    final retryAfter = _groupEpochRetryAfter[chatId];
    if (retryAfter != null && retryAfter.isAfter(DateTime.now())) {
      return [];
    }

    final inFlight = _groupEpochInFlight[chatId];
    if (inFlight != null) {
      return await inFlight;
    }

    final future = () async {
      final variants = <Uint8List>[];
      var endpointOk = false;

      void add(Uint8List key, {String? label}) {
        if (key.length != 32) return;
        final fingerprint = _bytesToHex(key);
        if (variants.any((k) => _bytesToHex(k) == fingerprint)) return;
        variants.add(key);
        if (label != null) {
          final preview = fingerprint.length >= 12
              ? fingerprint.substring(0, 12)
              : fingerprint;
          debugPrint('XSEC-2: group epoch key [$label] fp=$preview...');
        }
      }

      void collectFromDynamic(dynamic node) {
        if (node == null) return;

        if (node is String) {
          final key = _decodeServerKey(node);
          if (key != null) add(key);
          return;
        }

        if (node is List) {
          for (final item in node) {
            collectFromDynamic(item);
          }
          return;
        }

        if (node is! Map) return;

        final map = Map<String, dynamic>.from(node);
        const directFields = [
          'server_epoch_key',
          'epoch_key',
          'key',
          'chat_key',
          'encryption_key',
        ];

        for (final field in directFields) {
          final value = map[field];
          if (value is String) {
            final key = _decodeServerKey(value);
            if (key != null) add(key, label: field);
          }
        }

        const nestedFields = [
          'data',
          'result',
          'epoch',
          'current_epoch',
          'epochs',
          'keys',
          'items',
        ];
        for (final field in nestedFields) {
          if (map.containsKey(field)) {
            collectFromDynamic(map[field]);
          }
        }
      }

      final requestPlans = <({String path, Map<String, dynamic>? query})>[
        // Эталонный backend contract: /xsec2/group/<chat_id>/epoch/current/
        (path: '/xsec2/group/$chatId/epoch/current/', query: null),
        (path: '/xsec2/group/$chatId/epoch/current', query: null),
      ];

      for (final plan in requestPlans) {
        try {
          final response = await _apiClient.get(
            plan.path,
            queryParameters: plan.query,
            options: Options(
                validateStatus: (status) => status != null && status < 500),
          );

          if (response.statusCode == 200) {
            endpointOk = true;
          }

          if (response.statusCode != 200 || response.data == null) {
            continue;
          }

          collectFromDynamic(response.data);
        } catch (_) {}
      }

      if (variants.isNotEmpty) {
        _groupEpochKeyCache[chatId] = variants.first;
        _groupEpochRetryAfter.remove(chatId);
        _groupEpochEndpointOk[chatId] = endpointOk;
      } else {
        _groupEpochRetryAfter[chatId] =
            DateTime.now().add(const Duration(minutes: 2));
        _groupEpochEndpointOk[chatId] = endpointOk;
      }

      return variants;
    }();

    _groupEpochInFlight[chatId] = future;
    try {
      return await future;
    } finally {
      _groupEpochInFlight.remove(chatId);
    }
  }

  Uint8List? _decodeServerKey(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return null;

    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(raw)) {
      return _hexToBytes(raw);
    }

    final b64 = _normalizeBase64Decode(raw);
    if (b64 != null && b64.length == 32) {
      return b64;
    }

    return null;
  }

  // ================================================================
  // Шифрование/дешифрование сообщений
  // ================================================================

  /// Шифрует сообщение для отправки
  /// Формат: base64(12 байт nonce + ciphertext)
  Future<String?> encryptMessage(String plaintext, String chatId) async {
    try {
      final key = await ensureKeyForChat(chatId);
      if (key == null) {
        debugPrint('XSEC-2: No key for chat $chatId');
        return null;
      }

      // Используем AES-256-GCM из crypto package
      final aesGcm = crypto.AesGcm.with256bits();

      final secretKey = crypto.SecretKey(key);
      final plaintextBytes = utf8.encode(plaintext);

      // Шифруем
      final box = await aesGcm.encrypt(
        plaintextBytes,
        secretKey: secretKey,
      );

      // Nonce 12 байт + ciphertext + tag (16 байт)
      final nonce = box.nonce;
      final ciphertext = box.cipherText;
      final mac = box.mac.bytes;

      // Объединяем: nonce + ciphertext + mac
      final combined = Uint8List(nonce.length + ciphertext.length + mac.length);
      combined.setRange(0, nonce.length, nonce);
      combined.setRange(
          nonce.length, nonce.length + ciphertext.length, ciphertext);
      combined.setRange(nonce.length + ciphertext.length, combined.length, mac);

      return base64Encode(combined);
    } catch (e) {
      debugPrint('XSEC-2: Encryption error: $e');
      return null;
    }
  }

  /// Расшифровывает сообщение
  /// Для personal/favorites web в приоритете AES-GCM (nonce=12, формат nonce|cipher|tag)
  /// XChaCha20/ChaCha20 оставлены как fallback для legacy payload.
  Future<String?> decryptMessage(String encryptedBase64, String chatId) async {
    try {
      debugPrint('XSEC-2: decryptMessage start for chat $chatId');

      if (encryptedBase64.isEmpty) return null;

      final baseKey = await ensureKeyForChat(chatId);
      if (baseKey == null) {
        debugPrint('XSEC-2: No key for chat $chatId');
        return null;
      }

      final candidateKeys = await _candidateDecryptKeys(chatId, baseKey);

      final encryptedData = _normalizeBase64Decode(encryptedBase64.trim());
      if (encryptedData == null) {
        debugPrint('XSEC-2: Failed to decode base64');
        return null;
      }

      final fastKey = _lastSuccessfulDecryptKey[chatId];
      if (fastKey != null) {
        final fastResult =
            await _tryDecryptWithSingleKey(encryptedData, fastKey, chatId);
        if (fastResult != null) {
          return fastResult;
        }
      }

      debugPrint('XSEC-2: encryptedData.length=${encryptedData.length}');

      // Определяем формат по длине
      // XChaCha20-Poly1305: 24 байт nonce + (ciphertext + 16 байт tag)
      // AES-GCM: 12 байт nonce + ciphertext + 16 байт tag

      // Даем шанс расшифровать коротким payload (12 nonce + 16 tag + 2..X bytes cipher)
      if (encryptedData.length >= 28) {
        for (var index = 0; index < candidateKeys.length; index++) {
          final result = await _decryptAesGcm(
            encryptedData,
            candidateKeys[index],
            chatId: chatId,
          );
          if (result != null) {
            _lastSuccessfulDecryptKey[chatId] = candidateKeys[index];
            debugPrint(
                'XSEC-2: AES-GCM decrypted with key variant #$index: $result');
            return result;
          }

          final chachaResult = await _decryptChaCha20Poly1305(
            encryptedData,
            candidateKeys[index],
            chatId: chatId,
          );
          if (chachaResult != null) {
            _lastSuccessfulDecryptKey[chatId] = candidateKeys[index];
            debugPrint(
                'XSEC-2: ChaCha20-Poly1305 decrypted with key variant #$index: $chachaResult');
            return chachaResult;
          }
        }
      }

      // Fallback для legacy/нестандартных payload
      if (encryptedData.length >= 40) {
        for (var index = 0; index < candidateKeys.length; index++) {
          final result = await _decryptXChaCha20(
            encryptedData,
            candidateKeys[index],
            chatId: chatId,
          );
          if (result != null) {
            _lastSuccessfulDecryptKey[chatId] = candidateKeys[index];
            debugPrint(
                'XSEC-2: XChaCha20 decrypted with key variant #$index: $result');
            return result;
          }
        }
      }

      debugPrint('XSEC-2: All decryption methods failed');
      return null;
    } catch (e) {
      debugPrint('XSEC-2: Decryption error: $e');
      return null;
    }
  }

  /// Расшифровка XChaCha20-Poly1305
  /// Формат: 24 байта nonce + ciphertext + 16 байт tag (в конце ciphertext)
  Future<String?> _decryptXChaCha20(Uint8List data, Uint8List key,
      {String? chatId}) async {
    const nonceLen = 24;
    const tagLen = 16;

    if (data.length <= nonceLen + tagLen) return null;

    final nonce = data.sublist(0, nonceLen);
    final ciphertextWithTag = data.sublist(nonceLen);

    // Tag встроен в конец ciphertext
    if (ciphertextWithTag.length < tagLen) return null;

    final ciphertext =
        ciphertextWithTag.sublist(0, ciphertextWithTag.length - tagLen);
    final tag = ciphertextWithTag.sublist(ciphertextWithTag.length - tagLen);

    debugPrint(
        'XSEC-2: XChaCha20: nonce=${nonce.length}, ciphertext=${ciphertext.length}, tag=${tag.length}');

    try {
      final xchacha20 = crypto.Xchacha20.poly1305Aead();
      final secretKey = crypto.SecretKey(key);

      final box = crypto.SecretBox(
        ciphertext,
        nonce: nonce,
        mac: crypto.Mac(tag),
      );

      for (final aad in _candidateAad(chatId)) {
        try {
          final decrypted = aad == null
              ? await xchacha20.decrypt(
                  box,
                  secretKey: secretKey,
                )
              : await xchacha20.decrypt(
                  box,
                  secretKey: secretKey,
                  aad: aad,
                );
          return utf8.decode(decrypted);
        } catch (_) {}
      }

      return null;
    } catch (e) {
      debugPrint('XSEC-2: XChaCha20 failed: $e');
      return null;
    }
  }

  /// Расшифровка AES-GCM
  /// Формат: 12 байт nonce + ciphertext + 16 байт tag
  Future<String?> _decryptAesGcm(Uint8List data, Uint8List key,
      {String? chatId}) async {
    const nonceLen = 12;
    const tagLen = 16;

    if (data.length <= nonceLen + tagLen) return null;

    final cipherLen = data.length - nonceLen - tagLen;
    if (cipherLen <= 0) return null;

    final layouts =
        <({String name, Uint8List nonce, Uint8List ciphertext, Uint8List tag})>[
      (
        name: 'nonce|cipher|tag',
        nonce: data.sublist(0, nonceLen),
        ciphertext: data.sublist(nonceLen, nonceLen + cipherLen),
        tag: data.sublist(nonceLen + cipherLen),
      ),
      (
        name: 'nonce|tag|cipher',
        nonce: data.sublist(0, nonceLen),
        ciphertext: data.sublist(nonceLen + tagLen),
        tag: data.sublist(nonceLen, nonceLen + tagLen),
      ),
      (
        name: 'cipher|tag|nonce',
        nonce: data.sublist(data.length - nonceLen),
        ciphertext: data.sublist(0, cipherLen),
        tag: data.sublist(cipherLen, cipherLen + tagLen),
      ),
      (
        name: 'cipher|nonce|tag',
        nonce: data.sublist(cipherLen, cipherLen + nonceLen),
        ciphertext: data.sublist(0, cipherLen),
        tag: data.sublist(cipherLen + nonceLen),
      ),
      (
        name: 'tag|nonce|cipher',
        nonce: data.sublist(tagLen, tagLen + nonceLen),
        ciphertext: data.sublist(tagLen + nonceLen),
        tag: data.sublist(0, tagLen),
      ),
      (
        name: 'tag|cipher|nonce',
        nonce: data.sublist(data.length - nonceLen),
        ciphertext: data.sublist(tagLen, tagLen + cipherLen),
        tag: data.sublist(0, tagLen),
      ),
    ];

    try {
      final aesGcm = crypto.AesGcm.with256bits();
      final secretKey = crypto.SecretKey(key);

      for (final layout in layouts) {
        final box = crypto.SecretBox(
          layout.ciphertext,
          nonce: layout.nonce,
          mac: crypto.Mac(layout.tag),
        );

        for (final aad in _candidateAad(chatId)) {
          try {
            final decrypted = aad == null
                ? await aesGcm.decrypt(
                    box,
                    secretKey: secretKey,
                  )
                : await aesGcm.decrypt(
                    box,
                    secretKey: secretKey,
                    aad: aad,
                  );
            debugPrint(
                'XSEC-2: AES-GCM decrypt success with layout=${layout.name}');
            return utf8.decode(decrypted);
          } catch (_) {}
        }
      }

      return null;
    } catch (e) {
      debugPrint('XSEC-2: AES-GCM failed: $e');
      return null;
    }
  }

  /// Расшифровка ChaCha20-Poly1305 (IETF)
  /// Формат: 12 байт nonce + ciphertext + 16 байт tag
  Future<String?> _decryptChaCha20Poly1305(Uint8List data, Uint8List key,
      {String? chatId}) async {
    const nonceLen = 12;
    const tagLen = 16;

    if (data.length <= nonceLen + tagLen) return null;

    final cipherLen = data.length - nonceLen - tagLen;
    if (cipherLen <= 0) return null;

    final layouts =
        <({String name, Uint8List nonce, Uint8List ciphertext, Uint8List tag})>[
      (
        name: 'nonce|cipher|tag',
        nonce: data.sublist(0, nonceLen),
        ciphertext: data.sublist(nonceLen, nonceLen + cipherLen),
        tag: data.sublist(nonceLen + cipherLen),
      ),
      (
        name: 'nonce|tag|cipher',
        nonce: data.sublist(0, nonceLen),
        ciphertext: data.sublist(nonceLen + tagLen),
        tag: data.sublist(nonceLen, nonceLen + tagLen),
      ),
      (
        name: 'cipher|tag|nonce',
        nonce: data.sublist(data.length - nonceLen),
        ciphertext: data.sublist(0, cipherLen),
        tag: data.sublist(cipherLen, cipherLen + tagLen),
      ),
      (
        name: 'cipher|nonce|tag',
        nonce: data.sublist(cipherLen, cipherLen + nonceLen),
        ciphertext: data.sublist(0, cipherLen),
        tag: data.sublist(cipherLen + nonceLen),
      ),
      (
        name: 'tag|nonce|cipher',
        nonce: data.sublist(tagLen, tagLen + nonceLen),
        ciphertext: data.sublist(tagLen + nonceLen),
        tag: data.sublist(0, tagLen),
      ),
      (
        name: 'tag|cipher|nonce',
        nonce: data.sublist(data.length - nonceLen),
        ciphertext: data.sublist(tagLen, tagLen + cipherLen),
        tag: data.sublist(0, tagLen),
      ),
    ];

    try {
      final chacha20 = crypto.Chacha20.poly1305Aead();
      final secretKey = crypto.SecretKey(key);

      for (final layout in layouts) {
        final box = crypto.SecretBox(
          layout.ciphertext,
          nonce: layout.nonce,
          mac: crypto.Mac(layout.tag),
        );

        for (final aad in _candidateAad(chatId)) {
          try {
            final decrypted = aad == null
                ? await chacha20.decrypt(
                    box,
                    secretKey: secretKey,
                  )
                : await chacha20.decrypt(
                    box,
                    secretKey: secretKey,
                    aad: aad,
                  );
            debugPrint(
                'XSEC-2: ChaCha20-Poly1305 decrypt success with layout=${layout.name}');
            return utf8.decode(decrypted);
          } catch (_) {}
        }
      }

      return null;
    } catch (e) {
      debugPrint('XSEC-2: ChaCha20-Poly1305 failed: $e');
      return null;
    }
  }

  /// Расшифровывает сообщение для списка чатов
  /// (обёртка для совместимости с существующим кодом)
  Future<String?> decryptChatMessage(
      String encryptedBase64, String chatId) async {
    return decryptMessage(encryptedBase64, chatId);
  }

  /// Проверяет, является ли строка зашифрованным сообщением
  /// (base64 с nonce + ciphertext)
  bool isEncryptedMessage(String text) {
    if (text.isEmpty) return false;

    try {
      final trimmed = text.trim();
      // Проверяем что это валидный base64
      final decoded = _normalizeBase64Decode(trimmed);
      if (decoded == null) return false;

      // Минимальная длина: 12 байт nonce + тег 16 байт
      return decoded.length >= 28;
    } catch (e) {
      return false;
    }
  }

  // ================================================================
  // Загрузка и отправка ключей на сервер
  // ================================================================

  /// Создаёт и загружает ключи на сервер
  Future<bool> uploadKeysToServer() async {
    try {
      if (!hasKeys) {
        // Генерируем ключи если ещё нет
        final keys = await generateUserKeys();
        await saveUserKeys(keys);
      }

      await _ensureUploadFields();

      final ed25519PublicKey = _userKeys?['ed25519_public_key']?.toString();
      final encryptedBlob = _userKeys?['encrypted_blob']?.toString();

      final keys = {
        'x25519_public_key': _userKeys!['x25519_public_key'],
        'ed25519_public_key': ed25519PublicKey,
        'encrypted_blob': encryptedBlob,
        'recovery_blob': null,
      };

      final response = await _apiClient.post(
        AppConfig.xsec2UploadKeys,
        data: keys,
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('XSEC-2: Error uploading keys: $e');
      return false;
    }
  }

  Future<void> _ensureUploadFields() async {
    if (_userKeys == null) return;

    var changed = false;

    final hasEd25519 =
        (_userKeys!['ed25519_public_key']?.toString().isNotEmpty ?? false);
    if (!hasEd25519) {
      final ed25519 = crypto.Ed25519();
      final keyPair = await ed25519.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

      _userKeys!['ed25519_public_key'] =
          _bytesToHex(Uint8List.fromList(publicKey.bytes));
      _userKeys!['ed25519_private_key'] =
          _bytesToHex(Uint8List.fromList(privateKeyBytes));
      changed = true;
    }

    final hasBlob =
        (_userKeys!['encrypted_blob']?.toString().isNotEmpty ?? false);
    if (!hasBlob) {
      final blobPayload = {
        'version': 1,
        'x25519_private_key': _userKeys!['x25519_private_key'],
        'ed25519_private_key': _userKeys!['ed25519_private_key'],
        'created_at': _userKeys!['created_at'],
      };
      _userKeys!['encrypted_blob'] =
          base64Encode(utf8.encode(jsonEncode(blobPayload)));
      changed = true;
    }

    if (changed) {
      await saveUserKeys(_userKeys!);
    }
  }

  List<Uint8List?> _candidateAad(String? chatId) {
    if (chatId == null || chatId.isEmpty) return [null];
    return [
      null,
      Uint8List.fromList(utf8.encode(chatId)),
      Uint8List.fromList(utf8.encode('chat:$chatId')),
    ];
  }

  Future<List<Uint8List>> _candidateDecryptKeys(
      String chatId, Uint8List baseKey) async {
    final parts = chatId.split('_');
    if (parts.isEmpty) return <Uint8List>[];

    final isStableChat = parts[0] == 'favorites' || parts[0] == 'personal';
    if (isStableChat && _candidateDecryptKeyCache.containsKey(chatId)) {
      final cached = _candidateDecryptKeyCache[chatId]!;
      final ordered = <Uint8List>[];
      final fastKey = _lastSuccessfulDecryptKey[chatId];
      if (fastKey != null) {
        ordered.add(fastKey);
      }
      ordered.add(baseKey);
      ordered.addAll(cached);
      return _dedupeKeys(ordered);
    }

    final variants = <Uint8List>[];

    void add(Uint8List key, {String? label}) {
      if (key.length != 32) return;
      final fingerprint = _bytesToHex(key);
      if (variants.any((k) => _bytesToHex(k) == fingerprint)) return;
      variants.add(key);
      if (_logKeyCandidates && label != null) {
        final preview = fingerprint.length >= 12
            ? fingerprint.substring(0, 12)
            : fingerprint;
        debugPrint('XSEC-2: key candidate [$label] fp=$preview...');
      }
    }

    if (parts[0] == 'group' || parts[0] == 'channel') {
      var hasEpochKey = false;
      try {
        final epochKeys = await _fetchGroupEpochKeyCandidates(chatId);
        for (final key in epochKeys) {
          add(key, label: 'group.epoch.current');
        }
        hasEpochKey = epochKeys.isNotEmpty;
      } catch (_) {}

      final epochOk = _groupEpochEndpointOk[chatId] == true;
      if (epochOk && !hasEpochKey) {
        debugPrint(
            'XSEC-2: group/channel: epoch 200 without usable key, no legacy candidates');
        return variants;
      }

      // Протокольный fallback: если epoch недоступен, пробуем только legacy chat key.
      if (!hasEpochKey) {
        add(baseKey, label: 'group.legacy.chatKey');
      }

      return _dedupeKeys(variants);
    }

    if (parts[0] == 'personal' && parts.length >= 3 && myPublicKey != null) {
      try {
        final currentUserId = await _getCurrentUserId();
        if (currentUserId != null && currentUserId.isNotEmpty) {
          final otherUserId = parts[1] == currentUserId ? parts[2] : parts[1];
          final theirKeyData = await fetchUserPublicKey(otherUserId);
          final theirPub = theirKeyData?['x25519_public_key']?.toString();
          if (theirPub != null && theirPub.isNotEmpty) {
            final shared = await _computeSharedSecret(theirPub);
            add(
              _derivePersonalWebKey(shared, currentUserId, otherUserId),
              label: 'personal.web.exact(blake2b)',
            );
          }
        }
      } catch (_) {}
    }

    if (parts[0] == 'favorites' && myPublicKey != null) {
      try {
        final currentUserId = await _getCurrentUserId();
        if (currentUserId != null && currentUserId.isNotEmpty) {
          final shared = await _computeSharedSecret(myPublicKey!);
          add(
            _deriveFavoritesWebKey(shared, currentUserId),
            label: 'favorites.web.exact(blake2b)',
          );
        }
      } catch (_) {}
    }

    add(baseKey, label: 'base');

    // favorites: пробуем несколько исторических/кросс-клиентных derivation-вариантов
    if (parts[0] == 'favorites' && myPublicKey != null) {
      try {
        final shared = await _computeSharedSecret(myPublicKey!);
        final root = await _deriveRootKey(shared);
        final sharedHexBytes =
            Uint8List.fromList(utf8.encode(_bytesToHex(shared)));
        final rootHexBytes = Uint8List.fromList(utf8.encode(_bytesToHex(root)));
        final rootContext = Uint8List.fromList(utf8.encode(_rootKeyContext));
        final currentUserId = await _getCurrentUserId();
        if (currentUserId == null || currentUserId.isEmpty) return variants;
        final chatIdBytes = Uint8List.fromList(utf8.encode(chatId));
        final userIdBytes = Uint8List.fromList(utf8.encode(currentUserId));
        final favContext =
            Uint8List.fromList(utf8.encode('favorites:$currentUserId'));
        final favNamespace =
            Uint8List.fromList(utf8.encode('xsec2:favorites:$currentUserId'));
        final myPrivateHex = _userKeys?['x25519_private_key']?.toString();
        final myPrivate =
            myPrivateHex != null ? _hexToBytes(myPrivateHex) : null;

        // 1) Основной: root/root
        add(root, label: 'favorites.hkdf.root');

        // 1b) Иногда шифруют напрямую shared secret (без HKDF)
        add(shared, label: 'favorites.shared.raw');

        // 1c) Web-compatible BLAKE2b variants for favorites
        final favSaltKeyedByShared = _blake2bDigest(
          favNamespace,
          key: shared,
          outputLength: 32,
        );
        final favSaltKeyedByRoot = _blake2bDigest(
          favNamespace,
          key: root,
          outputLength: 32,
        );
        final favSaltUnkeyed = _blake2bDigest(
          favNamespace,
          outputLength: 32,
        );

        add(
          _blake2bDigest(root, key: favSaltKeyedByShared, outputLength: 32),
          label: 'favorites.blake(root|salt=blake(ns,key=shared))',
        );
        add(
          _blake2bDigest(shared, key: favSaltKeyedByRoot, outputLength: 32),
          label: 'favorites.blake(shared|salt=blake(ns,key=root))',
        );
        add(
          _blake2bDigest(root, key: favSaltUnkeyed, outputLength: 32),
          label: 'favorites.blake(root|salt=blake(ns))',
        );
        add(
          _blake2bDigest(shared, key: favSaltUnkeyed, outputLength: 32),
          label: 'favorites.blake(shared|salt=blake(ns))',
        );
        add(
          _blake2bDigest(root,
              key: _blake2bDigest(chatIdBytes, outputLength: 32),
              outputLength: 32),
          label: 'favorites.blake(root|salt=blake(chatId))',
        );
        add(
          _blake2bDigest(shared,
              key: _blake2bDigest(chatIdBytes, outputLength: 32),
              outputLength: 32),
          label: 'favorites.blake(shared|salt=blake(chatId))',
        );
        add(
          _blake2bDigest(rootHexBytes, key: chatIdBytes, outputLength: 32),
          label: 'favorites.blake(rootHex|key=chatId)',
        );
        add(
          _blake2bDigest(sharedHexBytes, key: chatIdBytes, outputLength: 32),
          label: 'favorites.blake(sharedHex|key=chatId)',
        );
        add(
          _blake2bDigest(root, key: chatIdBytes, outputLength: 32),
          label: 'favorites.blake(root|key=chatId)',
        );
        add(
          _blake2bDigest(shared, key: chatIdBytes, outputLength: 32),
          label: 'favorites.blake(shared|key=chatId)',
        );

        // 2) HKDF(root salt, favorites info)
        add(
          await _deriveHkdf(shared, salt: rootContext, info: favContext),
          label: 'favorites.hkdf(shared,root->fav)',
        );

        // 3) HKDF(favorites salt, root info)
        add(
          await _deriveHkdf(shared, salt: favContext, info: rootContext),
          label: 'favorites.hkdf(shared,fav->root)',
        );

        // 4) Legacy SHA-derived variant for backward compatibility
        add(
          await _legacyShaDerive(shared, 'favorites:$currentUserId'),
          label: 'favorites.legacy.sha',
        );

        // 5) HKDF с пустым info/salt комбинациями
        add(
          await _deriveHkdfFlexible(shared, salt: rootContext, info: null),
          label: 'favorites.hkdf(shared,salt=root)',
        );
        add(
          await _deriveHkdfFlexible(shared, salt: null, info: rootContext),
          label: 'favorites.hkdf(shared,info=root)',
        );
        add(
          await _deriveHkdfFlexible(shared, salt: null, info: null),
          label: 'favorites.hkdf(shared,default)',
        );
        add(
          await _deriveHkdf(shared, salt: chatIdBytes, info: userIdBytes),
          label: 'favorites.hkdf(shared,chatId->userId)',
        );
        add(
          await _deriveHkdf(shared, salt: userIdBytes, info: chatIdBytes),
          label: 'favorites.hkdf(shared,userId->chatId)',
        );
        add(
          await _deriveHkdf(root, salt: chatIdBytes, info: chatIdBytes),
          label: 'favorites.hkdf(root,chatId->chatId)',
        );

        // 6) Варианты derivation от raw private key (на случай рассинхрона web-кода)
        if (myPrivate != null && myPrivate.length == 32) {
          add(
            await _deriveHkdfFlexible(myPrivate,
                salt: rootContext, info: rootContext),
            label: 'favorites.hkdf(private,root->root)',
          );
          add(
            await _legacyShaDerive(myPrivate, 'favorites:$currentUserId'),
            label: 'favorites.legacy.sha.private',
          );
        }

        // 7) Fallback: root-key, полученный при decrypt encrypted_blob в этой сессии
        if (_sessionBlobRootKey != null && _sessionBlobRootKey!.length == 32) {
          add(_sessionBlobRootKey!, label: 'favorites.blobRoot.raw');
          add(
            await _deriveHkdfFlexible(_sessionBlobRootKey!,
                salt: rootContext, info: rootContext),
            label: 'favorites.blobRoot.hkdf(root->root)',
          );
          add(
            await _legacyShaDerive(
                _sessionBlobRootKey!, 'favorites:$currentUserId'),
            label: 'favorites.blobRoot.legacy.sha',
          );
        }

        // 8) Экстремально простые/сырые варианты, которые могли родиться в web (JS):
        if (myPrivate != null) {
          add(myPrivate, label: 'favorites.raw.x25519_private');
          add(
              await crypto.Sha256()
                  .hash(myPrivate)
                  .then((h) => Uint8List.fromList(h.bytes)),
              label: 'favorites.sha256(x25519_priv)');
        }
        final pubKey = myPublicKey;
        if (pubKey != null) {
          add(_hexToBytes(pubKey), label: 'favorites.raw.x25519_public');
          add(
              await crypto.Sha256()
                  .hash(_hexToBytes(pubKey))
                  .then((h) => Uint8List.fromList(h.bytes)),
              label: 'favorites.sha256(x25519_pub)');
        }

        final edPriv = _userKeys?['ed25519_private_key']?.toString();
        if (edPriv != null && edPriv.length == 64) {
          add(_hexToBytes(edPriv).sublist(0, 32),
              label: 'favorites.raw.ed25519_private(32)');
        }

        final sharedBytes = await crypto.Sha256()
            .hash(shared)
            .then((h) => Uint8List.fromList(h.bytes));
        add(sharedBytes, label: 'favorites.sha256(shared)');

        if (_sessionBlobRootKey != null) {
          final brBytes = await crypto.Sha256()
              .hash(_sessionBlobRootKey!)
              .then((h) => Uint8List.fromList(h.bytes));
          add(brBytes, label: 'favorites.sha256(blobRoot)');
        }

        final currentUserIdStr = currentUserId;
        final hashedFav1 = await crypto.Sha256()
            .hash(utf8.encode('favorites_user_$currentUserIdStr'))
            .then((h) => Uint8List.fromList(h.bytes));
        add(hashedFav1, label: 'favorites.sha256(favorites_user)');

        final hashedFavWeb = await crypto.Sha256()
            .hash(utf8.encode('favorites'))
            .then((h) => Uint8List.fromList(h.bytes));
        add(hashedFavWeb, label: 'favorites.sha256(favorites)');

        final hashedFav2 = await crypto.Sha256()
            .hash(utf8.encode('favorites:$currentUserIdStr'))
            .then((h) => Uint8List.fromList(h.bytes));
        add(hashedFav2, label: 'favorites.sha256(favorites_colon)');

        final hashedFav3 = await crypto.Sha256()
            .hash(utf8.encode(chatId))
            .then((h) => Uint8List.fromList(h.bytes));
        add(hashedFav3, label: 'favorites.sha256(chatId)');

        final hashedChatIdHex = _hexToBytes(await crypto.Sha256()
            .hash(utf8.encode(chatId))
            .then((h) => _bytesToHex(Uint8List.fromList(h.bytes))));
        add(hashedChatIdHex, label: 'favorites.sha256_hex(chatId)');

        var favStrBytes1 =
            Uint8List.fromList(utf8.encode('favorites_user_$currentUserId'));
        if (favStrBytes1.length <= 32) {
          final padded1 = Uint8List(32);
          padded1.setAll(0, favStrBytes1);
          add(padded1, label: 'favorites.byte_pad(favorites_user)');
        }
        var favStrBytes2 =
            Uint8List.fromList(utf8.encode('favorites:$currentUserId'));
        if (favStrBytes2.length <= 32) {
          final padded2 = Uint8List(32);
          padded2.setAll(0, favStrBytes2);
          add(padded2, label: 'favorites.byte_pad(favorites_colon)');
        }

        final derivedFromSalt = await _deriveHkdfFlexible(
          shared,
          salt: _hexToBytes('d8b0ca99b31bfb3856b642f4eb357405'),
          info: null,
        );
        add(derivedFromSalt, label: 'favorites.hkdf(shared,salt=static)');

        final pwHash = await crypto.Sha256()
            .hash(utf8.encode(
                'favorites_user_$currentUserIdStr:d8b0ca99b31bfb3856b642f4eb357405'))
            .then((h) => Uint8List.fromList(h.bytes));
        add(pwHash, label: 'favorites.sha256(chatId:salt)');
        
        var pbkdf2 = crypto.Pbkdf2(macAlgorithm: crypto.Hmac.sha256(), iterations: 100000, bits: 256);
        final derivedPb1 = await pbkdf2.deriveKey(secretKey: crypto.SecretKey(utf8.encode('favorites_user_$currentUserIdStr')), nonce: _hexToBytes('d8b0ca99b31bfb3856b642f4eb357405'));
        add(Uint8List.fromList(await derivedPb1.extractBytes()), label: 'favorites.pbkdf2(favorites_user,salt)');
        
        final derivedPb2 = await pbkdf2.deriveKey(secretKey: crypto.SecretKey(utf8.encode('favorites_user_$currentUserIdStr')), nonce: utf8.encode('favorites'));
        add(Uint8List.fromList(await derivedPb2.extractBytes()), label: 'favorites.pbkdf2(favorites_user,favorites)');

        final derivedPb3 = await pbkdf2.deriveKey(secretKey: crypto.SecretKey(utf8.encode('favorites')), nonce: utf8.encode('favorites_user_$currentUserIdStr'));
        add(Uint8List.fromList(await derivedPb3.extractBytes()), label: 'favorites.pbkdf2(favorites,favorites_user)');
        
      } catch (_) {}
    }

    // personal: fallback на legacy контекст сортированных pubkey
    if (parts[0] == 'personal' && parts.length >= 3 && myPublicKey != null) {
      try {
        final currentUserId = await _getCurrentUserId();
        if (currentUserId == null || currentUserId.isEmpty) return variants;
        final otherUserId = parts[1] == currentUserId ? parts[2] : parts[1];
        final theirKeyData = await fetchUserPublicKey(otherUserId);
        final theirPub = theirKeyData?['x25519_public_key']?.toString();
        if (theirPub != null && theirPub.isNotEmpty) {
          final shared = await _computeSharedSecret(theirPub);
          add(shared, label: 'personal.shared.raw');
          add(
            await crypto.Sha256()
                .hash(shared)
                .then((h) => Uint8List.fromList(h.bytes)),
            label: 'personal.sha256(shared)',
          );

          final sortedUsers = [currentUserId, otherUserId]..sort();
          add(
            await _legacyShaDerive(
              shared,
              'personal:${sortedUsers[0]}:${sortedUsers[1]}',
            ),
            label: 'personal.legacy.sha(userIds)',
          );
          add(
            await _legacyShaDerive(shared, chatId),
            label: 'personal.legacy.sha(chatId)',
          );

          final personalSalt = _blake2bDigest(
            Uint8List.fromList(
              utf8.encode('personal:${sortedUsers[0]}:${sortedUsers[1]}'),
            ),
            outputLength: 32,
          );
          add(
            _blake2bDigest(shared, key: personalSalt, outputLength: 32),
            label: 'personal.blake(shared|salt=personal:min:max)',
          );

          add(
            _blake2bDigest(
              shared,
              key: _blake2bDigest(
                Uint8List.fromList(utf8.encode(chatId)),
                outputLength: 32,
              ),
              outputLength: 32,
            ),
            label: 'personal.blake(shared|salt=chatId)',
          );

          final context = [myPublicKey!, theirPub]..sort();
          add(
            await _legacyShaDerive(shared, context.join(':')),
            label: 'personal.legacy.sha(sortedPubKeys)',
          );
          add(
            await _deriveHkdfFlexible(shared, salt: null, info: null),
            label: 'personal.hkdf(shared,default)',
          );
        }
      } catch (_) {}
    }

    final deduped = _dedupeKeys(variants);
    if (isStableChat) {
      _candidateDecryptKeyCache[chatId] = deduped;
    }
    return deduped;
  }

  List<Uint8List> _dedupeKeys(List<Uint8List> keys) {
    final unique = <Uint8List>[];
    final seen = <String>{};

    for (final key in keys) {
      if (key.length != 32) continue;
      final fingerprint = _bytesToHex(key);
      if (seen.add(fingerprint)) {
        unique.add(key);
      }
    }

    return unique;
  }

  Future<String?> _tryDecryptWithSingleKey(
    Uint8List encryptedData,
    Uint8List key,
    String chatId,
  ) async {
    if (encryptedData.length >= 28) {
      final aes = await _decryptAesGcm(encryptedData, key, chatId: chatId);
      if (aes != null) return aes;

      final chacha =
          await _decryptChaCha20Poly1305(encryptedData, key, chatId: chatId);
      if (chacha != null) return chacha;
    }

    if (encryptedData.length >= 40) {
      final xchacha = await _decryptXChaCha20(encryptedData, key, chatId: chatId);
      if (xchacha != null) return xchacha;
    }

    return null;
  }

  Future<Uint8List> _deriveHkdf(
    Uint8List secret, {
    required Uint8List salt,
    required Uint8List info,
  }) async {
    final hkdf = crypto.Hkdf(
      hmac: crypto.Hmac.sha256(),
      outputLength: 32,
    );
    final derived = await hkdf.deriveKey(
      secretKey: crypto.SecretKey(secret),
      nonce: salt,
      info: info,
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  Future<Uint8List> _deriveHkdfFlexible(
    Uint8List secret, {
    Uint8List? salt,
    Uint8List? info,
  }) async {
    final hkdf = crypto.Hkdf(
      hmac: crypto.Hmac.sha256(),
      outputLength: 32,
    );
    final secretKey = crypto.SecretKey(secret);
    late final crypto.SecretKey derived;

    if (salt != null && info != null) {
      derived =
          await hkdf.deriveKey(secretKey: secretKey, nonce: salt, info: info);
    } else if (salt != null) {
      derived = await hkdf.deriveKey(secretKey: secretKey, nonce: salt);
    } else if (info != null) {
      derived = await hkdf.deriveKey(secretKey: secretKey, info: info);
    } else {
      derived = await hkdf.deriveKey(secretKey: secretKey);
    }

    return Uint8List.fromList(await derived.extractBytes());
  }

  Future<Uint8List> _legacyShaDerive(
      Uint8List sharedSecret, String context) async {
    final contextBytes = Uint8List.fromList(utf8.encode(context));
    final input = Uint8List(sharedSecret.length + contextBytes.length);
    input.setRange(0, sharedSecret.length, sharedSecret);
    input.setRange(sharedSecret.length, input.length, contextBytes);

    final sha256 = crypto.Sha256();
    final hash1 = await sha256.hash(input);
    final hash2 = await sha256.hash(hash1.bytes);
    return Uint8List.fromList(hash2.bytes);
  }

  Uint8List _blake2bDigest(
    Uint8List input, {
    Uint8List? key,
    int outputLength = 32,
  }) {
    final digest = Blake2bDigest(
      digestSize: outputLength,
      key: key,
    );
    digest.update(input, 0, input.length);
    final out = Uint8List(outputLength);
    digest.doFinal(out, 0);
    return out;
  }

  Uint8List? _extractFavoritesOrChatKeyFromUserKeys(String chatId) {
    final keys = _userKeys;
    if (keys == null) return null;

    Uint8List? tryDecode(dynamic value) {
      if (value == null) return null;

      if (value is Map<String, dynamic>) {
        return tryDecode(
          value['key'] ??
              value['chat_key'] ??
              value['value'] ??
              value['encryption_key'],
        );
      }

      if (value is! String) return null;
      final raw = value.trim();
      if (raw.isEmpty) return null;

      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(raw)) {
        return _hexToBytes(raw);
      }

      final b64 = _normalizeBase64Decode(raw);
      if (b64 != null && b64.length == 32) {
        return b64;
      }

      return null;
    }

    final directCandidates = <dynamic>[
      keys['favorites_key'],
      keys['favorites_chat_key'],
      keys['bookmarks_key'],
      keys['saved_messages_key'],
      keys['self_chat_key'],
      keys['chat_key'],
    ];

    for (final candidate in directCandidates) {
      final decoded = tryDecode(candidate);
      if (decoded != null) return decoded;
    }

    final mapCandidates = <dynamic>[
      keys['chat_keys'],
      keys['chatKeys'],
      keys['conversation_keys'],
      keys['keys'],
      keys['favorites_keys'],
    ];

    final currentUserId = _currentUserId;
    final mapLookupKeys = <String>{
      chatId,
      'favorites',
      'bookmarks',
      if (currentUserId != null && currentUserId.isNotEmpty)
        'favorites_user_$currentUserId',
    };

    for (final entry in mapCandidates) {
      if (entry is! Map) continue;

      for (final mapKey in mapLookupKeys) {
        final value = entry[mapKey] ??
            entry[mapKey.toLowerCase()] ??
            entry[mapKey.toUpperCase()];
        final decoded = tryDecode(value);
        if (decoded != null) return decoded;
      }
    }

    return null;
  }

  // ================================================================
  // Утилиты
  // ================================================================

  /// Безопасное декодирование base64 с нормализацией
  Uint8List? _normalizeBase64Decode(String base64Str) {
    try {
      // Нормализация: убираем пробелы, заменяем URL-safe символы
      var normalized = base64Str
          .replaceAll(' ', '')
          .replaceAll('\n', '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');

      // Добавляем padding если нужно
      final pad = normalized.length % 4;
      if (pad == 2) {
        normalized += '==';
      } else if (pad == 3) {
        normalized += '=';
      }

      return base64Decode(normalized);
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic>? _tryDecodeBase64Json(String data) {
    try {
      final bytes = _normalizeBase64Decode(data);
      if (bytes == null) return null;
      final decoded = utf8.decode(bytes);
      final json = jsonDecode(decoded);
      if (json is Map<String, dynamic>) {
        return json;
      }
    } catch (_) {}
    return null;
  }

  String? _normalizeKeyString(String? value) {
    if (value == null || value.isEmpty) return null;

    final trimmed = value.trim();
    final isHex64 = RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(trimmed);
    if (isHex64) return trimmed.toLowerCase();

    final decoded = _normalizeBase64Decode(trimmed);
    if (decoded != null && decoded.length == 32) {
      return _bytesToHex(decoded);
    }

    return null;
  }

  /// Конвертирует HEX строку в байты
  Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  /// Конвертирует байты в HEX строку
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _derivePublicFromPrivate(String privateHex) {
    final privateKey = _hexToBytes(privateHex);
    final publicKey = x25519.X25519(privateKey, x25519.basePoint);
    return _bytesToHex(publicKey);
  }

  /// Генерирует случайные байты
  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  /// Получает ID текущего пользователя
  Future<String?> _getCurrentUserId() async {
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      return _currentUserId;
    }
    debugPrint('XSEC-2: current user id is not initialized');
    return null;
  }
}
