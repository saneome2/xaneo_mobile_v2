import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../providers/auth_provider.dart';
import 'chat_websocket_service.dart';
import '../api/api_client.dart';

/// Глобальный сервис присутствия
/// 
/// Отвечает за:
/// - Поддержание WebSocket-соединения с сервером, пока приложение активно на переднем плане
/// - Корректное закрытие сокета при сворачивании приложения в фон
/// - Предоставление общего потока событий для экранов списка чатов и др.
class PresenceService with WidgetsBindingObserver {
  final AuthProvider _authProvider;
  final ChatWebSocketService _chatWebSocketService;
  bool _initialized = false;

  PresenceService({
    required AuthProvider authProvider,
    required ApiClient apiClient,
    ChatWebSocketService? chatWebSocketService,
  })  : _authProvider = authProvider,
        _chatWebSocketService = chatWebSocketService ?? ChatWebSocketService(apiClient: apiClient);

  /// Поток всех событий, приходящих из WebSocket
  Stream<Map<String, dynamic>> get events => _chatWebSocketService.events;

  /// Статус подключения к WebSocket
  ValueNotifier<bool> get isConnected => _chatWebSocketService.isConnected;

  /// Инициализация сервиса
  void init() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _authProvider.addListener(_onAuthChanged);
    _updateConnection();
  }

  /// Уничтожение сервиса
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authProvider.removeListener(_onAuthChanged);
    _chatWebSocketService.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('PresenceService: App lifecycle state changed to $state');
    _updateConnection();
  }

  void _onAuthChanged() {
    _updateConnection();
  }

  void _updateConnection() {
    final isAuthenticated = _authProvider.isAuthenticated;
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    
    // Если состояние еще не определено (первый кадр), считаем, что мы на переднем плане (resumed)
    final isForeground = lifecycleState == null || lifecycleState == AppLifecycleState.resumed;

    debugPrint('PresenceService: updateConnection. Auth=$isAuthenticated, Foreground=$isForeground');

    if (isAuthenticated && isForeground) {
      _connect();
    } else {
      _disconnect();
    }
  }

  void _connect() {
    final user = _authProvider.user;
    if (user == null) {
      debugPrint('PresenceService: cannot connect, user is null');
      return;
    }
    // Подключаемся к специальному каналу 'favorites_user_${user.id}', который есть у каждого пользователя по умолчанию.
    // Это сохраняет сокет открытым и отмечает пользователя "в сети" на бэкенде.
    final favoritesChatId = 'favorites_user_${user.id}';
    debugPrint('PresenceService: connecting to presence websocket with ID $favoritesChatId...');
    _chatWebSocketService.connect(favoritesChatId);
  }

  void _disconnect() {
    debugPrint('PresenceService: disconnecting from presence websocket...');
    _chatWebSocketService.disconnect();
  }
}
