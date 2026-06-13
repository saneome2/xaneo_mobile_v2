import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/chat/chat_model.dart';
import '../../services/api/api_client.dart';
import '../../services/chat/chat_service.dart';
import '../../services/chat/chat_local_repository.dart';
import '../../services/chat/presence_service.dart';
import '../../services/crypto/crypto_service.dart';
import '../../styles/app_styles.dart';
import '../../widgets/common/avatar_widget.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with WidgetsBindingObserver {
  late final ChatService _chatService;
  late final LocalChatRepository _localChatRepo;
  bool _isLoadingSync = true;
  bool _isSyncInProgress = false;
  String? _error;
  Timer? _relativeTimeTimer;
  StreamSubscription<Map<String, dynamic>>? _wsEventsSub;
  bool _wasConnected = false;

  late final PresenceService _presenceService;

  // Поиск и Фильтрация
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _selectedCategory = 'all'; // 'all', 'personal', 'groups', 'channels', 'favorites'
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Инициализируем сервисы синхронно для работы StreamBuilder в первом кадре
    _localChatRepo = context.read<LocalChatRepository>();
    _chatService = ChatService(apiClient: context.read<ApiClient>());
    _presenceService = context.read<PresenceService>();
    _wasConnected = _presenceService.isConnected.value;
    _presenceService.isConnected.addListener(_onWsConnectionChanged);
    _wsEventsSub = _presenceService.events.listen(_handleWsEvent);
    
    // Запускаем синхронизацию сети после сборки первого кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncChats();
      _startRelativeTimeTicker();
    });
  }

  void _onWsConnectionChanged() {
    final isConnected = _presenceService.isConnected.value;
    if (isConnected && !_wasConnected) {
      // Синхронизация при восстановлении соединения (reconnect)
      _syncChats(silent: true);
    }
    _wasConnected = isConnected;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _presenceService.isConnected.removeListener(_onWsConnectionChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _wsEventsSub?.cancel();
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
    
    if (mounted) {
      setState(() {
        _isSyncInProgress = true;
        if (!silent) {
          _isLoadingSync = true;
          _error = null;
        }
      });
    } else {
      _isSyncInProgress = true;
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
      if (mounted) {
        setState(() {
          _isSyncInProgress = false;
        });
      } else {
        _isSyncInProgress = false;
      }
    }
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
    return Container(
      color: AppStyles.backgroundColor,
      child: Stack(
        children: [
          // 1. Список чатов (в фоне, скроллится под хедер)
          Positioned.fill(
            child: _buildContent(),
          ),

          // 2. Pinned Frosted Glass Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildPinnedGlassHeader(),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedGlassHeader() {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.06),
                width: 1,
              ),
            ),
          ),
          padding: EdgeInsets.only(
            top: statusBarHeight + 14,
            bottom: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Строка заголовка и поиска
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: 44,
                  child: _buildHeaderContent(),
                ),
              ),
              const SizedBox(height: 14),
              // Фильтры категорий
              _buildCategoryFilters(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderContent() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Обычный заголовок
        AnimatedOpacity(
          opacity: _isSearching ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: _isSearching,
            child: Row(
              children: [
                _buildTitleText(),
                const Spacer(),
                _buildHeaderButton(
                  child: const FaIcon(
                    FontAwesomeIcons.magnifyingGlass,
                    color: AppStyles.textPrimaryColor,
                    size: 14,
                  ),
                  onTap: () {
                    setState(() {
                      _isSearching = true;
                    });
                    _searchFocusNode.requestFocus();
                  },
                ),
                const SizedBox(width: 8),
                _buildHeaderButton(
                  child: const FaIcon(
                    FontAwesomeIcons.plus,
                    color: AppStyles.textPrimaryColor,
                    size: 15,
                  ),
                  onTap: () {
                    // TODO: Новый чат
                  },
                ),
              ],
            ),
          ),
        ),

        // Поисковая строка, выдвигающаяся справа
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          left: _isSearching ? 0 : MediaQuery.of(context).size.width - 40,
          right: 0,
          top: 0,
          bottom: 0,
          child: AnimatedOpacity(
            opacity: _isSearching ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: !_isSearching,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: FaIcon(
                              FontAwesomeIcons.magnifyingGlass,
                              color: AppStyles.textMutedColor,
                              size: 14,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                              cursorColor: Colors.white,
                              decoration: const InputDecoration(
                                hintText: 'Поиск чатов...',
                                hintStyle: TextStyle(
                                  color: AppStyles.textMutedColor,
                                  fontSize: 15,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 11),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val;
                                });
                              },
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, color: AppStyles.textMutedColor, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildHeaderButton(
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    onTap: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                      setState(() {
                        _searchQuery = '';
                        _isSearching = false;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderButton({
    required Widget child,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.05),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          splashColor: Colors.white.withOpacity(0.08),
          highlightColor: Colors.white.withOpacity(0.04),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildTitleText() {
    String title = 'Чаты';
    Color textColor = AppStyles.textPrimaryColor;
    
    if (_isSyncInProgress) {
      title = 'Обновление...';
      textColor = AppStyles.textSecondaryColor;
    } else if (!_presenceService.isConnected.value) {
      title = 'Соединение...';
      textColor = AppStyles.textSecondaryColor;
    }
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: Text(
        title,
        key: ValueKey<String>(title),
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textColor,
          fontFamily: AppStyles.fontFamily,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    final categories = [
      {'id': 'all', 'label': 'Все'},
      {'id': 'personal', 'label': 'Личные'},
      {'id': 'groups', 'label': 'Группы'},
      {'id': 'channels', 'label': 'Каналы'},
      {'id': 'favorites', 'label': 'Избранное'},
    ];

    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _selectedCategory == cat['id'];
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = cat['id']!;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  cat['label']!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? Colors.black : AppStyles.textSecondaryColor,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    final topOffset = MediaQuery.of(context).padding.top + 122.0;

    return StreamBuilder<List<ChatModel>>(
      stream: _localChatRepo.watchAllChats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && _isLoadingSync) {
          return Padding(
            padding: EdgeInsets.only(top: topOffset),
            child: const Center(
              child: CircularProgressIndicator(
                color: AppStyles.textPrimaryColor,
              ),
            ),
          );
        }

        final chats = snapshot.data ?? [];

        if (chats.isEmpty && _error != null) {
          return Padding(
            padding: EdgeInsets.only(top: topOffset),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const FaIcon(
                    FontAwesomeIcons.circleExclamation,
                    size: 50,
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
            ),
          );
        }

        var filteredChats = chats;

        // 1. Фильтрация по категории
        if (_selectedCategory == 'personal') {
          filteredChats = filteredChats.where((c) => c.isPersonal && !c.isFavorites).toList();
        } else if (_selectedCategory == 'groups') {
          filteredChats = filteredChats.where((c) => c.isGroup).toList();
        } else if (_selectedCategory == 'channels') {
          filteredChats = filteredChats.where((c) => c.isChannel).toList();
        } else if (_selectedCategory == 'favorites') {
          filteredChats = filteredChats.where((c) => c.isFavorites || c.id == 'favorites' || c.name == 'Избранное').toList();
        }

        // 2. Фильтрация по поисковому запросу
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          filteredChats = filteredChats.where((c) {
            final nameMatch = c.name.toLowerCase().contains(query);
            final msgMatch = c.lastMessage?.toLowerCase().contains(query) ?? false;
            return nameMatch || msgMatch;
          }).toList();
        }

        if (filteredChats.isEmpty) {
          return Padding(
            padding: EdgeInsets.only(top: topOffset),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const FaIcon(
                    FontAwesomeIcons.message,
                    size: 50,
                    color: AppStyles.textMutedColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isNotEmpty ? 'Ничего не найдено' : 'Нет чатов',
                    style: AppStyles.titleLarge.copyWith(
                      color: AppStyles.textMutedColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _searchQuery.isNotEmpty 
                        ? 'Попробуйте изменить запрос' 
                        : 'Начните новый разговор',
                    style: AppStyles.bodyMedium.copyWith(
                      color: AppStyles.textMutedColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Сортируем чаты: Избранное всегда первым
        final sortedChats = List<ChatModel>.from(filteredChats);
        sortedChats.sort((a, b) {
          final aName = a.name;
          final bName = b.name;
          if (a.isFavorites || a.id == 'favorites' || aName == 'Избранное') return -1;
          if (b.isFavorites || b.id == 'favorites' || bName == 'Избранное') return 1;
          
          if (a.lastMessageTime == null && b.lastMessageTime == null) return 0;
          if (a.lastMessageTime == null) return 1;
          if (b.lastMessageTime == null) return -1;
          return b.lastMessageTime!.compareTo(a.lastMessageTime!);
        });

        return RefreshIndicator(
          onRefresh: _syncChats,
          edgeOffset: topOffset - 24.0,
          color: AppStyles.textPrimaryColor,
          backgroundColor: AppStyles.inputBackgroundColor,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              top: topOffset,
              bottom: 100, // Отступ под нижнюю панель навигации
            ),
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
    return TweenAnimationBuilder<double>(
      key: ValueKey(chat.id),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1.0 - value)),
            child: child,
          ),
        );
      },
      child: Column(
        children: [
          _buildChatItemContent(chat),
          Divider(
            color: Colors.white.withOpacity(0.04),
            height: 1,
            indent: 84,
          ),
        ],
      ),
    );
  }

  Widget _buildChatItemContent(ChatModel chat) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ChatScreen(chat: chat),
            ),
          );
        },
        splashColor: Colors.white.withOpacity(0.03),
        highlightColor: Colors.white.withOpacity(0.01),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              // Аватар со статусом присутствия
              _buildAvatarWithPresence(chat),
              const SizedBox(width: 14),

              // Информация о чате
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Иконка для группы/канала/избранного
                        if (chat.isFavorites) ...[
                          FaIcon(
                            FontAwesomeIcons.solidBookmark,
                            size: 11,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          const SizedBox(width: 5),
                        ] else if (chat.isGroup) ...[
                          FaIcon(
                            FontAwesomeIcons.users,
                            size: 11,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          const SizedBox(width: 5),
                        ] else if (chat.isChannel) ...[
                          FaIcon(
                            FontAwesomeIcons.bullhorn,
                            size: 11,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          const SizedBox(width: 5),
                        ] else if (chat.isPersonal) ...[
                          FaIcon(
                            FontAwesomeIcons.shieldHalved,
                            size: 11,
                            color: Colors.white.withOpacity(0.4),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            chat.name,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: chat.unreadCount > 0 ? FontWeight.w600 : FontWeight.w500,
                              color: AppStyles.textPrimaryColor,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildMessageText(chat),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Время и счётчик непрочитанных
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (chat.lastMessageTime != null)
                    Text(
                      chat.formattedTime,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: chat.unreadCount > 0 ? FontWeight.w500 : FontWeight.w400,
                        color: chat.unreadCount > 0
                            ? Colors.white
                            : AppStyles.textMutedColor,
                      ),
                    ),
                  if (chat.unreadCount > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      decoration: BoxDecoration(
                        color: AppStyles.textPrimaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppStyles.backgroundColor,
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 28),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarWithPresence(ChatModel chat) {
    final isOnline = chat.isPersonal &&
        chat.otherUser != null &&
        (chat.otherUser!['is_online'] == true || chat.otherUser!['online'] == true);

    return Stack(
      children: [
        _buildAvatar(chat),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFF4ADE80), // Премиальный зеленый цвет
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black, // Рамка под цвет фона, чтобы индикатор выделялся
                  width: 2.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar(ChatModel chat) {
    // Определяем - есть ли реальный аватар (http/https URL)
    final hasRealAvatar = chat.avatar != null &&
        chat.avatar!.isNotEmpty &&
        (chat.avatar!.startsWith('http') || chat.avatar!.startsWith('https'));

    // Для Избранного показываем иконку закладки (bookmark)
    final icon = chat.isFavorites ? FontAwesomeIcons.solidBookmark : null;

    // Используем AvatarWidget
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
    final isEncrypted = chat.isEncryptedMessage || chat.displayMessage == 'Зашифрованное сообщение';
    return Row(
      children: [
        if (isEncrypted) ...[
          FaIcon(
            FontAwesomeIcons.lock,
            size: 10,
            color: chat.unreadCount > 0 ? Colors.white.withOpacity(0.5) : AppStyles.textMutedColor,
          ),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(
            chat.displayMessage,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: chat.unreadCount > 0 ? FontWeight.w500 : FontWeight.w400,
              color: chat.unreadCount > 0
                  ? Colors.white.withOpacity(0.7)
                  : AppStyles.textMutedColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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