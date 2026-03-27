import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../config/app_config.dart';
import '../../models/auth/recent_account.dart';
import '../api/api_client.dart';

/// Сервис для управления недавними аккаунтами
/// 
/// Функционал:
/// - Получение недавних аккаунтов с сервера
/// - Локальное хранение недавних аккаунтов
/// - Синхронизация между сервером и локальным хранилищем
class RecentAccountsService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage;

  /// Ключ для хранения недавних аккаунтов
  static const String _recentAccountsKey = 'recent_accounts';
  
  /// Ключ для хранения времени последней синхронизации
  static const String _lastSyncKey = 'recent_accounts_last_sync';

  RecentAccountsService({
    required ApiClient apiClient,
    FlutterSecureStorage? storage,
  })  : _apiClient = apiClient,
        _storage = storage ?? const FlutterSecureStorage();

  /// Получение недавних аккаунтов с сервера
  Future<RecentAccountsResponse> getRecentAccounts() async {
    try {
      final response = await _apiClient.get(AppConfig.authRecentAccounts);
      return RecentAccountsResponse.fromJson(response.data);
    } catch (e) {
      debugPrint('Error getting recent accounts: $e');
      return RecentAccountsResponse(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Получение недавних аккаунтов из локального хранилища
  Future<List<RecentAccount>> getLocalRecentAccounts() async {
    try {
      final jsonString = await _storage.read(key: _recentAccountsKey);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .map((e) => RecentAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error reading local recent accounts: $e');
      return [];
    }
  }

  /// Сохранение аккаунта локально
  Future<void> saveAccountLocally(RecentAccount account) async {
    try {
      final accounts = await getLocalRecentAccounts();
      
      // Удаляем существующий аккаунт с таким же ID
      accounts.removeWhere((a) => a.id == account.id);
      
      // Добавляем аккаунт в начало списка
      accounts.insert(0, account);
      
      // Ограничиваем количество аккаунтов (максимум 5)
      final limitedAccounts = accounts.take(5).toList();
      
      // Сохраняем
      await _saveAccounts(limitedAccounts);
    } catch (e) {
      debugPrint('Error saving account locally: $e');
    }
  }

  /// Удаление аккаунта из локального хранилища
  Future<void> removeAccountLocally(int userId) async {
    try {
      final accounts = await getLocalRecentAccounts();
      accounts.removeWhere((a) => a.id == userId);
      await _saveAccounts(accounts);
    } catch (e) {
      debugPrint('Error removing account locally: $e');
    }
  }

  /// Очистка всех локальных аккаунтов
  Future<void> clearLocalAccounts() async {
    try {
      await _storage.delete(key: _recentAccountsKey);
      await _storage.delete(key: _lastSyncKey);
    } catch (e) {
      debugPrint('Error clearing local accounts: $e');
    }
  }

  /// Синхронизация с сервером
  /// 
  /// Алгоритм:
  /// 1. Получаем аккаунты с сервера
  /// 2. Получаем локальные аккаунты
  /// 3. Объединяем, убирая дубликаты
  /// 4. Удаляем аккаунты, которых нет на сервере (были удалены)
  Future<List<RecentAccount>> syncWithServer() async {
    try {
      // Получаем данные с сервера
      final serverResponse = await getRecentAccounts();
      if (!serverResponse.success) {
        // Если ошибка, возвращаем локальные данные
        return await getLocalRecentAccounts();
      }

      final serverAccounts = serverResponse.recentAccounts;
      final localAccounts = await getLocalRecentAccounts();

      // Создаём мапу для быстрого поиска
      final serverIds = serverAccounts.map((a) => a.id).toSet();

      // Фильтруем локальные аккаунты, оставляя только те, что есть на сервере
      final validLocalAccounts = localAccounts
          .where((a) => serverIds.contains(a.id))
          .toList();

      // Объединяем: серверные данные приоритетнее
      final mergedMap = <int, RecentAccount>{};
      
      // Сначала добавляем локальные (если есть дополнительные данные)
      for (final account in validLocalAccounts) {
        mergedMap[account.id] = account;
      }
      
      // Затем обновляем данными с сервера
      for (final account in serverAccounts) {
        mergedMap[account.id] = account;
      }

      // Преобразуем в список и сортируем по lastLogin
      final mergedAccounts = mergedMap.values.toList()
        ..sort((a, b) => b.lastLogin.compareTo(a.lastLogin));

      // Сохраняем
      await _saveAccounts(mergedAccounts);
      
      // Сохраняем время синхронизации
      await _storage.write(
        key: _lastSyncKey,
        value: DateTime.now().toIso8601String(),
      );

      return mergedAccounts;
    } catch (e) {
      debugPrint('Error syncing with server: $e');
      return await getLocalRecentAccounts();
    }
  }

  /// Проверка, нужно ли синхронизировать
  Future<bool> needsSync() async {
    try {
      final lastSyncStr = await _storage.read(key: _lastSyncKey);
      if (lastSyncStr == null) return true;

      final lastSync = DateTime.parse(lastSyncStr);
      final now = DateTime.now();
      
      // Синхронизируем не чаще раза в час
      return now.difference(lastSync).inHours >= 1;
    } catch (e) {
      return true;
    }
  }

  /// Получение времени последней синхронизации
  Future<DateTime?> getLastSyncTime() async {
    try {
      final lastSyncStr = await _storage.read(key: _lastSyncKey);
      if (lastSyncStr == null) return null;
      return DateTime.parse(lastSyncStr);
    } catch (e) {
      return null;
    }
  }

  /// Сохранение списка аккаунтов
  Future<void> _saveAccounts(List<RecentAccount> accounts) async {
    final jsonList = accounts.map((a) => a.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await _storage.write(key: _recentAccountsKey, value: jsonString);
  }
}
