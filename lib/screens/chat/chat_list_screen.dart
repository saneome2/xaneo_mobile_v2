import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/chat/chat_model.dart';
import '../../services/api/api_client.dart';
import '../../services/auth/token_storage.dart';
import '../../services/chat/chat_service.dart';
import '../../services/chat/chat_local_repository.dart';
import '../../services/chat/chat_websocket_service.dart';
import '../../services/crypto/crypto_service.dart';
import '../../styles/app_styles.dart';
import '../../widgets/common/avatar_widget.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with WidgetsBindingObserver {
  late final ChatService _chatService;
  late final LocalChatRepository _localChatRepo;
  late final ChatWebSocketService _chatWebSocketService;
  bool _isLoadingSync = true;
  bool _isSyncInProgress = false;
  String? _error;
  Timer? _syncTimer;
  Timer? _relativeTimeTimer;
  StreamSubscription<Map<String, dynamic>>? _wsEventsSub;
  String? _connectedWsChatId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Инициализируем сервисы синхронно для работы StreamBuilder в первом кадре
    _localChatRepo = context.read<LocalChatRepository>();
    _chatService = ChatService(apiClient: context.read<ApiClient>());
    _chatWebSocketService = ChatWebSocketService(tokenStorage: TokenStorage());
    _wsEventsSub = _chatWebSocketService.events.listen(_handleWsEvent);
    
    // Запускаем синхронизацию сети после сборки первого кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncChats();
      _startAutoSync();
      _startRelativeTimeTicker();
    });
  }

  @override
  void dispose() {
    _wsEventsSub?.cancel();
    _chatWebSocketService.dispose();
    _syncTimer?.cancel();
    _relativeTimeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncChats(silent: true);
      _startRelativeTimeTicker();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _relativeTimeTimer?.cancel();
    }
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _syncChats(silent: true);
    });
  }

  void _startRelativeTimeTicker() {
    _relativeTimeTimer?.cancel();
    _relativeTimeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  /// Фоновая/первичная синхронизация чатов с API -> БД
  Future<void> _syncChats({bool silent = false}) async {
    if (_isSyncInProgress) return;
    _isSyncInProgress = true;

    if (!silent && mounted) {
      setState(() {
        _isLoadingSync = true;
        _error = null;
      });
    }

    try {
      final chats = await _chatService.getChats();
      if (!mounted) return;
      
      final cryptoService = context.read<CryptoService>();
      
      final decryptedChats = await Future.wait(
        chats.map((chat) async {
          if (chat.lastMessage != null && 
              (chat.isEncrypted || _looksLikeJsonPayload(chat.lastMessage))) {
            final decrypted = await cryptoService.decryptChatMessage(
              chat.lastMessage!, 
              chat.id,
            );
            if (decrypted != null) {
              return ChatModel(
                id: chat.id,
                name: chat.name,
                avatar: chat.avatar,
                avatarGradient: chat.avatarGradient,
                lastMessage: decrypted,
                lastMessageTime: chat.lastMessageTime,
                unreadCount: chat.unreadCount,
                isGroup: chat.isGroup,
                isChannel: chat.isChannel,
                isPersonal: chat.isPersonal,
                isFavorites: chat.isFavorites,
                otherUser: chat.otherUser,
                isEncrypted: false,
              );
            }
          }
          return chat;
        }),
      );
      
      // Сохраняем расшифрованные чаты в локальную БД
      await _localChatRepo.saveChatsBatch(decryptedChats);
      await _ensureWsConnected(decryptedChats);
      
      if (mounted && _isLoadingSync) {
        setState(() {
          _isLoadingSync = false;
        });
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingSync = false;
        });
      }
    } finally {
      _isSyncInProgress = false;
    }
  }

  Future<void> _ensureWsConnected(List<ChatModel> chats) async {
    if (chats.isEmpty) return;

    String? candidateChatId;
    for (final chat in chats) {
      if (chat.isFavorites || chat.id == 'favorites') {
        candidateChatId = chat.id;
        break;
      }
    }

    candidateChatId ??= chats.first.id;

    if (_connectedWsChatId == candidateChatId) return;
    _connectedWsChatId = candidateChatId;
    await _chatWebSocketService.connect(candidateChatId);
  }

  Future<void> _handleWsEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();
    if (type == null || type.isEmpty) return;

    switch (type) {
      case 'chat_list_update':
        final chatPayload = event['chat'];
        if (chatPayload is Map) {
          await _applyChatPreviewUpdate(chatPayload.cast<String, dynamic>());
        }
        break;
      case 'encrypted_message':
        await _applyEncryptedMessageEvent(event);
        break;
      case 'chat_deleted':
        final chatId = event['chat_id']?.toString();
        if (chatId != null && chatId.isNotEmpty) {
          await _localChatRepo.deleteChatByServerId(chatId);
        }
        break;
      case 'chats_reorder_required':
      case 'history_cleared':
      case 'message_deleted':
      case 'message_edited':
        _syncChats(silent: true);
        break;
      default:
        break;
    }
  }

  Future<void> _applyChatPreviewUpdate(Map<String, dynamic> payload) async {
    final chatJson = <String, dynamic>{
      'id': payload['id'] ?? payload['chat_id'],
      'chat_id': payload['chat_id'] ?? payload['id'],
      'title': payload['title'] ?? payload['name'],
      'avatar_url': payload['avatar_url'],
      'last_message': payload['last_message'],
      'last_message_time': payload['last_message_time'],
      'unread_count': payload['unread_count'],
    };

    var incoming = ChatModel.fromJson(chatJson);
    incoming = await _decryptPreviewIfNeeded(incoming);

    final existing = await _localChatRepo.getChatByServerId(incoming.id);
    if (existing != null) {
      incoming = ChatModel(
        id: incoming.id,
        name: incoming.name.isNotEmpty && incoming.name != 'Unknown'
            ? incoming.name
            : existing.name,
        avatar: incoming.avatar ?? existing.avatar,
        avatarGradient: incoming.avatarGradient ?? existing.avatarGradient,
        lastMessage: incoming.lastMessage,
        lastMessageTime: incoming.lastMessageTime,
        unreadCount: incoming.unreadCount,
        isGroup: incoming.isGroup || existing.isGroup,
        isChannel: incoming.isChannel || existing.isChannel,
        isPersonal: incoming.isPersonal || existing.isPersonal,
        isFavorites: incoming.isFavorites || existing.isFavorites,
        otherUser: incoming.otherUser ?? existing.otherUser,
        isEncrypted: incoming.isEncrypted,
      );
    }

    await _localChatRepo.saveChat(incoming);
  }

  Future<void> _applyEncryptedMessageEvent(Map<String, dynamic> event) async {
    final chatId = event['chat_id']?.toString();
    final encryptedText = event['encrypted_text']?.toString();

    if (chatId == null || chatId.isEmpty || encryptedText == null || encryptedText.isEmpty) {
      return;
    }

    final existing = await _localChatRepo.getChatByServerId(chatId);
    if (existing == null) {
      _syncChats(silent: true);
      return;
    }

    final cryptoService = context.read<CryptoService>();
    final decrypted = await cryptoService.decryptChatMessage(encryptedText, chatId);

    final createdAt = _parseApiDateTime(event['created_at']);

    final updated = ChatModel(
      id: existing.id,
      name: existing.name,
      avatar: existing.avatar,
      avatarGradient: existing.avatarGradient,
      lastMessage: decrypted ?? encryptedText,
      lastMessageTime: createdAt ?? existing.lastMessageTime,
      unreadCount: (event['unread_count'] as num?)?.toInt() ?? existing.unreadCount,
      isGroup: existing.isGroup,
      isChannel: existing.isChannel,
      isPersonal: existing.isPersonal,
      isFavorites: existing.isFavorites,
      otherUser: existing.otherUser,
      isEncrypted: decrypted == null,
    );

    await _localChatRepo.saveChat(updated);
  }

  Future<ChatModel> _decryptPreviewIfNeeded(ChatModel chat) async {
    final message = chat.lastMessage;
    if (message == null || message.isEmpty) return chat;

    final cryptoService = context.read<CryptoService>();
    final shouldDecrypt = chat.isEncrypted ||
        _looksLikeJsonPayload(message) ||
        cryptoService.isEncryptedMessage(message);

    if (!shouldDecrypt) return chat;

    final decrypted = await cryptoService.decryptChatMessage(message, chat.id);
    if (decrypted == null) return chat;

    return ChatModel(
      id: chat.id,
      name: chat.name,
      avatar: chat.avatar,
      avatarGradient: chat.avatarGradient,
      lastMessage: decrypted,
      lastMessageTime: chat.lastMessageTime,
      unreadCount: chat.unreadCount,
      isGroup: chat.isGroup,
      isChannel: chat.isChannel,
      isPersonal: chat.isPersonal,
      isFavorites: chat.isFavorites,
      otherUser: chat.otherUser,
      isEncrypted: false,
    );
  }

  DateTime? _parseApiDateTime(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) {
      return value.isUtc ? value.toLocal() : value;
    }

    if (value is int) {
      final isMilliseconds = value > 100000000000;
      return isMilliseconds
          ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
              .toLocal();
    }

    if (value is double) {
      return _parseApiDateTime(value.toInt());
    }

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;

      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) {
        return parsed.isUtc ? parsed.toLocal() : parsed;
      }

      final asInt = int.tryParse(trimmed);
      if (asInt != null) {
        return _parseApiDateTime(asInt);
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Заголовок
          Padding(
            padding: AppStyles.screenPadding.copyWith(top: 16),
            child: Row(
              children: [
                Text('Чаты', style: AppStyles.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.search, color: AppStyles.textPrimaryColor),
                  onPressed: () {
                    // TODO: Поиск
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: AppStyles.textPrimaryColor),
                  onPressed: () {
                    // TODO: Новый чат
                  },
                ),
              ],
            ),
          ),

          // Список чатов или состояние загрузки
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return StreamBuilder<List<ChatModel>>(
      stream: _localChatRepo.watchAllChats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && _isLoadingSync) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppStyles.textPrimaryColor,
            ),
          );
        }

        final chats = snapshot.data ?? [];

        if (chats.isEmpty && _error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: AppStyles.errorColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'Ошибка загрузки чатов',
                  style: AppStyles.titleLarge.copyWith(
                    color: AppStyles.textMutedColor,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _syncChats,
                  child: const Text('Повторить'),
                ),
              ],
            ),
          );
        }

        if (chats.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: AppStyles.textMutedColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'Нет чатов',
                  style: AppStyles.titleLarge.copyWith(
                    color: AppStyles.textMutedColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Начните новый разговор',
                  style: AppStyles.bodyMedium.copyWith(
                    color: AppStyles.textMutedColor,
                  ),
                ),
              ],
            ),
          );
        }

        // Сортируем чаты: Избранное всегда первым
        final sortedChats = List<ChatModel>.from(chats);
        sortedChats.sort((a, b) {
          // Если a - Избранное (favorites), оно первое
      final aName = a.name;
      final bName = b.name;
      if (a.isFavorites || a.id == 'favorites' || aName == 'Избранное') return -1;
      if (b.isFavorites || b.id == 'favorites' || bName == 'Избранное') return 1;
      // Иначе по времени последнего сообщения (новые сверху)
      if (a.lastMessageTime == null && b.lastMessageTime == null) return 0;
      if (a.lastMessageTime == null) return 1;
      if (b.lastMessageTime == null) return -1;
      return b.lastMessageTime!.compareTo(a.lastMessageTime!);
    });

    return RefreshIndicator(
      onRefresh: _syncChats,
      color: AppStyles.textPrimaryColor,
      backgroundColor: AppStyles.inputBackgroundColor,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: sortedChats.length,
        itemBuilder: (context, index) {
          return _buildChatItem(sortedChats[index]);
        },
      ),
    );
      },
    );
  }

  Widget _buildChatItem(ChatModel chat) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // TODO: Открыть чат
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              // Аватар
              _buildAvatar(chat),
              const SizedBox(width: 14),

              // Информация о чате
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Иконка для группы/канала
                        if (chat.isGroup || chat.isChannel) ...[
                          Icon(
                            chat.isGroup ? Icons.group : Icons.campaign,
                            size: 14,
                            color: AppStyles.textMutedColor,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            chat.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppStyles.textPrimaryColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (chat.lastMessage != null || chat.isGroup || chat.isChannel) ...[
              const SizedBox(height: 4),
              _buildMessageText(chat),
            ],
                  ],
                ),
              ),

        // Время и счётчик непрочитанных
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (chat.lastMessageTime != null)
              Text(
                chat.formattedTime,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppStyles.textMutedColor,
                ),
              ),
            if (chat.lastMessageTime != null && chat.unreadCount > 0)
              const SizedBox(height: 4),
            if (chat.unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppStyles.textPrimaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppStyles.backgroundColor,
                  ),
                ),
              ),
          ],
        ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(ChatModel chat) {
  // Определяем - есть ли реальный аватар (http/https URL)
  final hasRealAvatar = chat.avatar != null &&
      chat.avatar!.isNotEmpty &&
      (chat.avatar!.startsWith('http') || chat.avatar!.startsWith('https'));

  // Для Избранного показываем иконку закладки (bookmark)
  final icon = chat.isFavorites ? Icons.bookmark_rounded : null;

  // Используем AvatarWidget с градиентом
  return AvatarWidget(
    avatar: chat.avatar,
    avatarGradient: chat.avatarGradient,
    hasAvatar: hasRealAvatar,
    username: chat.name,
    size: 50,
    icon: icon,
  );
}

  Widget _buildMessageText(ChatModel chat) {
    return Text(
      chat.displayMessage,
      style: const TextStyle(
        fontSize: 14,
        color: AppStyles.textMutedColor,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  bool _looksLikeJsonPayload(String? message) {
    if (message == null || message.isEmpty) return false;
    final trimmed = message.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) return true;
    final hasNonce = RegExp(r'nonce\s*[:=]').hasMatch(trimmed);
    final hasCipher = RegExp(r'ciphertext\s*[:=]|encrypted_data\s*[:=]').hasMatch(trimmed);
    return hasNonce && hasCipher;
  }
}