import 'dart:async';
import 'dart:ui';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/chat/chat_model.dart';
import '../../models/auth/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth/token_storage.dart';
import '../../services/chat/chat_local_repository.dart';
import '../../services/chat/chat_websocket_service.dart';
import '../../services/crypto/crypto_service.dart';
import '../../services/database/app_database.dart';
import '../../styles/app_styles.dart';
import '../../widgets/common/avatar_widget.dart';

class ChatScreen extends StatefulWidget {
  final ChatModel chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final LocalChatRepository _localChatRepo;
  late final ChatWebSocketService _chatWebSocketService;
  StreamSubscription? _wsEventsSub;

  final _messageController = FormattedTextEditingController();
  final _messageFocusNode = FocusNode();
  final _scrollController = ScrollController();

  int? _localChatId;
  bool _isLoading = true;
  bool _isVoiceMode = true;
  late final Stream<List<Message>> _messagesStream;

  @override
  void initState() {
    super.initState();
    _localChatRepo = context.read<LocalChatRepository>();
    _messagesStream = _localChatRepo.watchMessagesForServerChat(widget.chat.id);
    _chatWebSocketService = ChatWebSocketService(tokenStorage: TokenStorage());

    _initChat();
  }

  @override
  void dispose() {
    _wsEventsSub?.cancel();
    _chatWebSocketService.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    // 1. Get or create local chatId
    var localId = await _localChatRepo.getLocalChatId(widget.chat.id);
    if (localId == null) {
      // If chat doesn't exist locally, save it first
      await _localChatRepo.saveChat(widget.chat);
      localId = await _localChatRepo.getLocalChatId(widget.chat.id);
    }

    if (mounted) {
      setState(() {
        _localChatId = localId;
        _isLoading = false;
      });
    }

    if (localId != null) {
      // 2. Populate mock history if the chat is completely empty for a nice initial experience
      await _populateMockMessagesIfNeeded(localId);
    }

    // 3. Connect to WebSocket for E2EE updates
    await _chatWebSocketService.connect(widget.chat.id);
    _wsEventsSub = _chatWebSocketService.events.listen(_handleWsEvent);
  }

  Future<void> _populateMockMessagesIfNeeded(int localId) async {
    try {
      final messagesStream = _localChatRepo.watchMessagesForChat(localId);
      final currentMessages = await messagesStream.first.timeout(
        const Duration(seconds: 1),
        onTimeout: () => [],
      );
      if (currentMessages.isEmpty) {
        final now = DateTime.now();
        final mockMessages = [
          MessagesCompanion(
            serverMessageId: const Value('mock_1'),
            chatId: Value(localId),
            senderId: Value(widget.chat.otherUser?['username'] ?? 'user'),
            textContent: const Value('Привет! Это безопасный чат Xaneo с поддержкой E2EE.'),
            timestamp: Value(now.subtract(const Duration(minutes: 5))),
          ),
          MessagesCompanion(
            serverMessageId: const Value('mock_2'),
            chatId: Value(localId),
            senderId: const Value('system'),
            textContent: const Value('Установлено сквозное шифрование XSEC-2. Никто посторонний не сможет прочесть вашу переписку.'),
            timestamp: Value(now.subtract(const Duration(minutes: 4))),
          ),
          MessagesCompanion(
            serverMessageId: const Value('mock_3'),
            chatId: Value(localId),
            senderId: Value(widget.chat.otherUser?['username'] ?? 'user'),
            textContent: const Value('Здесь можно безопасно общаться, обмениваться ключами и медиа-файлами 🛡️'),
            timestamp: Value(now.subtract(const Duration(minutes: 3))),
          ),
        ];
        await _localChatRepo.saveMessagesBatch(mockMessages);
      }
    } catch (e) {
      debugPrint('Error inserting mock messages: $e');
    }
  }

  Future<void> _handleWsEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();
    if (type != 'encrypted_message') return;

    final chatId = event['chat_id']?.toString();
    final encryptedText = event['encrypted_text']?.toString();

    if (chatId == null || chatId != widget.chat.id || encryptedText == null) return;

    final cryptoService = context.read<CryptoService>();
    final decrypted = await cryptoService.decryptChatMessage(encryptedText, chatId);

