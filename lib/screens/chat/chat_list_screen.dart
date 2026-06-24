import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'archived_chats_screen.dart';
import '../../widgets/common/premium_page_route.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
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

  late final ScrollController _scrollController;
  bool _isArchiveRowVisible = false;
  double _pullDistance = 0.0;
  final Set<String> _animatedChatIds = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

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

  void _onScroll() {
    if (!mounted) return;
    final offset = _scrollController.offset;
    
    // Мгновенно фиксируем появление архива, если оттянули полностью (до упора в -78px)
    if (offset <= -77.5 && !_isArchiveRowVisible) {
      setState(() {
        _isArchiveRowVisible = true;
        _pullDistance = 0.0;
      });
      _scrollController.jumpTo(0.0);
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}
      return;
    }

    // Обновляем расстояние оттягивания для анимации
    if (offset < 0) {
      setState(() {
        _pullDistance = -offset;
      });
    } else {
      if (_pullDistance != 0.0) {
        setState(() {
          _pullDistance = 0.0;
        });
      }
    }
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
              String? inferredType = chat.lastMessageType;
              if (decrypted.trim().startsWith('{')) {
                try {
                  final parsed = jsonDecode(decrypted);
                  if (parsed is Map) {
                    inferredType = parsed['type']?.toString() ?? chat.lastMessageType;
                  }
                } catch (_) {}
              }
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
                isArchived: chat.isArchived,
                archivedAt: chat.archivedAt,
                lastMessageType: inferredType,
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
      'last_message_type': payload['last_message_type'] ?? payload['message_type'],
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
        isArchived: existing.isArchived,
        archivedAt: existing.archivedAt,
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
    String? inferredType = event['message_type']?.toString() ?? event['last_message_type']?.toString();
    if (decrypted != null && decrypted.trim().startsWith('{')) {
      try {
        final parsed = jsonDecode(decrypted);
        if (parsed is Map) {
          inferredType = parsed['type']?.toString() ?? inferredType;
        }
      } catch (_) {}
    }

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
      isArchived: existing.isArchived,
      archivedAt: existing.archivedAt,
      lastMessageType: inferredType,
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

    String? inferredType = chat.lastMessageType;
    if (decrypted.trim().startsWith('{')) {
      try {
        final parsed = jsonDecode(decrypted);
        if (parsed is Map) {
          inferredType = parsed['type']?.toString() ?? inferredType;
        }
      } catch (_) {}
    }

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
      isArchived: chat.isArchived,
      archivedAt: chat.archivedAt,
      lastMessageType: inferredType,
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
    super.build(context);
    return StreamBuilder<List<ChatModel>>(
      stream: _localChatRepo.watchArchivedChats(),
      builder: (context, archivedSnapshot) {
        final archivedChats = archivedSnapshot.data ?? [];
        final showArchiveRow = archivedChats.isNotEmpty && _searchQuery.isEmpty && _selectedCategory == 'all';
        final topOffset = MediaQuery.of(context).padding.top + 122.0;

        return Container(
          color: AppStyles.backgroundColor,
          child: Stack(
            children: [
              // 1. Список чатов (в фоне, скроллится под хедер)
              Positioned.fill(
                child: _buildContent(archivedChats, showArchiveRow, topOffset),
              ),

              // 2. Floating Archive Row when pulling
              if (showArchiveRow && !_isArchiveRowVisible && _pullDistance > 0.0)
                Positioned(
                  top: topOffset + _pullDistance - 78.0,
                  left: 0,
                  right: 0,
                  height: 78.0,
                  child: Container(
                    color: AppStyles.backgroundColor,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 77.0,
                          child: _buildArchiveRow(archivedChats),
                        ),
                        Divider(
                          color: Colors.white.withOpacity(0.04),
                          height: 1,
                          indent: 84,
                        ),
                      ],
                    ),
                  ),
                ),

              // 3. Pinned Frosted Glass Header
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildPinnedGlassHeader(),
              ),
            ],
          ),
        );
      },
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

  Future<void> _archiveChat(ChatModel chat) async {
    // 1. Оптимистичное локальное обновление UI
    await _localChatRepo.updateArchiveStatus(chat.id, true);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Чат "${chat.name}" архивирован'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E1E2E),
          action: SnackBarAction(
            label: 'Отмена',
            textColor: Colors.white,
            onPressed: () async {
              await _localChatRepo.updateArchiveStatus(chat.id, false);
              await _chatService.archiveChat(chat.id, false);
            },
          ),
        ),
      );
    }

    // 2. Отправка запроса на сервер
    final success = await _chatService.archiveChat(chat.id, true);
    if (!success) {
      await _localChatRepo.updateArchiveStatus(chat.id, false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось архивировать чат на сервере'),
            backgroundColor: AppStyles.errorColor,
          ),
        );
      }
    }
  }

  Widget _buildArchiveRow(List<ChatModel> archivedChats) {
    final totalUnread = archivedChats.fold<int>(0, (sum, chat) => sum + chat.unreadCount);
    
    // Формируем красивое превью имен чатов в архиве
    final names = archivedChats.take(3).map((c) => c.name).join(', ');
    final previewText = archivedChats.length > 3 ? '$names и еще ${archivedChats.length - 3}' : names;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            PremiumPageRoute(
              page: const ArchivedChatsScreen(),
              transitionType: PremiumTransitionType.archivedReveal,
            ),
          );
        },
        splashColor: Colors.white.withOpacity(0.03),
        highlightColor: Colors.white.withOpacity(0.01),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: IgnorePointer(
            child: Row(
            children: [
              // Аватар архива с градиентом и иконкой
              AvatarWidget(
                avatar: null,
                avatarGradient: '6366F1,4F46E5', // Indigo-Violet gradient
                hasAvatar: false,
                username: 'Архив',
                size: 50,
                icon: FontAwesomeIcons.boxArchive,
              ),
              const SizedBox(width: 14),

              // Информация
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Архивированные чаты',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: AppStyles.textPrimaryColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      previewText.isNotEmpty ? previewText : 'Архив',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        color: AppStyles.textMutedColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Счётчик непрочитанных в архиве
              if (totalUnread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1), // Indigo color for archive badge
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    totalUnread > 99 ? '99+' : totalUnread.toString(),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppStyles.textMutedColor,
                  size: 14,
                ),
            ],
          ),
          ), // Close IgnorePointer
        ),
      ),
    );
  }

  Widget _buildContent(List<ChatModel> archivedChats, bool showArchiveRow, double topOffset) {
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

        if (filteredChats.isEmpty && !showArchiveRow) {
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

        final listLength = sortedChats.length + (showArchiveRow && _isArchiveRowVisible ? 1 : 0);

        return RefreshIndicator(
          onRefresh: _syncChats,
          edgeOffset: topOffset - 24.0,
          color: AppStyles.textPrimaryColor,
          backgroundColor: AppStyles.inputBackgroundColor,
          notificationPredicate: (notification) {
            final hasArchivedChats = archivedChats.isNotEmpty;
            if (hasArchivedChats && !_isArchiveRowVisible) {
              return false;
            }
            return notification.depth == 0;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              if (notification is ScrollEndNotification) {
                final offset = _scrollController.offset;
                if (offset < -70.0 && !_isArchiveRowVisible) {
                  setState(() {
                    _isArchiveRowVisible = true;
                  });
                  _scrollController.jumpTo(0.0);
                }
              }
              return false;
            },
            child: NotificationListener<OverscrollIndicatorNotification>(
              onNotification: (overscroll) {
                overscroll.disallowIndicator();
                return true;
              },
              child: ListView.builder(
                controller: _scrollController,
                physics: ArchiveRevealScrollPhysics(
                  isArchiveVisible: _isArchiveRowVisible,
                  parent: const AlwaysScrollableScrollPhysics(),
                ),
                itemExtent: 79.0, // Fixed height for O(1) layout
                padding: EdgeInsets.only(
                  top: topOffset,
                  bottom: 100, // Отступ под нижнюю панель навигации
                ),
                itemCount: listLength,
                itemBuilder: (context, index) {
                  if (showArchiveRow && _isArchiveRowVisible) {
                    if (index == 0) {
                      return SizedBox(
                        height: 78.0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 77.0,
                              child: _buildArchiveRow(archivedChats),
                            ),
                            Divider(
                              color: Colors.white.withOpacity(0.04),
                              height: 1,
                              indent: 84,
                            ),
                          ],
                        ),
                      );
                    }
                    return _buildChatItem(sortedChats[index - 1]);
                  }
                  return _buildChatItem(sortedChats[index]);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatItem(ChatModel chat) {
    final alreadyAnimated = _animatedChatIds.contains(chat.id);
    if (!alreadyAnimated) {
      _animatedChatIds.add(chat.id);
    }

    final itemContent = Column(
      children: [
        _buildChatItemContent(chat),
        Divider(
          color: Colors.white.withOpacity(0.04),
          height: 1,
          indent: 84,
        ),
      ],
    );

    final skipAnimation = alreadyAnimated || _isArchiveRowVisible;

    return Dismissible(
      key: ValueKey('active_${chat.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) => _archiveChat(chat),
      background: Container(
        color: const Color(0xFF6366F1), // Indigo/Premium violet-blue
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'В архив',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            SizedBox(width: 8),
            FaIcon(
              FontAwesomeIcons.boxArchive,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
      child: skipAnimation
          ? itemContent
          : TweenAnimationBuilder<double>(
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
              child: itemContent,
            ),
    );
  }

  Widget _buildChatItemContent(ChatModel chat) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            PremiumPageRoute(
              page: ChatScreen(chat: chat),
              transitionType: PremiumTransitionType.chatReveal,
            ),
          );
        },
        splashColor: Colors.white.withOpacity(0.03),
        highlightColor: Colors.white.withOpacity(0.01),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: IgnorePointer(
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
          ), // Close IgnorePointer
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
    // Сообщение считается зашифрованным для отображения замка, если:
    // 1. Оно помечено как зашифрованное
    // 2. И отображаемый текст это действительно "Зашифрованное сообщение"
    //    (а не конкретный тип вроде "📊 Опрос" или "✅ Список задач")
    final isEncrypted = chat.isEncryptedMessage && 
        chat.displayMessage == 'Зашифрованное сообщение';
    
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

class ArchiveRevealScrollPhysics extends BouncingScrollPhysics {
  final bool isArchiveVisible;
  const ArchiveRevealScrollPhysics({
    required this.isArchiveVisible,
    super.parent,
  });

  @override
  ArchiveRevealScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ArchiveRevealScrollPhysics(
      isArchiveVisible: isArchiveVisible,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (!isArchiveVisible && value < -78.0) {
      if (position.pixels >= -78.0) {
        return value - (-78.0);
      }
      return value - position.pixels;
    }
    return super.applyBoundaryConditions(position, value);
  }
}