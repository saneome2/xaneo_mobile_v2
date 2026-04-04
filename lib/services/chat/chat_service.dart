import 'package:dio/dio.dart';
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
      print('Error fetching chats: $e');
      return [];
    }
  }
}