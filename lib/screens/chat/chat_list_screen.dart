import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/chat/chat_model.dart';
import '../../providers/auth_provider.dart';
import '../../models/auth/user_model.dart';
import '../../services/api/api_client.dart';
import '../../services/chat/chat_service.dart';
import '../../services/crypto/crypto_service.dart';
import '../../styles/app_styles.dart';
import '../../widgets/common/avatar_widget.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late final ChatService _chatService;
  List<ChatModel> _chats = [];
  bool _isLoading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    // Инициализируем сервис через ApiClient из провайдера
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initChatService();
    });
  }

  void _initChatService() {
    final apiClient = context.read<ApiClient>();
    _chatService = ChatService(apiClient: apiClient);
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final chats = await _chatService.getChats();
      if (mounted) {
        setState(() {
          _chats = chats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
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
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppStyles.textPrimaryColor,
        ),
      );
    }

    if (_error != null) {
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
              onPressed: _loadChats,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_chats.isEmpty) {
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
    final sortedChats = List<ChatModel>.from(_chats);
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
      onRefresh: _loadChats,
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
                    if (chat.lastMessage != null) ...[
              const SizedBox(height: 4),
              _buildMessageText(chat),
            ],
                  ],
                ),
              ),

              // Время и счётчик непрочитанных
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (chat.lastMessageTime != null) ...[
                    Text(
                      chat.formattedTime,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppStyles.textMutedColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
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

  /// Построить текст сообщения с дешифрованием
  Widget _buildMessageText(ChatModel chat) {
    // Если сообщение похоже на зашифрованный payload - пробуем расшифровать
    final shouldTryDecrypt = chat.isEncrypted || _looksLikeJsonPayload(chat.lastMessage);
    if (shouldTryDecrypt) {
      final cryptoService = context.read<CryptoService>();
      
      return FutureBuilder<String?>(
        future: _tryDecryptMessage(cryptoService, chat),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Text(
              snapshot.data!,
              style: const TextStyle(
                fontSize: 14,
                color: AppStyles.textMutedColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          }

          // Не удалось расшифровать
          return const Text(
            '🔒 Зашифрованное сообщение',
            style: TextStyle(
              fontSize: 14,
              color: AppStyles.textMutedColor,
              fontStyle: FontStyle.italic,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        },
      );
    }

    // Обычное сообщение
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

  /// Попытка расшифровать сообщение.
  /// Ключ выбирается в CryptoService по типу чата:
  /// personal/favorites через ECDH-деривацию, group/channel через epoch+legacy fallback.
  Future<String?> _tryDecryptMessage(CryptoService cryptoService, ChatModel chat) async {
    if (chat.lastMessage == null) return null;

    return cryptoService.decryptChatMessage(chat.lastMessage!, chat.id);
  }
}
