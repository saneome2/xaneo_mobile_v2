import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/chat/chat_model.dart';
import '../../services/api/api_client.dart';
import '../../services/chat/chat_service.dart';
import '../../services/chat/chat_local_repository.dart';
import '../../styles/app_styles.dart';
import '../../widgets/common/avatar_widget.dart';
import 'chat_screen.dart';
import '../../widgets/common/premium_page_route.dart';

class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({super.key});

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  late final ChatService _chatService;
  late final LocalChatRepository _localChatRepo;
  Timer? _relativeTimeTimer;
  
  // Поиск
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _isSearching = false;

  bool _isTransitioning = true;

  @override
  void initState() {
    super.initState();
    _localChatRepo = context.read<LocalChatRepository>();
    _chatService = ChatService(apiClient: context.read<ApiClient>());
    
    // Defer rendering of complex UI and lists until route transition completes
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isTransitioning = false;
        });
        _startRelativeTimeTicker();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _relativeTimeTimer?.cancel();
    super.dispose();
  }

  void _startRelativeTimeTicker() {
    _relativeTimeTimer?.cancel();
    _relativeTimeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _unarchiveChat(ChatModel chat) async {
    // 1. Оптимистичное обновление UI локально
    await _localChatRepo.updateArchiveStatus(chat.id, false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Чат "${chat.name}" возвращен из архива'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E1E2E),
          action: SnackBarAction(
            label: 'Отмена',
            textColor: Colors.white,
            onPressed: () async {
              await _localChatRepo.updateArchiveStatus(chat.id, true);
              await _chatService.archiveChat(chat.id, true);
            },
          ),
        ),
      );
    }

    // 2. Отправка на сервер в фоне
    final success = await _chatService.archiveChat(chat.id, false);
    if (!success) {
      // В случае неудачи откатываем локальное изменение
      await _localChatRepo.updateArchiveStatus(chat.id, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось разархивировать чат на сервере'),
            backgroundColor: AppStyles.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      body: Stack(
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
    
    // BackdropFilter is extremely heavy during page transitions.
    // Use a solid color without blur while transitioning.
    if (_isTransitioning) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            height: 44,
            child: _buildHeaderContent(),
          ),
        ),
      );
    }

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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 44,
              child: _buildHeaderContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderContent() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Обычный заголовок с кнопкой назад
        AnimatedOpacity(
          opacity: _isSearching ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: _isSearching,
            child: Row(
              children: [
                _buildHeaderButton(
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppStyles.textPrimaryColor,
                    size: 16,
                  ),
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Архив',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppStyles.textPrimaryColor,
                    fontFamily: AppStyles.fontFamily,
                    letterSpacing: -0.5,
                  ),
                ),
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
              ],
            ),
          ),
        ),

        // Поисковая строка
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
                                hintText: 'Поиск в архиве...',
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

  Widget _buildContent() {
    final topOffset = MediaQuery.of(context).padding.top + 70.0;

    return StreamBuilder<List<ChatModel>>(
      stream: _localChatRepo.watchArchivedChats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
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
        var filteredChats = chats;

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
                    FontAwesomeIcons.boxArchive,
                    size: 50,
                    color: AppStyles.textMutedColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isNotEmpty ? 'Ничего не найдено' : 'Архив пуст',
                    style: AppStyles.titleLarge.copyWith(
                      color: AppStyles.textMutedColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _searchQuery.isNotEmpty 
                        ? 'Попробуйте изменить запрос' 
                        : 'Здесь будут находиться ваши архивированные чаты',
                    style: AppStyles.bodyMedium.copyWith(
                      color: AppStyles.textMutedColor,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemExtent: 79.0, // Fixed height for O(1) layout
          padding: EdgeInsets.only(
            top: topOffset,
            bottom: 30,
          ),
          itemCount: filteredChats.length,
          itemBuilder: (context, index) {
            final chat = filteredChats[index];
            return Dismissible(
              key: ValueKey('archive_${chat.id}'),
              direction: DismissDirection.endToStart,
              onDismissed: (direction) => _unarchiveChat(chat),
              background: Container(
                color: const Color(0xFF10B981), // Emerald/Premium green
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Вернуть',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.unarchive_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ],
                ),
              ),
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
          },
        );
      },
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
              _buildAvatar(chat),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
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

  Widget _buildAvatar(ChatModel chat) {
    final hasRealAvatar = chat.avatar != null &&
        chat.avatar!.isNotEmpty &&
        (chat.avatar!.startsWith('http') || chat.avatar!.startsWith('https'));

    final icon = chat.isFavorites ? FontAwesomeIcons.solidBookmark : null;

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
}