    final localId = _localChatId;
    if (localId != null) {
      final timestamp = _parseDateTime(event['created_at']) ?? DateTime.now();
      final senderId = event['sender_id']?.toString() ?? 'system';
      final msgId = event['id']?.toString() ?? 'ws_${DateTime.now().millisecondsSinceEpoch}';

      await _localChatRepo.saveMessage(
        MessagesCompanion(
          serverMessageId: Value(msgId),
          chatId: Value(localId),
          senderId: Value(senderId),
          textContent: Value(decrypted ?? encryptedText),
          timestamp: Value(timestamp),
        ),
      );

      // Update local chat preview
      final updatedChat = ChatModel(
        id: widget.chat.id,
        name: widget.chat.name,
        avatar: widget.chat.avatar,
        avatarGradient: widget.chat.avatarGradient,
        lastMessage: decrypted ?? encryptedText,
        lastMessageTime: timestamp,
        unreadCount: 0,
        isGroup: widget.chat.isGroup,
        isChannel: widget.chat.isChannel,
        isPersonal: widget.chat.isPersonal,
        isFavorites: widget.chat.isFavorites,
        otherUser: widget.chat.otherUser,
        isEncrypted: decrypted == null,
      );
      await _localChatRepo.saveChat(updatedChat);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    final localId = _localChatId;
    if (localId == null) return;

    final auth = context.read<AuthProvider>();
    final cryptoService = context.read<CryptoService>();
    final currentUser = auth.user;
    final timestamp = DateTime.now();
    final localMsgId = 'local_${timestamp.millisecondsSinceEpoch}';

    // 1. Save locally first (Optimistic update)
    await _localChatRepo.saveMessage(
      MessagesCompanion(
        serverMessageId: Value(localMsgId),
        chatId: Value(localId),
        senderId: Value(currentUser?.username ?? 'me'),
        textContent: Value(text),
        timestamp: Value(timestamp),
      ),
    );

    // Update chat preview locally
    final updatedChat = ChatModel(
      id: widget.chat.id,
      name: widget.chat.name,
      avatar: widget.chat.avatar,
      avatarGradient: widget.chat.avatarGradient,
      lastMessage: text,
      lastMessageTime: timestamp,
      unreadCount: 0,
      isGroup: widget.chat.isGroup,
      isChannel: widget.chat.isChannel,
      isPersonal: widget.chat.isPersonal,
      isFavorites: widget.chat.isFavorites,
      otherUser: widget.chat.otherUser,
      isEncrypted: false,
    );
    await _localChatRepo.saveChat(updatedChat);

    // 2. Encrypt & send E2EE over WS
    try {
      final encryptedText = await cryptoService.encryptMessage(text, widget.chat.id);
      
      if (encryptedText != null) {
        await _chatWebSocketService.send({
          'type': 'encrypted_message',
          'chat_id': widget.chat.id,
          'encrypted_text': encryptedText,
          'sender_id': currentUser?.id.toString() ?? currentUser?.username ?? 'me',
          'created_at': timestamp.toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Error sending E2EE message over WS: $e');
    }
  }

  void _applyFormatting(String prefix, String suffix, EditableTextState editableTextState) {
    final value = editableTextState.textEditingValue;
    final text = value.text;
    final selection = value.selection;

    if (selection.isCollapsed) return;

    final selectedText = selection.textInside(text);
    final newText = text.replaceRange(selection.start, selection.end, '$prefix$selectedText$suffix');
    
    final newSelection = TextSelection(
      baseOffset: selection.start,
      extentOffset: selection.end + prefix.length + suffix.length,
    );

    _messageController.value = TextEditingValue(
      text: newText,
      selection: newSelection,
    );
    
    editableTextState.hideToolbar();
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          // Stunning Liquid Glass Background decoration
          _buildGlassBackground(),

          // Main Chat Area
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white54,
                          ),
                        )
                      : _buildMessagesList(currentUser),
                ),
                
                // Compact Input Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: _buildInputArea(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassBackground() {
    return Stack(
      children: [
        // Floating glow bubble 1 (Top right)
        Positioned(
          top: -40,
          right: -40,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF6366F1).withOpacity(0.25), // E2E Indigo glow
                  const Color(0xFF6366F1).withOpacity(0.0),
                ],
              ),
            ),
          ),
        ),
        // Floating glow bubble 2 (Bottom left)
        Positioned(
          bottom: 120,
          left: -85,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFD946EF).withOpacity(0.18), // E2E Fuchsia glow
                  const Color(0xFFD946EF).withOpacity(0.0),
                ],
              ),
            ),
          ),
        ),
        // Heavy Glass Blur layer
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
            child: Container(
              color: Colors.black.withOpacity(0.75),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderDroplet({
    required Widget child,
    required VoidCallback onTap,
    bool isCircle = true,
  }) {
    return Container(
      width: isCircle ? 40 : null,
      height: 40,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.08),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leadingWidth: 52,
            leading: Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _buildHeaderDroplet(
                  isCircle: true,
                  onTap: () => Navigator.of(context).pop(),
                  child: const FaIcon(FontAwesomeIcons.chevronLeft, color: Colors.white, size: 14),
                ),
              ),
            ),
            centerTitle: true,
            title: _buildHeaderDroplet(
              isCircle: false,
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.chat.name,
                          style: AppStyles.bodyMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FaIcon(
                              FontAwesomeIcons.lock,
                              size: 9,
                              color: const Color(0xFF4ADE80).withOpacity(0.9),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Сквозное шифрование',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF4ADE80).withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              Center(
                child: _buildHeaderDroplet(
                  isCircle: true,
                  onTap: () {},
                  child: const FaIcon(FontAwesomeIcons.phone, color: Colors.white70, size: 16),
                ),
              ),
              const SizedBox(width: 8),
              Center(
                child: _buildHeaderDroplet(
                  isCircle: true,
                  onTap: () {},
                  child: const FaIcon(FontAwesomeIcons.ellipsisVertical, color: Colors.white70, size: 16),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList(UserModel? currentUser) {
    if (_localChatId == null) {
      return const Center(child: Text('Чат не найден', style: TextStyle(color: Colors.white)));
    }

    return StreamBuilder<List<Message>>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white54));
        }

        final messages = snapshot.data ?? [];

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(FontAwesomeIcons.lockOpen, size: 40, color: Colors.white.withOpacity(0.2)),
                const SizedBox(height: 12),
                Text(
                  'Напишите первое сообщение',
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(top: 16, bottom: 16),
          reverse: true, // Newer messages at the bottom
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            final isMe = msg.senderId == currentUser?.username || msg.senderId == currentUser?.id.toString();
            return _buildMessageBubble(msg, isMe, currentUser);
          },
        );
      },
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe, UserModel? currentUser) {
    if (message.senderId == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(FontAwesomeIcons.shield, color: const Color(0xFF4ADE80).withOpacity(0.7), size: 11),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message.textContent,
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6), height: 1.3),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final bubbleColor = isMe 
        ? Colors.white.withOpacity(0.12) 
        : Colors.white.withOpacity(0.04);
    
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    
    final corners = isMe
        ? const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          );

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: corners,
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildFormattedText(
              message.textContent,
              const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.35),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(fontSize: 9.5, color: Colors.white.withOpacity(0.35)),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  FaIcon(
                    message.isRead ? FontAwesomeIcons.checkDouble : FontAwesomeIcons.check,
                    size: 10,
                    color: message.isRead ? const Color(0xFF4ADE80) : Colors.white.withOpacity(0.3),
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 25,
            spreadRadius: -5,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: TextField(
            controller: _messageController,
            focusNode: _messageFocusNode,
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
            maxLines: 3,
            minLines: 1,
            textInputAction: TextInputAction.newline,
            contextMenuBuilder: (context, editableTextState) {
              final selection = editableTextState.textEditingValue.selection;
              final List<Widget> items = [];
              
              if (editableTextState.cutEnabled) {
                items.add(_buildToolbarButton(
                  icon: FontAwesomeIcons.scissors,
                  label: 'Вырезать',
                  onTap: () => editableTextState.cutSelection(SelectionChangedCause.toolbar),
                ));
              }
              if (editableTextState.copyEnabled) {
                items.add(_buildToolbarButton(
                  icon: FontAwesomeIcons.copy,
                  label: 'Копировать',
                  onTap: () => editableTextState.copySelection(SelectionChangedCause.toolbar),
                ));
              }
              if (editableTextState.pasteEnabled) {
                items.add(_buildToolbarButton(
                  icon: FontAwesomeIcons.clipboard,
                  label: 'Вставить',
                  onTap: () => editableTextState.pasteText(SelectionChangedCause.toolbar),
                ));
              }
              if (editableTextState.selectAllEnabled) {
                items.add(_buildToolbarButton(
                  icon: FontAwesomeIcons.squareCheck,
                  label: 'Выбрать все',
                  onTap: () => editableTextState.selectAll(SelectionChangedCause.toolbar),
                ));
              }
              
              if (!selection.isCollapsed) {
                items.addAll([
                  _buildToolbarButton(
                    icon: FontAwesomeIcons.bold,
                    label: 'Жирный',
                    onTap: () => _applyFormatting('**', '**', editableTextState),
                  ),
                  _buildToolbarButton(
                    icon: FontAwesomeIcons.italic,
                    label: 'Курсив',
                    onTap: () => _applyFormatting('*', '*', editableTextState),
                  ),
                  _buildToolbarButton(
                    icon: FontAwesomeIcons.code,
                    label: 'Код',
                    onTap: () => _applyFormatting('`', '`', editableTextState),
                  ),
                  _buildToolbarButton(
                    icon: FontAwesomeIcons.strikethrough,
                    label: 'Зачеркнуть',
                    onTap: () => _applyFormatting('~~', '~~', editableTextState),
                  ),
                ]);
              }

              if (items.isEmpty) return const SizedBox.shrink();

              final List<Widget> rowChildren = [];
              for (int i = 0; i < items.length; i++) {
                rowChildren.add(items[i]);
                if (i < items.length - 1) {
                  rowChildren.add(_buildToolbarDivider());
                }
              }

              return TextSelectionToolbar(
                anchorAbove: editableTextState.contextMenuAnchors.primaryAnchor,
                anchorBelow: editableTextState.contextMenuAnchors.secondaryAnchor ??
                    editableTextState.contextMenuAnchors.primaryAnchor,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width - 32,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.15),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: rowChildren,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
            decoration: InputDecoration(
              hintText: 'Сообщение...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 15),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.15),
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.15),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.25),
                  width: 1,
                ),
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () {
                    // TODO: Show sticker picker
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: FaIcon(
                      FontAwesomeIcons.faceSmile,
                      color: Colors.white.withOpacity(0.55),
                      size: 20,
                    ),
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Attach Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () {
                        // TODO: Add attachment action
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: FaIcon(
                          FontAwesomeIcons.plus,
                          color: Colors.white.withOpacity(0.65),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 2. Dynamic Send / Mic Button
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 2, top: 2),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _messageController,
                      builder: (context, value, child) {
                        final hasText = value.text.trim().isNotEmpty;
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return ScaleTransition(scale: animation, child: child);
                          },
                          child: hasText
                              ? GestureDetector(
                                  key: const ValueKey('send'),
                                  onTap: _sendMessage,
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF6366F1), Color(0xFFD946EF)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFD946EF).withOpacity(0.4),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: FaIcon(
                                        FontAwesomeIcons.arrowUp,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                )
                              : StatefulBuilder(
                                  builder: (context, setStateLocal) {
                                    return GestureDetector(
                                      key: ValueKey(_isVoiceMode ? 'mic' : 'video'),
                                      onTap: () {
                                        setStateLocal(() {
                                          _isVoiceMode = !_isVoiceMode;
                                        });
                                      },
                                      child: Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: FaIcon(
                                            _isVoiceMode
                                                ? FontAwesomeIcons.microphone
                                                : FontAwesomeIcons.video,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 80,
                minHeight: 44,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormattedText(String content, TextStyle baseStyle) {
    final List<TextSpan> spans = [];
    final RegExp regExp = RegExp(
      r'(\*\*(.*?)\*\*)|(\*(.*?)\*)|(__(.*?)__)|(_(.*?)_)|(`(.*?)`)|(~~(.*?)~~)|([^\*_`~]+|[\*_`~])',
    );

    final Iterable<Match> matches = regExp.allMatches(content);

    for (final Match match in matches) {
      final String fullMatch = match.group(0) ?? '';
      
      if (match.group(2) != null) {
        spans.add(TextSpan(
          text: match.group(2),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(
          text: match.group(4),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(6) != null) {
        spans.add(TextSpan(
          text: match.group(6),
          style: baseStyle.copyWith(decoration: TextDecoration.underline),
        ));
      } else if (match.group(8) != null) {
        spans.add(TextSpan(
          text: match.group(8),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(10) != null) {
        spans.add(TextSpan(
          text: match.group(10),
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: Colors.white.withOpacity(0.12),
            color: const Color(0xFF4ADE80),
          ),
        ));
      } else if (match.group(12) != null) {
        spans.add(TextSpan(
          text: match.group(12),
          style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        ));
      } else {
        spans.add(TextSpan(text: fullMatch, style: baseStyle));
      }
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  Widget _buildToolbarButton({
    required FaIconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarDivider() {
    return Container(
      width: 1,
      height: 18,
      color: Colors.white.withOpacity(0.12),
      margin: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}

class FormattedTextEditingController extends TextEditingController {
  FormattedTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<TextSpan> children = [];
    final RegExp regExp = RegExp(
      r'(\*\*(.*?)\*\*)|(\*(.*?)\*)|(__(.*?)__)|(_(.*?)_)|(`(.*?)`)|(~~(.*?)~~)|([^\*_`~]+|[\*_`~])',
    );

    final Iterable<Match> matches = regExp.allMatches(text);

    final invisibleStyle = (style ?? const TextStyle()).copyWith(
      color: Colors.transparent,
      fontSize: 0.1,
    );

    for (final Match match in matches) {
      final String fullMatch = match.group(0) ?? '';
      
      // Match bold: **text**
      if (match.group(2) != null) {
        final content = match.group(2)!;
        children.add(TextSpan(text: '**', style: invisibleStyle));
        children.add(TextSpan(
          text: content,
          style: style?.copyWith(fontWeight: FontWeight.bold) ??
              const TextStyle(fontWeight: FontWeight.bold),
        ));
        children.add(TextSpan(text: '**', style: invisibleStyle));
      }
      // Match italic: *text*
      else if (match.group(4) != null) {
        final content = match.group(4)!;
        children.add(TextSpan(text: '*', style: invisibleStyle));
        children.add(TextSpan(
          text: content,
          style: style?.copyWith(fontStyle: FontStyle.italic) ??
              const TextStyle(fontStyle: FontStyle.italic),
        ));
        children.add(TextSpan(text: '*', style: invisibleStyle));
      }
      // Match underline: __text__
      else if (match.group(6) != null) {
        final content = match.group(6)!;
        children.add(TextSpan(text: '__', style: invisibleStyle));
        children.add(TextSpan(
          text: content,
          style: style?.copyWith(decoration: TextDecoration.underline) ??
              const TextStyle(decoration: TextDecoration.underline),
        ));
        children.add(TextSpan(text: '__', style: invisibleStyle));
      }
      // Match italic: _text_
      else if (match.group(8) != null) {
        final content = match.group(8)!;
        children.add(TextSpan(text: '_', style: invisibleStyle));
        children.add(TextSpan(
          text: content,
          style: style?.copyWith(fontStyle: FontStyle.italic) ??
              const TextStyle(fontStyle: FontStyle.italic),
        ));
        children.add(TextSpan(text: '_', style: invisibleStyle));
      }
      // Match code: `text`
      else if (match.group(10) != null) {
        final content = match.group(10)!;
        children.add(TextSpan(text: '`', style: invisibleStyle));
        children.add(TextSpan(
          text: content,
          style: style?.copyWith(
                fontFamily: 'monospace',
                backgroundColor: Colors.white.withOpacity(0.1),
              ) ??
              TextStyle(
                fontFamily: 'monospace',
                backgroundColor: Colors.white.withOpacity(0.1),
              ),
        ));
        children.add(TextSpan(text: '`', style: invisibleStyle));
      }
      // Match strikethrough: ~~text~~
      else if (match.group(12) != null) {
        final content = match.group(12)!;
        children.add(TextSpan(text: '~~', style: invisibleStyle));
        children.add(TextSpan(
          text: content,
          style: style?.copyWith(decoration: TextDecoration.lineThrough) ??
              const TextStyle(decoration: TextDecoration.lineThrough),
        ));
        children.add(TextSpan(text: '~~', style: invisibleStyle));
      }
      // Plain text
      else {
        children.add(TextSpan(text: fullMatch, style: style));
      }
    }

    return TextSpan(style: style, children: children);
  }
}
