import 'package:flutter/foundation.dart';
import '../../config/app_config.dart';
import '../../models/chat/chat_model.dart';
import '../api/api_client.dart';

/// Сервис для работы с чатами
class ChatService {
  final ApiClient _apiClient;

  ChatService({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Получить список чатов пользователя
  Future<List<ChatModel>> getChats() async {
    try {
      final response = await _apiClient.get(AppConfig.chatsList);
      
      if (response.statusCode == 200 && response.data != null) {
        // API возвращает {chats: [...]} или [...]
        List<dynamic> data = [];
        if (response.data is List) {
          data = response.data as List;
        } else if (response.data is Map) {
          final mapData = response.data as Map<String, dynamic>;
          data = mapData['chats'] ?? mapData['results'] ?? [];
        }
        
        return data.map((json) => ChatModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      
      return [];
    } catch (e) {
      // Логируем ошибку
      debugPrint('Error fetching chats: $e');
      return [];
    }
  }

  /// Получить список зашифрованных сообщений для конкретного чата с пагинацией (limit/offset)
  Future<Map<String, dynamic>?> getEncryptedMessages(
    String chatId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _apiClient.get(
        '/encrypted-messages/',
        queryParameters: {
          'chat_id': chatId,
          'limit': limit,
          'offset': offset,
        },
      );
      
      if (response.statusCode == 200 && response.data != null) {
        if (response.data is Map) {
          return response.data as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching encrypted messages for chat $chatId: $e');
      return null;
    }
  }

  /// Отметить сообщения в чате как прочитанные
  Future<bool> markMessagesAsRead(String chatId) async {
    try {
      final response = await _apiClient.post(
        '/messages/mark-read/',
        data: {'chat_id': chatId},
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error marking messages as read for chat $chatId: $e');
      return false;
    }
  }
}