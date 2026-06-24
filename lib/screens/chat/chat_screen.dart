import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:url_launcher/url_launcher.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../models/chat/chat_model.dart';
import '../../widgets/common/video_thumbnail_widget.dart';
import '../../models/auth/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth/token_storage.dart';
import '../../services/api/api_client.dart';
import '../../services/chat/chat_local_repository.dart';
import '../../services/chat/chat_service.dart';
import '../../services/chat/chat_websocket_service.dart';
import '../../services/crypto/crypto_service.dart';
import '../../services/database/app_database.dart';
import '../../styles/app_styles.dart';
import '../../widgets/common/chat_info_modal.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../utils/local_proxy.dart';
import 'package:record/record.dart';
import 'widgets/todo_poll_widgets.dart';
import '../../widgets/common/create_poll_todo_modals.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/video_message_player.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/playback_provider.dart';
import '../../widgets/voice_waveform_slider.dart';

/// Immutable state class для оптимизации Selector
class _VoicePlaybackState {
  final String? currentAudioUrl;
  final bool isPlaying;
  final bool isInitialized;
  final bool isLoading;
  final Duration position;
  final Duration duration;

  const _VoicePlaybackState({
    required this.currentAudioUrl,
    required this.isPlaying,
    required this.isInitialized,
    required this.isLoading,
    required this.position,
    required this.duration,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _VoicePlaybackState &&
          runtimeType == other.runtimeType &&
          currentAudioUrl == other.currentAudioUrl &&
          isPlaying == other.isPlaying &&
          isInitialized == other.isInitialized &&
          isLoading == other.isLoading &&
          position == other.position &&
          duration == other.duration;

  @override
  int get hashCode =>
      currentAudioUrl.hashCode ^
      isPlaying.hashCode ^
      isInitialized.hashCode ^
      isLoading.hashCode ^
      position.hashCode ^
      duration.hashCode;
}

class ChatScreen extends StatefulWidget {
  final ChatModel chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final LocalChatRepository _localChatRepo;
  late final ChatService _chatService;
  late final ChatWebSocketService _chatWebSocketService;
  StreamSubscription? _wsEventsSub;

  final _messageController = FormattedTextEditingController();
  final _messageFocusNode = FocusNode();
  final _scrollController = ScrollController();

  int? _localChatId;
  bool _isLoading = true;
  bool _isVoiceMode = true;

  // Recording state variables
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingDurationSeconds = 0;
  double _dragOffset = 0.0;
  bool _isHoldingButton = false;

  // Video recording state variables
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isRecordingVideo = false;
  Timer? _videoRecordingTimer;
  double _videoRecordingDurationSeconds = 0.0;
  final Map<String, String> _pendingVideoTempIds = {}; // file_id -> temp serverMessageId
  final Map<String, String> _pendingVideoLocalPaths = {}; // file_id -> локальный путь к записи
  late Stream<List<Message>> _messagesStream;

  // Local copy of otherUser to reflect WS status updates
  Map<String, dynamic>? _otherUser;

  // State variables for pagination/virtualization
  bool _isHistoryLoading = false;
  bool _hasMoreMessages = true;
  int _limit = 20;

  // Typing state variables (sending)
  bool _isTyping = false;
  Timer? _typingRepeatTimer;
  Timer? _typingStopTimer;

  // Typing state variables (receiving)
  String? _typingText;
  Timer? _typingTimer;
  String? _activeLottiePath;
  String? _jwtToken;
  final Map<String, String> _typingUsers = {};
  final Map<String, String> _typingLottiePaths = {};
  final Map<String, Timer> _typingTimers = {};

  // Sets of message IDs to manage animations
  final Set<String> _initialMessageIds = {};
  bool _isInitialLoadDone = false;
  final Set<String> _animatedMessageIds = {};
  final Set<String> _messagesToAnimate = {};
  bool _isOwner = false;

  // Оптимистичная отправка голосовых: temp-сообщение показывается сразу,
  // затем сверяется с эхом сервера по file_id (чтобы не плодить дубли).
  final Map<String, String> _pendingVoiceTempIds = {}; // file_id -> temp serverMessageId
  final Map<String, String> _pendingVoiceLocalPaths = {}; // file_id -> локальный путь к записи

  Future<void> _loadJwtToken() async {
    final token = await TokenStorage().getAccessToken();
    if (mounted) {
      setState(() {
        _jwtToken = token;
      });
    }
  }

  Future<void> _loadCameras() async {
    try {
      _cameras = await availableCameras();
    } catch (e) {
      debugPrint('Error loading cameras: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadJwtToken();
    _loadCameras();
    _otherUser = widget.chat.otherUser != null ? Map<String, dynamic>.from(widget.chat.otherUser!) : null;
    _localChatRepo = context.read<LocalChatRepository>();
    _chatService = ChatService(apiClient: context.read<ApiClient>());
    _messagesStream = _localChatRepo.watchMessagesForServerChat(widget.chat.id, limit: _limit);
    _chatWebSocketService = ChatWebSocketService(
      tokenStorage: TokenStorage(),
      apiClient: context.read<ApiClient>(),
    );

    _scrollController.addListener(_scrollListener);
    _messageController.addListener(_onTextChanged);
    _initChat();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _messageController.removeListener(_onTextChanged);
    _wsEventsSub?.cancel();
    _chatWebSocketService.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();

    _typingRepeatTimer?.cancel();
    _typingStopTimer?.cancel();
    _typingTimer?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _videoRecordingTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _messageController.text;
    if (text.isNotEmpty) {
      _startTypingState();
    } else {
      _stopTypingState();
    }
  }

  void _sendTypingEvent(bool isTypingNow, {String action = 'typing'}) {
    _chatWebSocketService.send({
      'type': 'typing',
      'is_typing': isTypingNow,
      'action': action,
    });
  }

  void _startTypingState() {
    if (_isTyping) {
      _typingStopTimer?.cancel();
      _typingStopTimer = Timer(const Duration(seconds: 2), _stopTypingState);
      return;
    }

    _isTyping = true;
    _sendTypingEvent(true);

    _typingRepeatTimer?.cancel();
    _typingRepeatTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_isTyping) {
        _sendTypingEvent(true);
      }
    });

    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), _stopTypingState);
  }

  void _stopTypingState() {
    if (!_isTyping) return;
    _isTyping = false;
    _sendTypingEvent(false);

    _typingRepeatTimer?.cancel();
    _typingRepeatTimer = null;
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
  }

  void _scrollListener() {
    // If we scroll close to the top (maxScrollExtent), load more history
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMoreMessages();
    }
  }

  Future<void> _initChat() async {
    // 1. Get or create local chatId
    var localId = await _localChatRepo.getLocalChatId(widget.chat.id);
    if (localId == null) {
      // If chat doesn't exist locally, save it first
      await _localChatRepo.saveChat(widget.chat);
      localId = await _localChatRepo.getLocalChatId(widget.chat.id);
    }

    // Let it build the initial list straight away to avoid post-transition jank

    if (localId != null) {
      final localCount = await _localChatRepo.getMessageCount(localId);
      
      if (mounted) {
        setState(() {
          _localChatId = localId;
          if (localCount > 0) {
            _isLoading = false;
          }
          // Set initial limit up to the number of local messages (or at least 20)
          _limit = localCount > 0 ? (localCount < 20 ? localCount : 20) : 20;
          _updateStream();
        });
      }

      if (localCount > 0) {
        // If we have messages locally, sync the latest ones in the background without blocking the UI
        _syncLatestMessages();
      } else {
        // If we have no messages locally, do a blocking load of the first page
        await _loadMoreMessages();
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }

    // 3. Connect to WebSocket for E2EE updates
    await _chatWebSocketService.connect(widget.chat.id);
    _wsEventsSub = _chatWebSocketService.events.listen(_handleWsEvent);
    
    // 4. Mark messages as read since the chat is open
    _chatService.markMessagesAsRead(widget.chat.id);

    // 5. Fetch group/channel details for owner check
    _fetchChatDetails();
  }

  Future<void> _syncLatestMessages() async {
    final localId = _localChatId;
    if (localId == null) return;

    try {
      final cryptoService = context.read<CryptoService>();
      final response = await _chatService.getEncryptedMessages(
        widget.chat.id,
        limit: 20,
        offset: 0,
      );

      if (response != null) {
        final results = response['results'] as List<dynamic>? ?? [];
        if (results.isEmpty) return;

        final List<MessagesCompanion> companions = [];
        final msgIds = results
            .map((item) => item['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();

        final existingMessages = await _localChatRepo.getMessagesByServerIds(msgIds);
        final existingMap = {for (final m in existingMessages) m.serverMessageId: m.textContent};

        int newMessagesCount = 0;
        for (final item in results) {
          final msgId = item['id']?.toString() ?? '';
          if (msgId.isNotEmpty && !existingMap.containsKey(msgId)) {
            newMessagesCount++;
          }
          final senderId = item['author_username']?.toString() ?? 'unknown';
          final encryptedText = item['encrypted_text']?.toString() ?? '';
          final timestamp = _parseDateTime(item['created_at']) ?? DateTime.now();

          String? decrypted;
          if (existingMap.containsKey(msgId)) {
            final existingText = existingMap[msgId] ?? '';
            if (cryptoService.isEncryptedMessage(existingText) && encryptedText.isNotEmpty) {
              decrypted = await cryptoService.decryptChatMessage(encryptedText, widget.chat.id);
              await Future.delayed(Duration.zero);
            } else {
              decrypted = existingText;
            }
          } else if (encryptedText.isNotEmpty) {
            decrypted = await cryptoService.decryptChatMessage(encryptedText, widget.chat.id);
            // Yield event loop to prevent UI stutter during heavy decryption loop
            await Future.delayed(Duration.zero);
          }

          String? fileInfoJson;
          if (decrypted != null && decrypted.trim().startsWith('{')) {
            try {
              final parsed = jsonDecode(decrypted);
              if (parsed is Map && (parsed['type'] == 'file' || parsed['type'] == 'voice' || parsed['type'] == 'video_message') && parsed['file_id'] != null) {
                fileInfoJson = decrypted;
              }
            } catch (_) {}
          }

          if (fileInfoJson == null) {
            final fileId = item['attached_file_id']?.toString();
            if (fileId != null) {
              final fileName = item['attached_file_name']?.toString() ?? 'file';
              final fileSize = item['attached_file_size'] as int? ?? 0;
              final fileType = item['attached_file_type']?.toString() ?? 'application/octet-stream';
              final fileUrlSuffix = item['attached_file_url']?.toString() ?? '/api/files/download/$fileId/';
              fileInfoJson = jsonEncode({
                'file_id': fileId,
                'file_name': fileName,
                'file_size': fileSize,
                'mime_type': fileType,
                'file_url': fileUrlSuffix,
              });
            }
          }

          final messageType = item['message_type']?.toString();
          final messageId = item['message_id']?.toString();
          final completionStatusVal = item['completion_status'] != null ? jsonEncode(item['completion_status']) : null;
          final votesByOptionVal = item['votes_by_option'] != null ? jsonEncode(item['votes_by_option']) : null;

          companions.add(
            MessagesCompanion(
              serverMessageId: Value(msgId),
              chatId: Value(localId),
              senderId: Value(senderId),
              textContent: Value(decrypted ?? encryptedText),
              timestamp: Value(timestamp),
              fileUrl: Value(fileInfoJson),
              messageType: Value(messageType),
              messageId: Value(messageId),
              completionStatus: Value(completionStatusVal),
              votesByOption: Value(votesByOptionVal),
            ),
          );
        }

        if (companions.isNotEmpty) {
          await _localChatRepo.saveMessagesBatch(companions);
        }

        if (mounted && newMessagesCount > 0) {
          setState(() {
            _limit += newMessagesCount;
            _updateStream();
          });
        }
      }
    } catch (e) {
      debugPrint('Error syncing latest messages: $e');
    }
  }

  /// Helper: only recreates the stream when needed, avoiding redundant StreamBuilder resets.
  void _updateStream() {
    _messagesStream = _localChatRepo.watchMessagesForServerChat(
      widget.chat.id,
      limit: _limit,
    );
  }

  Future<void> _loadMoreMessages() async {
    if (_isHistoryLoading) return;

    final localId = _localChatId;
    if (localId == null) return;

    // Set loading flag without rebuilding stream  
    setState(() => _isHistoryLoading = true);

    try {
      final localCount = await _localChatRepo.getMessageCount(localId);

      // If we have more messages locally than what we are currently showing, just show them
      if (localCount > _limit) {
        if (mounted) {
          setState(() {
            _limit = (_limit + 20).clamp(0, localCount);
            _updateStream();
            _isHistoryLoading = false;
          });
        }
        return;
      }

      // If we don't have more messages locally, fetch from the server
      if (!_hasMoreMessages) {
        if (mounted) setState(() => _isHistoryLoading = false);
        return;
      }

      final cryptoService = context.read<CryptoService>();
      final response = await _chatService.getEncryptedMessages(
        widget.chat.id,
        limit: 20,
        offset: localCount,
      );

      if (response != null) {
        final results = response['results'] as List<dynamic>? ?? [];
        if (results.isEmpty) {
          if (mounted) {
            setState(() {
              _hasMoreMessages = false;
              _isHistoryLoading = false;
            });
          }
          return;
        }

        final List<MessagesCompanion> companions = [];
        final msgIds = results
            .map((item) => item['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();

        final existingMessages = await _localChatRepo.getMessagesByServerIds(msgIds);
        final existingMap = {for (final m in existingMessages) m.serverMessageId: m.textContent};

        for (final item in results) {
          final msgId = item['id']?.toString() ?? '';
          final senderId = item['author_username']?.toString() ?? 'unknown';
          final encryptedText = item['encrypted_text']?.toString() ?? '';
          final timestamp = _parseDateTime(item['created_at']) ?? DateTime.now();

          String? decrypted;
          if (existingMap.containsKey(msgId)) {
            final existingText = existingMap[msgId] ?? '';
            if (cryptoService.isEncryptedMessage(existingText) && encryptedText.isNotEmpty) {
              decrypted = await cryptoService.decryptChatMessage(encryptedText, widget.chat.id);
              await Future.delayed(Duration.zero);
            } else {
              decrypted = existingText;
            }
          } else if (encryptedText.isNotEmpty) {
            decrypted = await cryptoService.decryptChatMessage(encryptedText, widget.chat.id);
            // Yield event loop to prevent UI stutter during heavy decryption loop
            await Future.delayed(Duration.zero);
          }

          String? fileInfoJson;
          if (decrypted != null && decrypted.trim().startsWith('{')) {
            try {
              final parsed = jsonDecode(decrypted);
              if (parsed is Map && (parsed['type'] == 'file' || parsed['type'] == 'voice' || parsed['type'] == 'video_message') && parsed['file_id'] != null) {
                fileInfoJson = decrypted;
              }
            } catch (_) {}
          }

          if (fileInfoJson == null) {
            final fileId = item['attached_file_id']?.toString();
            if (fileId != null) {
              final fileName = item['attached_file_name']?.toString() ?? 'file';
              final fileSize = item['attached_file_size'] as int? ?? 0;
              final fileType = item['attached_file_type']?.toString() ?? 'application/octet-stream';
              final fileUrlSuffix = item['attached_file_url']?.toString() ?? '/api/files/download/$fileId/';
              fileInfoJson = jsonEncode({
                'file_id': fileId,
                'file_name': fileName,
                'file_size': fileSize,
                'mime_type': fileType,
                'file_url': fileUrlSuffix,
              });
            }
          }

          final messageType = item['message_type']?.toString();
          final messageId = item['message_id']?.toString();
          final completionStatusVal = item['completion_status'] != null ? jsonEncode(item['completion_status']) : null;
          final votesByOptionVal = item['votes_by_option'] != null ? jsonEncode(item['votes_by_option']) : null;

          companions.add(
            MessagesCompanion(
              serverMessageId: Value(msgId),
              chatId: Value(localId),
              senderId: Value(senderId),
              textContent: Value(decrypted ?? encryptedText),
              timestamp: Value(timestamp),
              fileUrl: Value(fileInfoJson),
              messageType: Value(messageType),
              messageId: Value(messageId),
              completionStatus: Value(completionStatusVal),
              votesByOption: Value(votesByOptionVal),
            ),
          );
        }

        if (companions.isNotEmpty) {
          await _localChatRepo.saveMessagesBatch(companions);
        }

        if (mounted) {
          // Single setState: update limit + stream + hasMore + loading flag all at once
          setState(() {
            _limit = localCount + results.length;
            _updateStream();
            if (results.length < 20) _hasMoreMessages = false;
            _isHistoryLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _hasMoreMessages = false;
            _isHistoryLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading message history: $e');
      if (mounted) setState(() => _isHistoryLoading = false);
    }
  }

  Future<void> _handleWsEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();

    // Handle server-side error responses
    if (type == 'error') {
      debugPrint('WS_ERROR: ${event['message']}');
      return;
    }

    if (type == 'typing') {
      final userId = event['user_id']?.toString() ?? '';
      final eventIsTyping = event['is_typing'] == true;
      final action = event['action']?.toString() ?? 'typing';
      
      String getActionText(String? action) {
        switch (action) {
          case 'recording_voice':
            return 'записывает голосовое...';
          case 'sending_photo':
            return 'отправляет фото...';
          case 'sending_video':
            return 'отправляет видео...';
          case 'sending_file':
            return 'отправляет файл...';
          case 'typing':
          default:
            return 'печатает...';
        }
      }

      String getLottieAsset(String? action) {
        switch (action) {
          case 'recording_voice':
            return 'assets/animations/recording_voice.json';
          case 'sending_photo':
            return 'assets/animations/sending_photo.json';
          case 'sending_video':
            return 'assets/animations/sending_video.json';
          case 'sending_file':
            return 'assets/animations/sending_file.json';
          case 'typing':
          default:
            return 'assets/animations/typing.json';
        }
      }
      
      if (widget.chat.isPersonal) {
        final otherId = _otherUser?['id']?.toString();
        final otherUsername = _otherUser?['username']?.toString();
        if (userId == otherId || event['username']?.toString() == otherUsername) {
          if (eventIsTyping) {
            setState(() {
              _typingText = getActionText(action);
              _activeLottiePath = getLottieAsset(action);
            });
            _typingTimer?.cancel();
            _typingTimer = Timer(const Duration(seconds: 5), () {
              if (mounted) {
                setState(() {
                  _typingText = null;
                  _activeLottiePath = null;
                });
              }
            });
          } else {
            setState(() {
              _typingText = null;
              _activeLottiePath = null;
            });
            _typingTimer?.cancel();
          }
        }
      } else {
        final name = event['first_name']?.toString() ?? event['username']?.toString() ?? 'Кто-то';
        final actionText = getActionText(action);
        final lottieAsset = getLottieAsset(action);
        
        if (eventIsTyping) {
          setState(() {
            _typingUsers[userId] = '$name $actionText';
            _typingLottiePaths[userId] = lottieAsset;
          });
          _typingTimers[userId]?.cancel();
          _typingTimers[userId] = Timer(const Duration(seconds: 5), () {
            if (mounted) {
              setState(() {
                _typingUsers.remove(userId);
                _typingLottiePaths.remove(userId);
              });
            }
          });
        } else {
          setState(() {
            _typingUsers.remove(userId);
            _typingLottiePaths.remove(userId);
          });
          _typingTimers[userId]?.cancel();
        }
      }
      return;
    }

    if (type == 'user_status_update') {
      if (mounted && widget.chat.isPersonal && _otherUser != null) {
        final eventUserId = event['user_id']?.toString();
        final eventUsername = event['username']?.toString();
        final otherId = _otherUser!['id']?.toString();
        final otherUsername = _otherUser!['username']?.toString();

        if ((eventUserId != null && eventUserId == otherId) ||
            (eventUsername != null && eventUsername == otherUsername)) {
          setState(() {
            _otherUser!['is_online'] = event['is_online'];
            _otherUser!['online'] = event['is_online']; // Sync both properties
            _otherUser!['last_seen'] = event['timestamp'];
          });
        }
      }
      return;
    }

    if (type == 'chat_user_status') {
      if (mounted) {
        setState(() {
          _otherUser ??= {};
          _otherUser!['online_count'] = event['online_count'];
        });
      }
      return;
    }

    if (type == 'voice_message') {
      await _handleIncomingVoiceMessage(event);
      return;
    }

    if (type == 'video_message') {
      await _handleIncomingVideoMessage(event);
      return;
    }

    if (type != 'encrypted_message' && type != 'poll_message' && type != 'todo_list_message') {
      if (type == 'todo_completion_update') {
        await _handleTodoCompletionUpdate(event);
        return;
      }
      if (type == 'poll_vote_update') {
        await _handlePollVoteUpdate(event);
        return;
      }
      return;
    }

    final chatId = event['chat_id']?.toString();
    final encryptedText = event['encrypted_text']?.toString() ?? event['encrypted_content']?.toString();

    if (chatId == null || chatId != widget.chat.id || encryptedText == null) return;

    final cryptoService = context.read<CryptoService>();
    final decrypted = await cryptoService.decryptChatMessage(encryptedText, chatId);

    final localId = _localChatId;
    if (localId != null) {
      final timestamp = _parseDateTime(event['created_at']) ?? DateTime.now();
      final senderId = event['author_username']?.toString() ??
          event['author_id']?.toString() ??
          event['sender_id']?.toString() ??
          event['creator_username']?.toString() ??
          event['creator_id']?.toString() ??
          'system';
      final msgId = event['id']?.toString() ?? 'ws_${DateTime.now().millisecondsSinceEpoch}';

      String? fileInfoJson;
      if (decrypted != null && decrypted.trim().startsWith('{')) {
        try {
          final parsed = jsonDecode(decrypted);
          if (parsed is Map && (parsed['type'] == 'file' || parsed['type'] == 'voice' || parsed['type'] == 'video_message') && parsed['file_id'] != null) {
            fileInfoJson = decrypted;
          }
        } catch (_) {}
      }

      if (fileInfoJson == null) {
        final fileId = event['attached_file_id']?.toString();
        if (fileId != null) {
          final fileName = event['attached_file_name']?.toString() ?? 'file';
          final fileSize = event['attached_file_size'] as int? ?? 0;
          final fileType = event['attached_file_type']?.toString() ?? 'application/octet-stream';
          final fileUrlSuffix = event['attached_file_url']?.toString() ?? '/api/files/download/$fileId/';
          fileInfoJson = jsonEncode({
            'file_id': fileId,
            'file_name': fileName,
            'file_size': fileSize,
            'mime_type': fileType,
            'file_url': fileUrlSuffix,
          });
        }
      }

      String? messageType = event['message_type']?.toString();
      if (messageType == null) {
        if (type == 'todo_list_message') messageType = 'todo_list';
        if (type == 'poll_message') messageType = 'poll';
      }
      final messageId = event['message_id']?.toString();
      final completionStatusVal = event['completion_status'] != null ? jsonEncode(event['completion_status']) : null;
      final votesByOptionVal = event['votes_by_option'] != null ? jsonEncode(event['votes_by_option']) : null;

      final bool isAlreadyKnown = _initialMessageIds.contains(msgId) || _animatedMessageIds.contains(msgId);

      await _localChatRepo.saveMessage(
        MessagesCompanion(
          serverMessageId: Value(msgId),
          chatId: Value(localId),
          senderId: Value(senderId),
          textContent: Value(decrypted ?? encryptedText),
          timestamp: Value(timestamp),
          fileUrl: Value(fileInfoJson),
          messageType: Value(messageType),
          messageId: Value(messageId),
          completionStatus: Value(completionStatusVal),
          votesByOption: Value(votesByOptionVal),
        ),
      );

      if (!isAlreadyKnown) {
        _messagesToAnimate.add(msgId);
        if (mounted) {
          setState(() {
            _limit++;
            _updateStream();
          });
        }
      }

      // Mark the message as read on the server since we are viewing it
      _chatService.markMessagesAsRead(widget.chat.id);

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
        otherUser: _otherUser,
        isEncrypted: decrypted == null,
        isArchived: widget.chat.isArchived,
        archivedAt: widget.chat.archivedAt,
      );
      await _localChatRepo.saveChat(updatedChat);
    }
  }

  Future<void> _handleIncomingVoiceMessage(Map<String, dynamic> event) async {
    final chatId = event['chat_id']?.toString();
    if (chatId == null || chatId != widget.chat.id) return;

    final localId = _localChatId;
    if (localId == null) return;

    final fileId = event['file_id']?.toString();
    if (fileId == null) return;

    final timestamp = _parseDateTime(event['created_at']) ?? DateTime.now();
    final senderId = event['author_username']?.toString() ??
        event['author_id']?.toString() ??
        event['sender_id']?.toString() ??
        'system';
    final msgId = event['id']?.toString() ??
        event['message_id']?.toString() ??
        'ws_${timestamp.millisecondsSinceEpoch}';

    final duration = event['duration'] is num
        ? (event['duration'] as num).toInt()
        : int.tryParse(event['duration']?.toString() ?? '') ?? 0;
    final mimeType = event['mime_type']?.toString() ?? 'audio/wav';

    // Сверка с оптимистичной отправкой: если это эхо нашего же ГС,
    // схлопываем temp-сообщение в реальное (без дубля и без новой анимации),
    // сохраняя local_path — чтобы наше сообщение проигрывалось из локального файла.
    final String? tempId = _pendingVoiceTempIds.remove(fileId);
    final String? localPath = _pendingVoiceLocalPaths.remove(fileId);
    final bool isOwnEcho = tempId != null;

    if (isOwnEcho) {
      await _localChatRepo.deleteMessageByServerId(tempId);
      _messagesToAnimate.remove(tempId);
      _animatedMessageIds.add(msgId); // считаем уже "проявленным" — не анимируем заново
    }

    // Шаблон голосового: плеер сам подгрузит и расшифрует файл по file_id.
    // Для своего сообщения добавляем local_path для мгновенного проигрывания.
    final fileInfoJson = jsonEncode({
      'type': 'voice',
      'file_id': fileId,
      'duration': duration,
      'mime_type': mimeType,
      if (localPath != null) 'local_path': localPath,
    });

    final bool isAlreadyKnown = isOwnEcho ||
        _initialMessageIds.contains(msgId) ||
        _animatedMessageIds.contains(msgId);

    await _localChatRepo.saveMessage(
      MessagesCompanion(
        serverMessageId: Value(msgId),
        chatId: Value(localId),
        senderId: Value(senderId),
        textContent: Value(fileInfoJson),
        timestamp: Value(timestamp),
        fileUrl: Value(fileInfoJson),
        messageType: const Value('voice'),
      ),
    );

    if (!isAlreadyKnown) {
      _messagesToAnimate.add(msgId);
    }
    if (mounted) {
      setState(() {
        if (!isAlreadyKnown) _limit++;
        _updateStream();
      });
    }

    _chatService.markMessagesAsRead(widget.chat.id);

    final updatedChat = ChatModel(
      id: widget.chat.id,
      name: widget.chat.name,
      avatar: widget.chat.avatar,
      avatarGradient: widget.chat.avatarGradient,
      lastMessage: '🎤 Голосовое сообщение',
      lastMessageTime: timestamp,
      unreadCount: 0,
      isGroup: widget.chat.isGroup,
      isChannel: widget.chat.isChannel,
      isPersonal: widget.chat.isPersonal,
      isFavorites: widget.chat.isFavorites,
      otherUser: _otherUser,
      isEncrypted: false,
      isArchived: widget.chat.isArchived,
      archivedAt: widget.chat.archivedAt,
    );
    await _localChatRepo.saveChat(updatedChat);
  }

  Future<void> _handleIncomingVideoMessage(Map<String, dynamic> event) async {
    final chatId = event['chat_id']?.toString();
    if (chatId == null || chatId != widget.chat.id) return;

    final localId = _localChatId;
    if (localId == null) return;

    final fileId = event['file_id']?.toString();
    if (fileId == null) return;

    final timestamp = _parseDateTime(event['created_at']) ?? DateTime.now();
    final senderId = event['author_username']?.toString() ??
        event['author_id']?.toString() ??
        event['sender_id']?.toString() ??
        'system';
    final msgId = event['id']?.toString() ??
        event['message_id']?.toString() ??
        'ws_${timestamp.millisecondsSinceEpoch}';

    final duration = event['duration'] is num
        ? (event['duration'] as num).toDouble()
        : double.tryParse(event['duration']?.toString() ?? '') ?? 0.0;

    final String? tempId = _pendingVideoTempIds.remove(fileId);
    final String? localPath = _pendingVideoLocalPaths.remove(fileId);
    final bool isOwnEcho = tempId != null;

    if (isOwnEcho) {
      await _localChatRepo.deleteMessageByServerId(tempId);
      _messagesToAnimate.remove(tempId);
      _animatedMessageIds.add(msgId);
    }

    final fileInfoJson = jsonEncode({
      'type': 'video_message',
      'file_id': fileId,
      'duration': duration,
      'mime_type': 'video/mp4',
      if (localPath != null) 'local_path': localPath,
    });

    final bool isAlreadyKnown = isOwnEcho ||
        _initialMessageIds.contains(msgId) ||
        _animatedMessageIds.contains(msgId);

    await _localChatRepo.saveMessage(
      MessagesCompanion(
        serverMessageId: Value(msgId),
        chatId: Value(localId),
        senderId: Value(senderId),
        textContent: Value(fileInfoJson),
        timestamp: Value(timestamp),
        fileUrl: Value(fileInfoJson),
        messageType: const Value('video_message'),
        messageId: Value(msgId),
      ),
    );

    if (!isAlreadyKnown) {
      _messagesToAnimate.add(msgId);
    }
    if (mounted) {
      setState(() {
        if (!isAlreadyKnown) _limit++;
        _updateStream();
      });
    }

    _chatService.markMessagesAsRead(widget.chat.id);

    final updatedChat = ChatModel(
      id: widget.chat.id,
      name: widget.chat.name,
      avatar: widget.chat.avatar,
      avatarGradient: widget.chat.avatarGradient,
      lastMessage: '📹 Видеосообщение',
      lastMessageTime: timestamp,
      unreadCount: 0,
      isGroup: widget.chat.isGroup,
      isChannel: widget.chat.isChannel,
      isPersonal: widget.chat.isPersonal,
      isFavorites: widget.chat.isFavorites,
      otherUser: _otherUser,
      isEncrypted: false,
      isArchived: widget.chat.isArchived,
      archivedAt: widget.chat.archivedAt,
    );
    await _localChatRepo.saveChat(updatedChat);
  }

  Future<String?> _insertOptimisticVideoMessage(String path, double duration) async {
    final localId = _localChatId;
    if (localId == null) return null;

    final currentUser = context.read<AuthProvider>().user;
    final senderId = currentUser?.username ?? currentUser?.id.toString() ?? 'me';
    final timestamp = DateTime.now();
    final tempId = 'temp_video_${timestamp.millisecondsSinceEpoch}';

    final fileInfoJson = jsonEncode({
      'type': 'video_message',
      'file_id': tempId,
      'duration': duration,
      'mime_type': 'video/mp4',
      'local_path': path,
    });

    await _localChatRepo.saveMessage(
      MessagesCompanion(
        serverMessageId: Value(tempId),
        chatId: Value(localId),
        senderId: Value(senderId),
        textContent: Value(fileInfoJson),
        timestamp: Value(timestamp),
        fileUrl: Value(fileInfoJson),
        messageType: const Value('video_message'),
        messageId: Value(tempId),
      ),
    );

    if (mounted) {
      setState(() {
        _limit++;
        _updateStream();
      });
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    final updatedChat = ChatModel(
      id: widget.chat.id,
      name: widget.chat.name,
      avatar: widget.chat.avatar,
      avatarGradient: widget.chat.avatarGradient,
      lastMessage: '📹 Видеосообщение (${duration.toStringAsFixed(1)} сек.)',
      lastMessageTime: timestamp,
      unreadCount: widget.chat.unreadCount,
      isGroup: widget.chat.isGroup,
      isChannel: widget.chat.isChannel,
      isPersonal: widget.chat.isPersonal,
      isFavorites: widget.chat.isFavorites,
      otherUser: _otherUser,
      isEncrypted: false,
      isArchived: widget.chat.isArchived,
      archivedAt: widget.chat.archivedAt,
    );
    await _localChatRepo.saveChat(updatedChat);

    return tempId;
  }

  Future<bool> _requestCameraPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    return cameraStatus.isGranted && micStatus.isGranted;
  }

  Future<CameraDescription?> _getCameraToUse() async {
    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
    }
    if (_cameras.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final savedDirection = prefs.getString('last_used_camera_lens_direction') ?? 'front';

    CameraDescription? selectedCamera;
    if (savedDirection == 'back') {
      selectedCamera = _cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
    } else {
      selectedCamera = _cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
    }
    return selectedCamera;
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2) return;
    if (_cameraController == null) return;

    final currentLens = _cameraController!.description.lensDirection;
    final nextLens = currentLens == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    final nextCam = _cameras.firstWhere(
      (cam) => cam.lensDirection == nextLens,
      orElse: () => _cameras.first,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'last_used_camera_lens_direction',
      nextLens == CameraLensDirection.back ? 'back' : 'front',
    );

    await _cameraController!.dispose();
    _cameraController = CameraController(
      nextCam,
      ResolutionPreset.medium,
      enableAudio: true,
    );

    try {
      await _cameraController!.initialize();
      if (_isRecordingVideo) {
        await _cameraController!.startVideoRecording();
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error toggling camera: $e');
    }
  }

  Future<void> _startVideoRecording() async {
    try {
      final hasPermission = await _requestCameraPermissions();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Требуется разрешение на камеру и микрофон')),
          );
        }
        return;
      }

      final camera = await _getCameraToUse();
      if (camera == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Камера не найдена')),
          );
        }
        return;
      }

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: true,
      );

      try {
        await Feedback.forLongPress(context);
      } catch (_) {}

      await _cameraController!.initialize();

      if (!_isHoldingButton) {
        await _cameraController!.dispose();
        _cameraController = null;
        return;
      }

      await _cameraController!.startVideoRecording();

      if (!_isHoldingButton) {
        try {
          await _cameraController!.stopVideoRecording();
        } catch (_) {}
        await _cameraController!.dispose();
        _cameraController = null;
        return;
      }

      _sendTypingEvent(true, action: 'recording_voice');

      if (mounted) {
        setState(() {
          _isRecordingVideo = true;
          _videoRecordingDurationSeconds = 0.0;
          _dragOffset = 0.0;
        });
      }

      _videoRecordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (mounted) {
          setState(() {
            _videoRecordingDurationSeconds += 0.1;
          });
          if (_videoRecordingDurationSeconds >= 60.0) {
            _stopAndSendVideoRecording();
          }
        }
      });
    } catch (e) {
      debugPrint('Error starting video recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка инициализации камеры: $e')),
        );
      }
    }
  }

  Future<void> _cancelVideoRecording() async {
    if (!_isRecordingVideo) return;
    try {
      _videoRecordingTimer?.cancel();
      _videoRecordingTimer = null;

      if (_cameraController != null) {
        try {
          final file = await _cameraController!.stopVideoRecording();
          final localFile = File(file.path);
          if (await localFile.exists()) {
            await localFile.delete();
          }
        } catch (_) {}
        await _cameraController!.dispose();
        _cameraController = null;
      }

      _sendTypingEvent(false);

      if (mounted) {
        setState(() {
          _isRecordingVideo = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Запись видео отменена'),
            backgroundColor: Colors.redAccent.withValues(alpha: 0.9),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error cancelling video recording: $e');
    }
  }

  Future<void> _stopAndSendVideoRecording() async {
    if (!_isRecordingVideo) return;
    try {
      _videoRecordingTimer?.cancel();
      _videoRecordingTimer = null;

      if (_cameraController == null) return;
      
      final XFile file;
      try {
        file = await _cameraController!.stopVideoRecording();
      } catch (e) {
        debugPrint('Error stopping video recording: $e');
        return;
      } finally {
        await _cameraController!.dispose();
        _cameraController = null;
      }

      _sendTypingEvent(false);

      final path = file.path;
      final duration = _videoRecordingDurationSeconds;

      if (mounted) {
        setState(() {
          _isRecordingVideo = false;
        });
      }

      if (duration < 1.0) {
        final localFile = File(path);
        if (await localFile.exists()) {
          await localFile.delete();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Слишком короткое видеосообщение'),
              backgroundColor: Colors.orangeAccent.withValues(alpha: 0.9),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        return;
      }

      final tempId = await _insertOptimisticVideoMessage(path, duration);
      await _uploadAndSendVideoMessage(path, duration, tempId);
    } catch (e) {
      debugPrint('Error stopping video recording: $e');
    }
  }

  Future<void> _uploadAndSendVideoMessage(String path, double duration, [String? tempId]) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;

      final filename = path.split('/').last;

      final formData = FormData.fromMap({
        'file_type': 'video_message',
        'chat_id': widget.chat.id,
        'file': await MultipartFile.fromFile(
          file.path,
          filename: filename,
        ),
        'duration': duration,
      });

      final apiClient = context.read<ApiClient>();

      final response = await apiClient.post(
        '/files/upload/',
        data: formData,
      );

      if (response.statusCode == 201 && response.data['success'] == true) {
        final fileId = response.data['file_id'] as String;

        if (tempId != null) {
          _pendingVideoTempIds[fileId] = tempId;
          _pendingVideoLocalPaths[fileId] = path;
        }

        final cryptoService = context.read<CryptoService>();

        final videoMetadata = jsonEncode({
          'type': 'video_message',
          'file_id': fileId,
          'duration': duration,
          'mime_type': 'video/mp4',
        });

        final encryptedText = await cryptoService.encryptMessage(videoMetadata, widget.chat.id);

        if (encryptedText != null) {
          await _chatWebSocketService.send({
            'type': 'video_message',
            'file_id': fileId,
            'duration': duration,
            'chat_id': widget.chat.id,
            'encrypted_text': encryptedText,
          });
        } else {
          await _chatWebSocketService.send({
            'type': 'video_message',
            'file_id': fileId,
            'duration': duration,
            'chat_id': widget.chat.id,
          });
        }
      } else {
        throw Exception('Failed to upload video message to backend');
      }
    } catch (e) {
      debugPrint('Error uploading video message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки видеосообщения: $e')),
        );
      }
    }
  }

  Future<void> _handleTodoCompletionUpdate(Map<String, dynamic> event) async {
    final messageId = event['todo_message_id']?.toString();
    final itemIndex = event['item_index'];
    final isCompleted = event['is_completed'] as bool?;

    if (messageId == null || itemIndex == null || isCompleted == null) return;

    final repo = context.read<LocalChatRepository>();
    final dbMsg = await repo.getMessageByMessageId(messageId);
    if (dbMsg != null) {
      final statusMap = dbMsg.completionStatus != null
          ? Map<String, dynamic>.from(jsonDecode(dbMsg.completionStatus!))
          : <String, dynamic>{};

      statusMap[itemIndex.toString()] = isCompleted;
      final updatedStatus = jsonEncode(statusMap);

      await repo.updateMessageCompanion(
        MessagesCompanion(
          id: Value(dbMsg.id),
          completionStatus: Value(updatedStatus),
        ),
      );
    }
  }

  Future<void> _handlePollVoteUpdate(Map<String, dynamic> event) async {
    final messageId = event['poll_message_id']?.toString();
    if (messageId == null) return;

    final optionId = event['option_id']?.toString();
    if (optionId == null) return;

    final removeVote = event['remove_vote'] == true;
    final userId = event['user_id']?.toString();
    final username = event['username']?.toString();

    final repo = context.read<LocalChatRepository>();
    final dbMsg = await repo.getMessageByMessageId(messageId);
    if (dbMsg != null) {
      // 1. Update userVotes (if this vote belongs to the current user)
      final currentUser = context.read<AuthProvider>().user;
      final isCurrentUser = (currentUser != null &&
          (userId == currentUser.id.toString() || username == currentUser.username));

      List<String> userVotes = [];
      if (dbMsg.userVotes != null && dbMsg.userVotes!.isNotEmpty) {
        try {
          userVotes = List<String>.from(jsonDecode(dbMsg.userVotes!));
        } catch (_) {}
      }

      if (isCurrentUser) {
        if (removeVote) {
          if (!userVotes.contains(optionId)) {
            // Vote already removed locally, skip duplicate increment/decrement
            return;
          }
          userVotes.remove(optionId);
        } else {
          if (userVotes.contains(optionId)) {
            // Vote already added locally, skip duplicate increment/decrement
            return;
          }
          userVotes.add(optionId);
        }
      }

      // 2. Update votesByOption
      Map<String, dynamic> votesByOption = {};
      if (dbMsg.votesByOption != null && dbMsg.votesByOption!.isNotEmpty) {
        try {
          votesByOption = Map<String, dynamic>.from(jsonDecode(dbMsg.votesByOption!));
        } catch (_) {}
      }

      final int currentOptionCount = votesByOption[optionId] is num
          ? (votesByOption[optionId] as num).toInt()
          : int.tryParse(votesByOption[optionId]?.toString() ?? '') ?? 0;

      if (removeVote) {
        votesByOption[optionId] = (currentOptionCount - 1).clamp(0, 999999);
      } else {
        votesByOption[optionId] = currentOptionCount + 1;
      }

      await repo.updateMessageCompanion(
        MessagesCompanion(
          id: Value(dbMsg.id),
          votesByOption: Value(jsonEncode(votesByOption)),
          userVotes: Value(jsonEncode(userVotes)),
        ),
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    final localId = _localChatId;
    if (localId == null) return;

    final cryptoService = context.read<CryptoService>();
    final timestamp = DateTime.now();
    // 1. Update chat preview locally
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
      otherUser: _otherUser,
      isEncrypted: false,
      isArchived: widget.chat.isArchived,
      archivedAt: widget.chat.archivedAt,
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
          'images': [],
          'image': null,
        });
      } else {
        debugPrint('SEND_MSG: encryption returned null, key not available for chat ${widget.chat.id}');
      }
    } catch (e) {
      debugPrint('Error sending E2EE message over WS: $e');
    }
  }

  Future<void> _sendPollMessage(String question, List<String> options, bool isMultipleChoice) async {
    final cryptoService = context.read<CryptoService>();
    final List<Map<String, String>> optionsList = options
        .asMap()
        .entries
        .map((e) => {'id': 'opt_${e.key}', 'text': e.value})
        .toList();

    final payload = jsonEncode({
      'type': 'poll',
      'question': question,
      'options': optionsList,
      'is_multiple_choice': isMultipleChoice,
      'is_native': true,
    });

    try {
      final encryptedText = await cryptoService.encryptMessage(payload, widget.chat.id);
      final encryptedQuestion = await cryptoService.encryptMessage(question, widget.chat.id);

      if (encryptedText != null && encryptedQuestion != null) {
        await _chatWebSocketService.send({
          'type': 'poll_message',
          'encrypted_content': encryptedText,
          'encrypted_question': encryptedQuestion,
          'question': question,
          'chat_id': widget.chat.id,
        });
      }
    } catch (e) {
      debugPrint('Error sending poll over WS: $e');
    }
  }

  Future<void> _sendTodoListMessage(String title, List<String> items) async {
    final cryptoService = context.read<CryptoService>();
    final List<Map<String, dynamic>> itemsList = items.map((item) => {
      'text': item,
      'completed': false,
    }).toList();

    final payload = jsonEncode({
      'type': 'todo_list',
      'title': title,
      'items': itemsList,
      'is_native': true,
    });

    try {
      final encryptedText = await cryptoService.encryptMessage(payload, widget.chat.id);
      final encryptedTitle = await cryptoService.encryptMessage(title, widget.chat.id);

      if (encryptedText != null && encryptedTitle != null) {
        await _chatWebSocketService.send({
          'type': 'todo_list_message',
          'encrypted_content': encryptedText,
          'encrypted_title': encryptedTitle,
          'title': title,
          'chat_id': widget.chat.id,
        });
      }
    } catch (e) {
      debugPrint('Error sending todo list over WS: $e');
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141416),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.08),
                width: 1.5,
              ),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.poll_rounded, color: Colors.white),
                  ),
                  title: const Text('Создать опрос', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text('Проведение голосования в чате', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    CreatePollModal.show(context, _sendPollMessage);
                  },
                ),
                Divider(color: Colors.white.withOpacity(0.04), height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_box_rounded, color: Colors.white),
                  ),
                  title: const Text('Создать To-Do список', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text('Список задач с отметками выполнения', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    CreateTodoModal.show(context, _sendTodoListMessage);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Требуется разрешение на запись аудио')),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      // Используем WAV (pcm16bits) для 100% гарантии точной перемотки (seek) на всех платформах.
      // Сжимаем sampleRate для уменьшения размера файла (24kHz достаточно для голоса).
      final path = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';

      // Haptic feedback
      try {
        await Feedback.forLongPress(context);
      } catch (_) {}

      await _audioRecorder.start(
        const RecordConfig(
          // AudioEncoder.wav = PCM16 С RIFF/WAVE заголовком.
          // pcm16bits писал headerless raw PCM → ffmpeg на бэке не мог его распознать,
          // а клиенты не могли декодировать. wav даёт валидный самодостаточный файл.
          encoder: AudioEncoder.wav,
          sampleRate: 24000,
          bitRate: 48000,
        ),
        path: path,
      );

      _sendTypingEvent(true, action: 'recording_voice');

      if (mounted) {
        setState(() {
          _isRecording = true;
          _recordingDurationSeconds = 0;
          _dragOffset = 0.0;
        });
      }

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _isRecording) {
          setState(() {
            _recordingDurationSeconds++;
          });
        }
      });
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      
      final path = await _audioRecorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      
      _sendTypingEvent(false);

      if (mounted) {
        setState(() {
          _isRecording = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Запись отменена'),
            backgroundColor: Colors.redAccent.withValues(alpha: 0.9),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error cancelling recording: $e');
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;

      final path = await _audioRecorder.stop();
      _sendTypingEvent(false);

      if (mounted) {
        setState(() {
          _isRecording = false;
        });
      }

      if (path == null) return;

      final duration = _recordingDurationSeconds;
      if (duration < 1) {
        // Delete file if too short
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Слишком короткое сообщение'),
              backgroundColor: Colors.orangeAccent.withValues(alpha: 0.9),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        return;
      }

      // Оптимистично показываем ГС СРАЗУ (играется из локального файла),
      // а загрузка/отправка идут в фоне.
      final tempId = await _insertOptimisticVoice(path, duration);

      // Upload file в фоне; tempId нужен для сверки с эхом сервера.
      await _uploadAndSendVoiceMessage(path, duration, tempId);
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  /// Вставляет локальное "temp" голосовое сообщение, которое отображается мгновенно
  /// и проигрывается прямо из записанного файла. Возвращает его serverMessageId (temp).
  Future<String?> _insertOptimisticVoice(String path, int duration) async {
    final localId = _localChatId;
    if (localId == null) return null;

    final currentUser = context.read<AuthProvider>().user;
    final senderId = currentUser?.username ?? currentUser?.id.toString() ?? 'me';
    final timestamp = DateTime.now();
    final tempId = 'temp_voice_${timestamp.millisecondsSinceEpoch}';

    final fileInfoJson = jsonEncode({
      'type': 'voice',
      'file_id': '',
      'duration': duration,
      'mime_type': 'audio/wav',
      'local_path': path,
    });

    await _localChatRepo.saveMessage(
      MessagesCompanion(
        serverMessageId: Value(tempId),
        chatId: Value(localId),
        senderId: Value(senderId),
        textContent: Value(fileInfoJson),
        timestamp: Value(timestamp),
        fileUrl: Value(fileInfoJson),
        messageType: const Value('voice'),
      ),
    );

    _messagesToAnimate.add(tempId);
    if (mounted) {
      setState(() {
        _limit++;
        _updateStream();
      });
    }

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    // Обновляем превью чата
    final updatedChat = ChatModel(
      id: widget.chat.id,
      name: widget.chat.name,
      avatar: widget.chat.avatar,
      avatarGradient: widget.chat.avatarGradient,
      lastMessage: '🎤 Голосовое сообщение',
      lastMessageTime: timestamp,
      unreadCount: 0,
      isGroup: widget.chat.isGroup,
      isChannel: widget.chat.isChannel,
      isPersonal: widget.chat.isPersonal,
      isFavorites: widget.chat.isFavorites,
      otherUser: _otherUser,
      isEncrypted: false,
      isArchived: widget.chat.isArchived,
      archivedAt: widget.chat.archivedAt,
    );
    await _localChatRepo.saveChat(updatedChat);

    return tempId;
  }

  Future<void> _uploadAndSendVoiceMessage(String path, int duration, [String? tempId]) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;

      final filename = path.split('/').last;

      final formData = FormData.fromMap({
        'file_type': 'audio',
        'chat_id': widget.chat.id,
        'file': await MultipartFile.fromFile(
          file.path,
          filename: filename,
        ),
        'mime_type': 'audio/wav',
      });

      final apiClient = context.read<ApiClient>();

      final response = await apiClient.post(
        '/files/upload/',
        data: formData,
      );

      if (response.statusCode == 201 && response.data['success'] == true) {
        final fileId = response.data['file_id'] as String;

        // Связываем temp-сообщение и локальный файл с реальным file_id,
        // чтобы эхо сервера схлопнулось в уже показанное сообщение.
        if (tempId != null) {
          _pendingVoiceTempIds[fileId] = tempId;
          _pendingVoiceLocalPaths[fileId] = path;
        }

        final cryptoService = context.read<CryptoService>();

        final voiceMetadata = jsonEncode({
          'type': 'voice',
          'file_id': fileId,
          'duration': duration,
          'mime_type': 'audio/wav',
        });

        final encryptedText = await cryptoService.encryptMessage(voiceMetadata, widget.chat.id);

        if (encryptedText != null) {
          await _chatWebSocketService.send({
            'type': 'voice_message',
            'file_id': fileId,
            'duration': duration,
            'chat_id': widget.chat.id,
            'encrypted_text': encryptedText,
          });
        } else {
          debugPrint('Failed to encrypt voice metadata');
        }
      } else {
        throw Exception('Failed to upload file to backend');
      }
    } catch (e) {
      debugPrint('Error uploading/sending voice: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки голосового сообщения: $e')),
        );
      }
    }
  }

  String _formatRecordingDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().user;

    return Provider<ChatWebSocketService>.value(
      value: _chatWebSocketService,
      child: Scaffold(
        backgroundColor: AppStyles.backgroundColor,
        resizeToAvoidBottomInset: true,
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(context),
        body: Stack(
          children: [
            // Stunning Liquid Glass Background decoration
            _buildGlassBackground(),

            // Main Chat Area
            Column(
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
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: _buildInputArea(context),
                  ),
                ),
              ],
            ),

            // Mini Media Player
            _buildMiniPlayer(),

            if (_isRecordingVideo && _cameraController != null && _cameraController!.value.isInitialized)
              _buildVideoRecordingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoRecordingOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          // 1. Background dimmer & preview circle - ignores pointer events to prevent blocking input gestures underneath
          IgnorePointer(
            ignoring: true,
            child: Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 15,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: ClipOval(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: 260,
                              height: 260 * _cameraController!.value.aspectRatio,
                              child: CameraPreview(_cameraController!),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _formatRecordingDuration(_videoRecordingDurationSeconds.toInt()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Удерживайте кнопку для записи',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Interactive overlay controls - positioned to be clickable without overlapping the record button
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.of(context).size.height / 2 + 180,
            child: Center(
              child: GestureDetector(
                onTap: _toggleCamera,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.flip_camera_ios,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPlayer() {
    final topOffset = MediaQuery.of(context).padding.top + 64; // Under the AppBar
    // Positioned всегда в дереве (он в Stack). Анимация появления/исчезновения
    // делается внутри через AnimatedSwitcher: slide-down + fade на появление,
    // slide-up + fade на исчезновение.
    return Positioned(
      top: topOffset,
      left: 16,
      right: 16,
      child: Consumer<PlaybackProvider>(
        builder: (context, playbackProvider, child) {
          final isVisible = playbackProvider.currentAudioUrl != null;
          final isPlaying = playbackProvider.isPlaying;
          final title = playbackProvider.title;
          final subtitle = playbackProvider.subtitle;

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (widget, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.6),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: widget,
                ),
              );
            },
            child: isVisible
                ? Container(
                    key: const ValueKey('mini_player_visible'),
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xE6141416), // frosted look
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        // Play/Pause
                        GestureDetector(
                          onTap: () {
                            if (isPlaying) {
                              playbackProvider.pause();
                            } else {
                              playbackProvider.resume();
                            }
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Title and subtitle
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: AppStyles.fontFamily,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 10,
                                  fontFamily: AppStyles.fontFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Close button
                        GestureDetector(
                          onTap: () => playbackProvider.stop(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white.withOpacity(0.4),
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('mini_player_hidden')),
          );
        },
      ),
    );
  }

  // Pre-cached color constants — avoids creating new Color objects on every build
  static const _glowIndigo = Color(0x3F6366F1);      // 0.25 opacity
  static const _glowIndigoT = Color(0x006366F1);      // 0.0 opacity
  static const _glowFuchsia = Color(0x2ED946EF);       // 0.18 opacity
  static const _glowFuchsiaT = Color(0x00D946EF);      // 0.0 opacity
  static const _glassTint = Color(0xD9000000);          // ~0.85 opacity replaces blur+0.75

  Widget _buildGlassBackground() {
    // Instead of BackdropFilter (which recomputes blur every frame during scroll),
    // we use a solid dark layer over subtle gradient orbs.
    // This achieves the same "frosted glass" visual at zero GPU cost.
    return Stack(
      children: [
        // Floating glow bubble 1 (Top right)
        Positioned(
          top: -40,
          right: -40,
          child: Container(
            width: 280,
            height: 280,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_glowIndigo, _glowIndigoT],
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
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_glowFuchsia, _glowFuchsiaT],
              ),
            ),
          ),
        ),
        // Semi-transparent dark overlay (replaces BackdropFilter blur)
        Positioned.fill(
          child: Container(
            color: _glassTint,
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderDroplet({
    required Widget child,
    VoidCallback? onTap,
    bool isCircle = true,
  }) {
    final borderRadius = isCircle ? null : BorderRadius.circular(20);
    return Container(
      width: isCircle ? 40 : null,
      height: 40,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: borderRadius,
        color: Colors.white.withOpacity(0.08),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: onTap != null
            ? InkWell(
                customBorder: isCircle ? const CircleBorder() : null,
                borderRadius: borderRadius,
                onTap: onTap,
                child: Center(child: child),
              )
            : Center(child: child),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    // Replaced BackdropFilter with solid semi-transparent background.
    // BackdropFilter on AppBar was recomputing blur on every scroll frame
    // because extendBodyBehindAppBar makes the list scroll underneath.
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
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
          onTap: () {
            final currentChat = ChatModel(
              id: widget.chat.id,
              name: widget.chat.name,
              avatar: widget.chat.avatar,
              avatarGradient: widget.chat.avatarGradient,
              lastMessage: widget.chat.lastMessage,
              lastMessageTime: widget.chat.lastMessageTime,
              unreadCount: widget.chat.unreadCount,
              isGroup: widget.chat.isGroup,
              isChannel: widget.chat.isChannel,
              isPersonal: widget.chat.isPersonal,
              isFavorites: widget.chat.isFavorites,
              otherUser: _otherUser,
              isEncrypted: widget.chat.isEncrypted,
            );
            ChatInfoModal.show(context, currentChat);
          },
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
                    _buildAppBarSubtitle(),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_canCall()) ...[
            Center(
              child: _buildHeaderDroplet(
                isCircle: true,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Звонок в чат "${widget.chat.name}"...'),
                      duration: const Duration(seconds: 2),
                      backgroundColor: const Color(0xFF1E1E22),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                },
                child: const FaIcon(FontAwesomeIcons.phone, color: Colors.white70, size: 16),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Center(
            child: PopupMenuButton<String>(
              offset: const Offset(0, 48),
              color: const Color(0xFF16161A),
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              onSelected: _handleMenuAction,
              itemBuilder: (context) => _buildMenuItems(),
              child: _buildHeaderDroplet(
                isCircle: true,
                onTap: null,
                child: const FaIcon(FontAwesomeIcons.ellipsisVertical, color: Colors.white70, size: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  bool _isDeleted() {
    final name = widget.chat.name.toLowerCase();
    if (name.contains('удаленный') || 
        name.contains('удалённый') || 
        name.contains('deleted')) {
      return true;
    }
    if (_otherUser != null) {
      final other = _otherUser!;
      if (other['is_deleted'] == true || 
          other['deleted'] == true ||
          other['status'] == 'deleted') {
        return true;
      }
    }
    return false;
  }

  bool _isBot() {
    if (_otherUser != null) {
      final other = _otherUser!;
      if (other['is_bot'] == true || other['bot'] == true) {
        return true;
      }
      final username = other['username']?.toString().toLowerCase() ?? '';
      if (username.endsWith('bot')) {
        return true;
      }
    }
    if (widget.chat.name.toLowerCase().endsWith('bot')) {
      return true;
    }
    return false;
  }

  bool _canCall() {
    final chat = widget.chat;

    // 1. Избранное -> звонки запрещены
    if (chat.isFavorites) return false;

    // 2. Каналы -> звонки запрещены
    if (chat.isChannel) return false;

    // 3. Личные чаты (собеседники)
    if (chat.isPersonal) {
      if (_isBot() || _isDeleted()) return false;

      // Проверяем настройки приватности с бэка в Map otherUser
      final other = _otherUser;
      if (other != null) {
        if (other['allow_calls'] == false ||
            other['can_call'] == false ||
            other['calls_allowed'] == false ||
            other['calls_enabled'] == false) {
          return false;
        }
      }
      return true;
    }

    // 4. Группы
    if (chat.isGroup) {
      final other = _otherUser;
      if (other != null) {
        if (other['allow_calls'] == false ||
            other['can_call'] == false ||
            other['calls_allowed'] == false ||
            other['calls_enabled'] == false ||
            other['voice_calls_enabled'] == false) {
          return false;
        }
      }
      return true;
    }

    return false;
  }

  String _pluralizeParticipants(int count) {
    if (count % 10 == 1 && count % 100 != 11) {
      return '$count участник';
    } else if ([2, 3, 4].contains(count % 10) && ![12, 13, 14].contains(count % 100)) {
      return '$count участника';
    } else {
      return '$count участников';
    }
  }

  String _formatSubscribers(int count) {
    if (count < 1000) {
      if (count % 10 == 1 && count % 100 != 11) {
        return '$count подписчик';
      } else if ([2, 3, 4].contains(count % 10) && ![12, 13, 14].contains(count % 100)) {
        return '$count подписчика';
      } else {
        return '$count подписчиков';
      }
    }
    
    String formatted;
    if (count < 1000000) {
      final kVal = count / 1000.0;
      formatted = '${_formatDecimal(kVal)}K';
    } else if (count < 1000000000) {
      final mVal = count / 1000000.0;
      formatted = '${_formatDecimal(mVal)}M';
    } else {
      final bVal = count / 1000000000.0;
      formatted = '${_formatDecimal(bVal)}B';
    }
    return '$formatted подписчиков';
  }

  String _formatDecimal(double value) {
    if (value == value.toInt().toDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  String _formatUserStatus(Map<String, dynamic>? otherUser) {
    if (otherUser == null) return '';
    
    if (otherUser['is_online'] == true || otherUser['online'] == true) {
      return 'в сети';
    }
    
    final lastSeenVal = otherUser['last_seen'] ?? otherUser['last_login'] ?? otherUser['last_activity'];
    if (lastSeenVal == null) return 'был(-а) недавно';
    
    DateTime? lastSeen;
    if (lastSeenVal is String) {
      lastSeen = DateTime.tryParse(lastSeenVal);
    } else if (lastSeenVal is int) {
      lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenVal);
    } else if (lastSeenVal is DateTime) {
      lastSeen = lastSeenVal;
    }
    
    if (lastSeen == null) return 'был(-а) недавно';
    
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (difference.inMinutes < 1) {
      return 'был(-а) только что';
    }
    
    if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      String minStr;
      if (mins % 10 == 1 && mins % 100 != 11) {
        minStr = 'минуту';
      } else if ([2, 3, 4].contains(mins % 10) && ![12, 13, 14].contains(mins % 100)) {
        minStr = 'минуты';
      } else {
        minStr = 'минут';
      }
      return 'был(-а) в сети $mins $minStr назад';
    }
    
    final today = DateTime(now.year, now.month, now.day);
    final lastSeenDay = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);
    
    final hour = lastSeen.hour.toString().padLeft(2, '0');
    final minute = lastSeen.minute.toString().padLeft(2, '0');
    
    if (lastSeenDay == today) {
      return 'был(-а) в сети сегодня в $hour:$minute';
    }
    
    final yesterday = today.subtract(const Duration(days: 1));
    if (lastSeenDay == yesterday) {
      return 'был(-а) в сети вчера в $hour:$minute';
    }
    
    final day = lastSeen.day.toString().padLeft(2, '0');
    final month = lastSeen.month.toString().padLeft(2, '0');
    return 'был(-а) в сети $day.$month.${lastSeen.year} в $hour:$minute';
  }

  Widget _buildAppBarSubtitle() {
    if (widget.chat.isFavorites || _isDeleted()) {
      return const SizedBox.shrink();
    }

    String statusText = '';
    dynamic icon;
    Color color = const Color(0xE6A1A1AA); // light gray (~0.9 opacity)
    String? lottiePath;

    if (widget.chat.isPersonal) {
      if (_isBot()) {
        statusText = 'бот';
        icon = FontAwesomeIcons.robot;
      } else {
        if (_typingText != null) {
          statusText = _typingText!;
          color = const Color(0xFF38BDF8); // sky blue for typing
          lottiePath = _activeLottiePath;
        } else {
          statusText = _formatUserStatus(_otherUser);
          if (statusText == 'в сети') {
            color = const Color(0xE64ADE80); // green for online
          }
        }
      }
    } else if (widget.chat.isGroup) {
      if (_typingUsers.isNotEmpty) {
        statusText = _typingUsers.values.join(', ');
        color = const Color(0xFF38BDF8); // sky blue for typing
        lottiePath = _typingLottiePaths.isNotEmpty ? _typingLottiePaths.values.first : null;
      } else {
        final membersCount = _otherUser?['members_count'] as int? ?? 0;
        final onlineCount = _otherUser?['online_count'] as int? ?? 0;
        
        statusText = _pluralizeParticipants(membersCount);
        if (onlineCount > 0) {
          statusText += ', $onlineCount в сети';
        }
      }
      icon = FontAwesomeIcons.users;
    } else if (widget.chat.isChannel) {
      final subscribersCount = _otherUser?['subscribers_count'] as int? ?? 0;
      statusText = _formatSubscribers(subscribersCount);
      icon = FontAwesomeIcons.bullhorn;
    }

    if (statusText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (lottiePath != null) ...[
            SizedBox(
              height: 14,
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                child: Lottie.asset(
                  lottiePath,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ] else if (icon != null) ...[
            FaIcon(
              icon,
              size: 11,
              color: color,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            statusText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
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
        // Prevent full-screen loading spinner flicker when switching/re-subscribing to the stream
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.white54));
        }

        final messages = snapshot.data ?? [];

        if (messages.isEmpty && _isHistoryLoading) {
          return const Center(child: CircularProgressIndicator(color: Colors.white54));
        }

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

        if (!_isInitialLoadDone && messages.isNotEmpty) {
          _initialMessageIds.addAll(messages.map((m) => m.serverMessageId));
          _isInitialLoadDone = true;
        }

        final topPadding = MediaQuery.of(context).padding.top + 64 + 16;
        final showSpinner = _isHistoryLoading && _hasMoreMessages;

        return ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.only(top: topPadding, bottom: 16),
          reverse: true, // Newer messages at the bottom
          itemCount: messages.length + (showSpinner ? 1 : 0),
          cacheExtent: 600, // Кешируем виджеты в пределах 600 пикселей для плавной прокрутки без пересборок
          itemBuilder: (context, index) {
            if (index == messages.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                    ),
                  ),
                ),
              );
            }
            final msg = messages[index];
            final isMe = msg.senderId == currentUser?.username || msg.senderId == currentUser?.id.toString();
            final senderRealName = isMe 
              ? (currentUser?.username ?? 'Вы') 
              : (widget.chat.isGroup ? msg.senderId : widget.chat.name);

            final bool isNewMessage = _messagesToAnimate.contains(msg.serverMessageId);

            return NewMessageAnimator(
              key: ValueKey('anim_${msg.serverMessageId}'),
              animate: isNewMessage,
              onStartAnimating: isNewMessage
                  ? () {
                      _messagesToAnimate.remove(msg.serverMessageId);
                      _animatedMessageIds.add(msg.serverMessageId);
                    }
                  : null,
              child: MessageBubble(
                key: ValueKey(msg.serverMessageId),
                message: msg,
                isMe: isMe,
                currentUser: currentUser,
                jwtToken: _jwtToken,
                senderRealName: senderRealName,
              ),
            );
          },
        );
      },
    );
  }



  Widget _buildInputArea(BuildContext context) {
    // Removed BackdropFilter — it was recomputing blur on every rebuild.
    // Using a solid dark container instead for the same frosted look.
    return Container(
      decoration: BoxDecoration(
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000), // 0.15 opacity
            blurRadius: 25,
            spreadRadius: -5,
            offset: Offset(0, 8),
          ),
        ],
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          TextField(
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
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
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
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 15),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.25),
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
                      color: Colors.white.withValues(alpha: 0.55),
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
                      onTap: _showAttachmentMenu,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: FaIcon(
                          FontAwesomeIcons.plus,
                          color: Colors.white.withValues(alpha: 0.65),
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
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.white.withValues(alpha: 0.2),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: FaIcon(
                                        FontAwesomeIcons.arrowUp,
                                        color: Colors.black,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                )
                              : GestureDetector(
                                  key: const ValueKey('mic_video_toggle'),
                                  onLongPressStart: (_) async {
                                    _isHoldingButton = true;
                                    if (_isVoiceMode) {
                                      await _startRecording();
                                    } else {
                                      await _startVideoRecording();
                                    }
                                  },
                                  onLongPressMoveUpdate: (details) {
                                    if (_isVoiceMode && _isRecording) {
                                      setState(() {
                                        _dragOffset = details.offsetFromOrigin.dx.clamp(-120.0, 0.0);
                                      });
                                      if (_dragOffset < -100) {
                                        _isHoldingButton = false;
                                        _cancelRecording();
                                      }
                                    } else if (!_isVoiceMode && _isRecordingVideo) {
                                      setState(() {
                                        _dragOffset = details.offsetFromOrigin.dx.clamp(-120.0, 0.0);
                                      });
                                      if (_dragOffset < -100) {
                                        _isHoldingButton = false;
                                        _cancelVideoRecording();
                                      }
                                    }
                                  },
                                  onLongPressEnd: (_) async {
                                    _isHoldingButton = false;
                                    if (_isVoiceMode && _isRecording) {
                                      await _stopAndSendRecording();
                                    } else if (!_isVoiceMode && _isRecordingVideo) {
                                      await _stopAndSendVideoRecording();
                                    }
                                  },
                                  onLongPressCancel: () async {
                                    _isHoldingButton = false;
                                    if (_isVoiceMode) {
                                      await _cancelRecording();
                                    } else {
                                      await _cancelVideoRecording();
                                    }
                                  },
                                  onTap: () {
                                    setState(() {
                                      _isVoiceMode = !_isVoiceMode;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: (_isRecording || _isRecordingVideo) ? 42 : 38,
                                    height: (_isRecording || _isRecordingVideo) ? 42 : 38,
                                    decoration: BoxDecoration(
                                      color: (_isRecording || _isRecordingVideo) ? Colors.red : Colors.white.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 300),
                                        transitionBuilder: (Widget child, Animation<double> animation) {
                                          return RotationTransition(
                                            turns: child.key == const ValueKey('mic')
                                                ? Tween<double>(begin: 0.15, end: 0.0).animate(animation)
                                                : Tween<double>(begin: -0.15, end: 0.0).animate(animation),
                                            child: ScaleTransition(
                                              scale: animation,
                                              child: FadeTransition(
                                                opacity: animation,
                                                child: child,
                                              ),
                                            ),
                                          );
                                        },
                                        child: FaIcon(
                                          _isVoiceMode
                                              ? FontAwesomeIcons.microphone
                                              : FontAwesomeIcons.video,
                                          key: ValueKey(_isVoiceMode ? 'mic' : 'video'),
                                          color: Colors.white,
                                          size: (_isRecording || _isRecordingVideo) ? 18 : 16,
                                        ),
                                      ),
                                    ),
                                  ),
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
          if (_isRecording)
            Positioned(
              left: 4,
              top: 4,
              bottom: 4,
              right: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  color: const Color(0xFF161618),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const _BlinkingRedDot(),
                      const SizedBox(width: 10),
                      Text(
                        _formatRecordingDuration(_recordingDurationSeconds),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Transform.translate(
                        offset: Offset(_dragOffset, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chevron_left, 
                              color: Colors.white.withValues(alpha: 0.5), 
                              size: 16,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Смахните для отмены',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5), 
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isRecordingVideo)
            Positioned(
              left: 4,
              top: 4,
              bottom: 4,
              right: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  color: const Color(0xFF161618),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const _BlinkingRedDot(),
                      const SizedBox(width: 10),
                      Text(
                        _formatRecordingDuration(_videoRecordingDurationSeconds.toInt()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Transform.translate(
                        offset: Offset(_dragOffset, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chevron_left, 
                              color: Colors.white.withValues(alpha: 0.5), 
                              size: 16,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Смахните для отмены',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5), 
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
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

  Future<void> _fetchChatDetails() async {
    if (widget.chat.isFavorites || widget.chat.isPersonal) {
      return;
    }
    
    try {
      final apiClient = context.read<ApiClient>();
      final String endpoint;
      if (widget.chat.isGroup) {
        final groupId = widget.chat.id.replaceFirst('group_', '');
        endpoint = '/groups/$groupId/';
      } else if (widget.chat.isChannel) {
        final channelId = widget.chat.id.replaceFirst('channel_', '');
        endpoint = '/channels/$channelId/';
      } else {
        return;
      }
      
      final response = await apiClient.get(endpoint);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final isOwner = data['is_creator'] == true || data['is_owner'] == true;
          if (mounted) {
            setState(() {
              _isOwner = isOwner;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching chat details: $e');
    }
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    final List<PopupMenuEntry<String>> items = [];

    PopupMenuItem<String> buildItem({
      required String value,
      required FaIconData icon,
      required String text,
      bool isDanger = false,
    }) {
      return PopupMenuItem<String>(
        value: value,
        height: 44,
        child: Row(
          children: [
            FaIcon(
              icon,
              size: 16,
              color: isDanger ? Colors.redAccent : Colors.white70,
            ),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isDanger ? Colors.redAccent : Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.chat.isPersonal) {
      items.add(buildItem(
        value: 'search',
        icon: FontAwesomeIcons.magnifyingGlass,
        text: 'Поиск',
      ));
      items.add(buildItem(
        value: 'clear',
        icon: FontAwesomeIcons.trash,
        text: 'Очистить историю',
      ));
      if (!_isBot() && !_isDeleted()) {
        items.add(buildItem(
          value: 'delete',
          icon: FontAwesomeIcons.trashCan,
          text: 'Удалить чат',
          isDanger: true,
        ));
      }
    } else if (widget.chat.isFavorites) {
      items.add(buildItem(
        value: 'search',
        icon: FontAwesomeIcons.magnifyingGlass,
        text: 'Поиск',
      ));
      items.add(buildItem(
        value: 'clear',
        icon: FontAwesomeIcons.trash,
        text: 'Очистить историю',
      ));
    } else if (widget.chat.isChannel) {
      if (_isOwner) {
        items.add(buildItem(
          value: 'clear',
          icon: FontAwesomeIcons.trash,
          text: 'Очистить историю',
        ));
        items.add(buildItem(
          value: 'search',
          icon: FontAwesomeIcons.magnifyingGlass,
          text: 'Поиск',
        ));
        items.add(buildItem(
          value: 'delete',
          icon: FontAwesomeIcons.trashCan,
          text: 'Удалить канал',
          isDanger: true,
        ));
      } else {
        items.add(buildItem(
          value: 'search',
          icon: FontAwesomeIcons.magnifyingGlass,
          text: 'Поиск',
        ));
        items.add(buildItem(
          value: 'report',
          icon: FontAwesomeIcons.flag,
          text: 'Пожаловаться',
        ));
      }
    } else if (widget.chat.isGroup) {
      if (_isOwner) {
        items.add(buildItem(
          value: 'edit',
          icon: FontAwesomeIcons.pen,
          text: 'Редактировать группу',
        ));
        items.add(buildItem(
          value: 'search',
          icon: FontAwesomeIcons.magnifyingGlass,
          text: 'Поиск',
        ));
        items.add(buildItem(
          value: 'clear',
          icon: FontAwesomeIcons.trash,
          text: 'Очистить историю',
        ));
        items.add(buildItem(
          value: 'delete',
          icon: FontAwesomeIcons.trashCan,
          text: 'Удалить группу',
          isDanger: true,
        ));
        items.add(buildItem(
          value: 'leave',
          icon: FontAwesomeIcons.rightFromBracket,
          text: 'Покинуть группу',
          isDanger: true,
        ));
      } else {
        items.add(buildItem(
          value: 'search',
          icon: FontAwesomeIcons.magnifyingGlass,
          text: 'Поиск',
        ));
        items.add(buildItem(
          value: 'clear',
          icon: FontAwesomeIcons.trash,
          text: 'Очистить историю',
        ));
        items.add(buildItem(
          value: 'report',
          icon: FontAwesomeIcons.flag,
          text: 'Пожаловаться',
        ));
        items.add(buildItem(
          value: 'leave',
          icon: FontAwesomeIcons.rightFromBracket,
          text: 'Покинуть группу',
          isDanger: true,
        ));
      }
    }

    return items;
  }

  void _handleMenuAction(String value) {
    switch (value) {
      case 'search':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Поиск сообщений временно недоступен в мобильной версии'),
            backgroundColor: Color(0xFF1E1E22),
          ),
        );
        break;
      case 'clear':
        _confirmClearHistory();
        break;
      case 'delete':
        _confirmDeleteChat();
        break;
      case 'report':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Жалоба отправлена модераторам'),
            backgroundColor: Colors.green,
          ),
        );
        break;
      case 'edit':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Редактирование группы временно недоступно в мобильной версии'),
            backgroundColor: Color(0xFF1E1E22),
          ),
        );
        break;
      case 'leave':
        _confirmLeaveGroup();
        break;
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('Очистить историю', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Вы уверены, что хотите очистить историю сообщений в этом чате? Это действие нельзя отменить.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Очистить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearHistory();
    }
  }

  Future<void> _clearHistory() async {
    try {
      final apiClient = context.read<ApiClient>();
      
      final String chatType;
      if (widget.chat.isFavorites) {
        chatType = 'favorites';
      } else if (widget.chat.isChannel) {
        chatType = 'channel';
      } else if (widget.chat.isGroup) {
        chatType = 'group';
      } else {
        chatType = 'personal';
      }

      final response = await apiClient.post(
        '/../clear-chat-history/',
        data: {
          'chat_id': widget.chat.id,
          'chat_type': chatType,
        },
      );

      if (response.statusCode == 200) {
        final localId = _localChatId;
        if (localId != null) {
          await _localChatRepo.deleteMessagesForChat(localId);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('История чата "${widget.chat.name}" успешно очищена'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error clearing chat history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при очистке истории: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteChat() async {
    final String titleText;
    final String contentText;
    if (widget.chat.isChannel) {
      titleText = 'Удалить канал';
      contentText = 'Вы уверены, что хотите удалить канал "${widget.chat.name}"? Все подписчики будут удалены, а история очищена.';
    } else if (widget.chat.isGroup) {
      titleText = 'Удалить группу';
      contentText = 'Вы уверены, что хотите удалить группу "${widget.chat.name}"? Все участники будут удалены, а история очищена.';
    } else {
      titleText = 'Удалить чат';
      contentText = 'Вы уверены, что хотите удалить чат "${widget.chat.name}"? Все сообщения будут безвозвратно удалены.';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: Text(titleText, style: const TextStyle(color: Colors.white)),
        content: Text(contentText, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteChatAction();
    }
  }

  Future<void> _deleteChatAction() async {
    try {
      final apiClient = context.read<ApiClient>();
      
      final response = await apiClient.post(
        '/../delete-chat/',
        data: {
          'chat_id': widget.chat.id,
        },
      );

      if (response.statusCode == 200) {
        await _localChatRepo.deleteChatByServerId(widget.chat.id);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Чат "${widget.chat.name}" успешно удален'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('Error deleting chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении чата: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _confirmLeaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('Покинуть группу', style: TextStyle(color: Colors.white)),
        content: Text(
          'Вы уверены, что хотите покинуть группу "${widget.chat.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Выйти', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _leaveGroupAction();
    }
  }

  Future<void> _leaveGroupAction() async {
    try {
      final apiClient = context.read<ApiClient>();
      final groupId = widget.chat.id.replaceFirst('group_', '');
      
      final response = await apiClient.post('/groups/$groupId/leave/');

      if (response.statusCode == 200) {
        await _localChatRepo.deleteChatByServerId(widget.chat.id);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Вы покинули группу "${widget.chat.name}"'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('Error leaving group: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при выходе из группы: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
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

class FormattedText extends StatelessWidget {
  final String content;
  final TextStyle baseStyle;

  const FormattedText({
    super.key,
    required this.content,
    required this.baseStyle,
  });

  static final RegExp _regExp = RegExp(
    r'(\*\*(.*?)\*\*)|(\*(.*?)\*)|(__(.*?)__)|(_(.*?)_)|(`(.*?)`)|(~~(.*?)~~)|([^\*_`~]+|[\*_`~])',
  );

  // Simple check: if the text has no formatting markers at all, skip regex
  static final RegExp _hasMarkers = RegExp(r'[*_`~]');

  // Cached code-highlight background color
  static const _codeBg = Color(0x1FFFFFFF); // ~0.12 white
  static const _codeColor = Color(0xFF4ADE80);

  // ── Static memoization cache ────────────────────────────────────
  // Key: content string, Value: pre-built TextSpan.
  // Avoids re-running regex on every build frame during scroll.
  // Bounded to last 200 messages to prevent unbounded memory growth.
  static final Map<String, TextSpan> _cache = {};
  static const _maxCacheSize = 200;

  TextSpan _buildSpans() {
    // Check cache first
    final cached = _cache[content];
    if (cached != null) return cached;

    final rootStyle = baseStyle.copyWith(fontFamily: AppStyles.fontFamily);

    // Fast path: plain text (most messages)
    if (!_hasMarkers.hasMatch(content)) {
      final span = TextSpan(text: content, style: rootStyle);
      _addToCache(content, span);
      return span;
    }

    // Pre-compute style variants once (not per-match)
    final boldStyle = rootStyle.copyWith(fontWeight: FontWeight.bold);
    final italicStyle = rootStyle.copyWith(fontStyle: FontStyle.italic);
    final underlineStyle = rootStyle.copyWith(decoration: TextDecoration.underline);
    final codeStyle = rootStyle.copyWith(
      fontFamily: 'monospace',
      backgroundColor: _codeBg,
      color: _codeColor,
    );
    final strikeStyle = rootStyle.copyWith(decoration: TextDecoration.lineThrough);

    final List<TextSpan> spans = [];
    final matches = _regExp.allMatches(content);

    for (final Match match in matches) {
      final String fullMatch = match.group(0) ?? '';

      if (match.group(2) != null) {
        spans.add(TextSpan(text: match.group(2), style: boldStyle));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(text: match.group(4), style: italicStyle));
      } else if (match.group(6) != null) {
        spans.add(TextSpan(text: match.group(6), style: underlineStyle));
      } else if (match.group(8) != null) {
        spans.add(TextSpan(text: match.group(8), style: italicStyle));
      } else if (match.group(10) != null) {
        spans.add(TextSpan(text: match.group(10), style: codeStyle));
      } else if (match.group(12) != null) {
        spans.add(TextSpan(text: match.group(12), style: strikeStyle));
      } else {
        spans.add(TextSpan(text: fullMatch, style: rootStyle));
      }
    }

    final result = TextSpan(style: rootStyle, children: spans);
    _addToCache(content, result);
    return result;
  }

  static void _addToCache(String key, TextSpan value) {
    if (_cache.length >= _maxCacheSize) {
      // Evict oldest entries (first 50)
      final keysToRemove = _cache.keys.take(50).toList();
      for (final k in keysToRemove) {
        _cache.remove(k);
      }
    }
    _cache[key] = value;
  }

  @override
  Widget build(BuildContext context) {
    return RichText(text: _buildSpans());
  }
}


class NewMessageAnimator extends StatefulWidget {
  final Widget child;
  final bool animate;
  final VoidCallback? onStartAnimating;

  const NewMessageAnimator({
    super.key,
    required this.child,
    required this.animate,
    this.onStartAnimating,
  });

  @override
  State<NewMessageAnimator> createState() => _NewMessageAnimatorState();
}

class _NewMessageAnimatorState extends State<NewMessageAnimator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _sizeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    );

    _sizeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    if (widget.animate) {
      _controller.forward();
      if (widget.onStartAnimating != null) {
        // Run after current frame layout pass is finished to avoid triggering setState warnings
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onStartAnimating!();
        });
      }
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _sizeAnimation,
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: widget.child,
        ),
      ),
    );
  }
}


class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final UserModel? currentUser;
  final String? jwtToken;
  final String senderRealName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.currentUser,
    required this.jwtToken,
    required this.senderRealName,
  });

  // ── Pre-cached constants ─────────────────────────────────────────
  static const _myBubbleColor    = Color(0x1FFFFFFF);  // ~0.12 white
  static const _otherBubbleColor = Color(0x0AFFFFFF);  // ~0.04 white
  static const _borderColor      = Color(0x0DFFFFFF);  // ~0.05 white
  static const _systemBg         = Color(0x08FFFFFF);  // ~0.03 white
  static const _systemBorder     = Color(0x0DFFFFFF);  // ~0.05 white
  static const _systemIconColor  = Color(0xB34ADE80);  // ~0.7 green
  static const _systemTextColor  = Color(0x99FFFFFF);  // ~0.6 white
  static const _timeColor        = Color(0x59FFFFFF);  // ~0.35 white
  static const _checkColor       = Color(0x4DFFFFFF);  // ~0.3 white
  static const _checkReadColor   = Color(0xFF4ADE80);

  static const _myCorners = BorderRadius.only(
    topLeft: Radius.circular(18),
    topRight: Radius.circular(18),
    bottomLeft: Radius.circular(18),
    bottomRight: Radius.circular(4),
  );

  static const _otherCorners = BorderRadius.only(
    topLeft: Radius.circular(18),
    topRight: Radius.circular(18),
    bottomLeft: Radius.circular(4),
    bottomRight: Radius.circular(18),
  );

  static const _bodyStyle = TextStyle(
    color: Colors.white,
    fontSize: 14.5,
    height: 1.35,
    fontFamily: AppStyles.fontFamily,
  );

  static const _timeStyle = TextStyle(
    fontSize: 9.5,
    color: _timeColor,
    fontFamily: AppStyles.fontFamily,
  );

  static const _systemTextStyle = TextStyle(
    fontSize: 11,
    color: _systemTextColor,
    height: 1.3,
    fontFamily: AppStyles.fontFamily,
  );

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 Б';
    const suffixes = ['Б', 'КБ', 'МБ', 'ГБ'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Widget _buildDroplet({
    required Widget child,
    VoidCallback? onTap,
    bool isCircle = true,
  }) {
    final borderRadius = isCircle ? null : BorderRadius.circular(20);
    return Container(
      width: isCircle ? 40 : null,
      height: isCircle ? 40 : null,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: borderRadius,
        color: Colors.white.withOpacity(0.08),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: isCircle ? const CircleBorder() : null,
          borderRadius: borderRadius,
          onTap: onTap,
          child: Padding(
            padding: isCircle ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: isCircle ? Center(child: child) : child,
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl, String senderName, DateTime timestamp) {
    final timeStr = _formatTime(timestamp);
    final months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    final dateStr = '${timestamp.day} ${months[timestamp.month - 1]} в $timeStr';

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Image Viewer with Hero
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Hero(
                    tag: imageUrl,
                    child: Image.network(
                      imageUrl,
                      headers: jwtToken != null ? {'Authorization': 'Bearer $jwtToken'} : null,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint('FULLSCREEN IMAGE LOAD ERROR: $error');
                        debugPrint('FULLSCREEN IMAGE URL: $imageUrl');
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, color: Colors.white54, size: 64),
                              SizedBox(height: 16),
                              Text('Не удалось загрузить изображение', style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Animated UI elements
              FadeTransition(
                opacity: animation,
                child: Stack(
                  children: [
                    // Top Left: Back Button Droplet
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 16,
                      left: 16,
                      child: _buildDroplet(
                        isCircle: true,
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                      ),
                    ),

                    // Top Right: Context Menu Droplet
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 16,
                      right: 16,
                      child: _buildDroplet(
                        isCircle: true,
                        onTap: () {}, // Mock
                        child: const Icon(Icons.more_vert, color: Colors.white, size: 22),
                      ),
                    ),

                    // Bottom Center: Sender & Date Droplet
                    Positioned(
                      bottom: MediaQuery.paddingOf(context).bottom + 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _buildDroplet(
                          isCircle: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                senderName,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dateStr,
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadFileSilent(BuildContext context, String url, String fileName) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Скачивание $fileName...'), duration: const Duration(seconds: 1)),
      );
      
      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download/Xaneo');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        dir = await getDownloadsDirectory();
        if (dir != null) {
          dir = Directory('${dir.path}/Xaneo');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        } else {
          dir = await getApplicationDocumentsDirectory();
        }
      }

      final savePath = '${dir!.path}/$fileName';
      final dio = Dio();
      if (jwtToken != null) {
        dio.options.headers['Authorization'] = 'Bearer $jwtToken';
      }
      await dio.download(url, savePath);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл сохранен: $savePath')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка скачивания: $e')),
        );
      }
    }
  }

  void _showFullScreenVideo(BuildContext context, String videoUrl, String senderName, DateTime timestamp) {
    final timeStr = _formatTime(timestamp);
    final months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    final dateStr = '${timestamp.day} ${months[timestamp.month - 1]} в $timeStr';

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Video Player Viewer
              Center(
                child: _FullScreenVideoPlayer(videoUrl: videoUrl, jwtToken: jwtToken),
              ),

              // Animated UI elements
              FadeTransition(
                opacity: animation,
                child: Stack(
                  children: [
                    // Top Left: Back Button Droplet
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 16,
                      left: 16,
                      child: _buildDroplet(
                        isCircle: true,
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                      ),
                    ),

                    // Top Right: Context Menu Droplet
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 16,
                      right: 16,
                      child: _buildDroplet(
                        isCircle: true,
                        onTap: () {}, // Mock
                        child: const Icon(Icons.more_vert, color: Colors.white, size: 22),
                      ),
                    ),

                    // Bottom Center: Sender & Date Droplet
                    Positioned(
                      bottom: MediaQuery.paddingOf(context).bottom + 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _buildDroplet(
                          isCircle: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                senderName,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dateStr,
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url, String fileId) async {
    try {
      String finalUrl = url;
      // Если токен отсутствует в URL, попробуем получить новый токен доступа через API
      if (!url.contains('token=')) {
        try {
          final apiClient = context.read<ApiClient>();
          final response = await apiClient.post('/files/share/$fileId/', data: {'expires_in_days': 0});
          if (response.statusCode == 200 || response.statusCode == 201) {
            final token = response.data['token']?.toString();
            if (token != null) {
              final uri = Uri.parse(url);
              finalUrl = uri.replace(queryParameters: {
                ...uri.queryParameters,
                'token': token,
              }).toString();
            }
          }
        } catch (e) {
          // Игнорируем ошибку и пробуем открыть оригинальный URL
          debugPrint('Ошибка при получении токена доступа к файлу: $e');
        }
      }

      final uri = Uri.parse(finalUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw 'Не удалось открыть ссылку: $finalUrl';
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при открытии файла: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message.senderId == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _systemBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _systemBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FaIcon(FontAwesomeIcons.shield, color: _systemIconColor, size: 11),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message.textContent,
                  style: _systemTextStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Map<String, dynamic>? fileData;
    String displayContent = message.textContent;

    // 1. Попытка распарсить JSON из textContent (E2E шифрованный формат сообщения-файла)
    if (message.textContent.trim().startsWith('{')) {
      try {
        final parsed = jsonDecode(message.textContent);
        if (parsed is Map) {
          final pType = parsed['type'];
          if ((pType == 'file' || pType == 'voice' || pType == 'voice_message') && parsed['file_id'] != null) {
            fileData = Map<String, dynamic>.from(parsed);
            displayContent = ''; // Чистое файловое сообщение без текстовой подписи
          } else if (pType == 'todo_list' || pType == 'poll') {
            final isTodo = pType == 'todo_list';
            final isPoll = pType == 'poll';
            final isNative = parsed['is_native'] == true;
            final isTodoType = message.messageType == 'todo_list';
            final isPollType = message.messageType == 'poll';

            if ((isTodo && (isTodoType || isNative)) || (isPoll && (isPollType || isNative))) {
              fileData = Map<String, dynamic>.from(parsed);
              displayContent = '';
            }
          }
        }
      } catch (_) {}
    }

    // 2. Попытка распарсить JSON из поля fileUrl
    if (fileData == null && message.fileUrl != null && message.fileUrl!.isNotEmpty) {
      try {
        final parsed = jsonDecode(message.fileUrl!);
        if (parsed is Map) {
          fileData = Map<String, dynamic>.from(parsed);
          // Если в тексте сообщения была сериализованная копия JSON, очищаем отображение текста
          if (message.textContent.trim().startsWith('{')) {
            displayContent = '';
          }
        }
      } catch (_) {}
    }

    Widget? attachmentWidget;
    bool isOnlyFile = false;
    bool isOnlyMedia = false;
    if (fileData != null) {
      final fileId = fileData['file_id']?.toString() ?? '';
      final fileName = fileData['file_name']?.toString() ?? 'file';
      final fileSize = fileData['file_size'] as int? ?? 0;
      final mime = (fileData['mime_type'] ?? '').toString().toLowerCase();
      final accessToken = fileData['access_token']?.toString();

      final lowerName = fileName.toLowerCase();
      final isImage = mime.startsWith('image/') ||
          lowerName.endsWith('.jpg') ||
          lowerName.endsWith('.jpeg') ||
          lowerName.endsWith('.png') ||
          lowerName.endsWith('.gif') ||
          lowerName.endsWith('.webp') ||
          lowerName.endsWith('.bmp') ||
          lowerName.endsWith('.svg');

      final isVideo = mime.startsWith('video/') ||
          lowerName.endsWith('.mp4') ||
          lowerName.endsWith('.avi') ||
          lowerName.endsWith('.mov') ||
          lowerName.endsWith('.wmv') ||
          lowerName.endsWith('.flv') ||
          lowerName.endsWith('.webm') ||
          lowerName.endsWith('.mkv') ||
          lowerName.endsWith('.3gp') ||
          lowerName.endsWith('.ogv') ||
          lowerName.endsWith('.m4v');

      // Формируем абсолютную ссылку для скачивания с JWT или access токеном
      final uri = Uri.parse(AppConfig.apiBaseUrl);
      final hostUrl = '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}';
      final fileUrlSuffix = fileData['file_url']?.toString() ?? '/api/files/download/$fileId/';
      String absoluteUrl = '';
      if (fileUrlSuffix.startsWith('http')) {
        absoluteUrl = '$fileUrlSuffix${accessToken != null ? (fileUrlSuffix.contains('?') ? "&token=$accessToken" : "?token=$accessToken") : ""}';
      } else {
        final prefix = fileUrlSuffix.startsWith('/') ? '' : '/';
        absoluteUrl = '$hostUrl$prefix$fileUrlSuffix${accessToken != null ? "?token=$accessToken" : ""}';
      }

      final isVoice = fileData['type'] == 'voice' ||
          mime.startsWith('audio/') ||
          lowerName.endsWith('.ogg') ||
          lowerName.endsWith('.webm') ||
          lowerName.endsWith('.opus') ||
          lowerName.endsWith('.wav') ||
          lowerName.endsWith('.mp3');

      final isVideoMessage = fileData['type'] == 'video_message';

      isOnlyFile = displayContent.isEmpty;
      isOnlyMedia = isOnlyFile && (isImage || isVideo || isVideoMessage);

      if (fileData['type'] == 'todo_list') {
        attachmentWidget = TodoListWidget(
          message: message,
          chatWebSocketService: context.watch<ChatWebSocketService>(),
          localChatRepo: context.watch<LocalChatRepository>(),
          onStateChanged: () {},
        );
      } else if (fileData['type'] == 'poll') {
        attachmentWidget = PollWidget(
          message: message,
          chatWebSocketService: context.watch<ChatWebSocketService>(),
          localChatRepo: context.watch<LocalChatRepository>(),
          onStateChanged: () {},
        );
      } else if (isVideoMessage) {
        final duration = fileData['duration'] is num
            ? (fileData['duration'] as num).toDouble()
            : double.tryParse(fileData['duration']?.toString() ?? '') ?? 0.0;
        final localPath = fileData['local_path']?.toString();
        final videoSource = (localPath != null && localPath.isNotEmpty) ? localPath : absoluteUrl;
        attachmentWidget = VideoMessagePlayer(
          videoUrl: videoSource,
          jwtToken: jwtToken,
          duration: duration,
          localPath: localPath,
        );
      } else if (isVoice) {
        final duration = fileData['duration'] is num
            ? (fileData['duration'] as num).toInt()
            : int.tryParse(fileData['duration']?.toString() ?? '') ?? 0;
        // Если есть локальный путь (только что записанное наше ГС) — играем из него,
        // не дожидаясь скачивания. Иначе — обычная ссылка на скачивание.
        final localPath = fileData['local_path']?.toString();
        final voiceSource = (localPath != null && localPath.isNotEmpty) ? localPath : absoluteUrl;
        attachmentWidget = VoiceMessagePlayer(
          audioUrl: voiceSource,
          duration: duration,
          jwtToken: jwtToken,
          isMe: isMe,
          mimeType: fileData['mime_type']?.toString() ?? mime,
          senderName: senderRealName,
        );
      } else if (isImage) {
        attachmentWidget = GestureDetector(
          onTap: () => _showFullScreenImage(context, absoluteUrl, senderRealName, message.timestamp),
          child: Container(
            margin: isOnlyMedia ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: isOnlyMedia ? null : BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: ClipRRect(
              borderRadius: isOnlyMedia ? (isMe ? _myCorners : _otherCorners) : BorderRadius.circular(11),
              child: Stack(
                children: [
                  Hero(
                    tag: absoluteUrl,
                    child: Image.network(
                      absoluteUrl,
                      key: ValueKey('${absoluteUrl}_${jwtToken ?? ""}'),
                      headers: jwtToken != null ? {'Authorization': 'Bearer $jwtToken'} : null,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint('IMAGE PREVIEW LOAD ERROR: $error');
                        debugPrint('IMAGE PREVIEW URL: $absoluteUrl');
                        return Container(
                          height: 120,
                          color: Colors.black12,
                          child: const Center(
                            child: Icon(Icons.broken_image, color: Colors.white54, size: 36),
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 150,
                          color: Colors.black12,
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              if (isOnlyMedia)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(message.timestamp),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          FaIcon(
                            message.isRead ? FontAwesomeIcons.checkDouble : FontAwesomeIcons.check,
                            size: 10,
                            color: Colors.white, 
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        );
      } else if (isVideo) {
        attachmentWidget = GestureDetector(
          onTap: () => _showFullScreenVideo(context, absoluteUrl, senderRealName, message.timestamp),
          child: Container(
            margin: isOnlyMedia ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: isOnlyMedia ? null : BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: ClipRRect(
              borderRadius: isOnlyMedia ? (isMe ? _myCorners : _otherCorners) : BorderRadius.circular(11),
              child: Stack(
                children: [
                  VideoThumbnailWidget(
                    videoUrl: absoluteUrl,
                    jwtToken: jwtToken,
                    width: 280,
                    height: 200,
                    borderRadius: isOnlyMedia ? (isMe ? _myCorners : _otherCorners) : BorderRadius.circular(11),
                  ),
                  Container(
                    height: 200,
                    width: 280,
                    color: Colors.black26,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const FaIcon(FontAwesomeIcons.play, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  if (isOnlyMedia)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTime(message.timestamp),
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              FaIcon(
                                message.isRead ? FontAwesomeIcons.checkDouble : FontAwesomeIcons.check,
                                size: 10,
                                color: Colors.white,
                              ),
                            ]
                          ],
                        ),
                      ),
                    )
                  else
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Row(
                        children: [
                          const FaIcon(FontAwesomeIcons.video, color: Colors.white70, size: 10),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              fileName,
                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _formatFileSize(fileSize),
                            style: const TextStyle(color: Colors.white54, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      } else {
        // Обычные файлы (документы, архивы и др.)
        attachmentWidget = GestureDetector(
          onTap: () => _downloadFileSilent(context, absoluteUrl, fileName),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const FaIcon(FontAwesomeIcons.fileLines, color: Colors.white70, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatFileSize(fileSize),
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const FaIcon(FontAwesomeIcons.download, color: Colors.white54, size: 14),
              ],
            ),
          ),
        );
      }
    }


    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.70,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2.5, horizontal: 16),
          padding: isOnlyMedia ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isOnlyMedia ? Colors.transparent : (isMe ? _myBubbleColor : _otherBubbleColor),
            borderRadius: isMe ? _myCorners : _otherCorners,
            border: isOnlyMedia ? null : Border.all(color: _borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (attachmentWidget != null) attachmentWidget,
              if (displayContent.isNotEmpty)
                FormattedText(
                  content: displayContent,
                  baseStyle: _bodyStyle,
                ),
              if (!isOnlyMedia) const SizedBox(height: 3),
              if (!isOnlyMedia)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.timestamp),
                      style: _timeStyle,
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      FaIcon(
                        message.isRead ? FontAwesomeIcons.checkDouble : FontAwesomeIcons.check,
                        size: 10,
                        color: message.isRead ? _checkReadColor : _checkColor,
                      ),
                    ]
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? jwtToken;
  const _FullScreenVideoPlayer({Key? key, required this.videoUrl, this.jwtToken}) : super(key: key);

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  late VideoPlayerController _videoPlayerController;
  bool _isLoading = true;
  double _downloadProgress = 0.0;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final hash = widget.videoUrl.hashCode.toString();
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/video_cache_$hash.mp4');

      if (!await tempFile.exists()) {
        final dio = Dio();
        if (widget.jwtToken != null) {
          dio.options.headers['Authorization'] = 'Bearer ${widget.jwtToken}';
        }
        await dio.download(
          widget.videoUrl, 
          tempFile.path,
          onReceiveProgress: (count, total) {
            if (total != -1 && mounted) {
              setState(() {
                _downloadProgress = count / total;
              });
            }
          },
        );
      }

      _videoPlayerController = VideoPlayerController.file(tempFile);
      await _videoPlayerController.initialize();
      _videoPlayerController.addListener(_onVideoEvent);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _videoPlayerController.play();
        _startHideTimer();
      }
    } catch (e) {
      debugPrint('Video init error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onVideoEvent() {
    if (mounted) setState(() {});
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _videoPlayerController.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePlay() {
    if (_videoPlayerController.value.isPlaying) {
      _videoPlayerController.pause();
      setState(() => _showControls = true);
      _hideControlsTimer?.cancel();
    } else {
      _videoPlayerController.play();
      setState(() => _showControls = true);
      _startHideTimer();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _videoPlayerController.removeListener(_onVideoEvent);
    _videoPlayerController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString();
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildProgressBar() {
    final position = _videoPlayerController.value.position;
    final duration = _videoPlayerController.value.duration;
    final remaining = duration - position;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Text(_formatDuration(position), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: position.inMilliseconds.toDouble(),
                max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                onChanged: (v) {
                  _videoPlayerController.seekTo(Duration(milliseconds: v.toInt()));
                  _startHideTimer();
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('-${_formatDuration(remaining)}', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            if (_downloadProgress > 0) ...[
              const SizedBox(height: 16),
              Text(
                'Загрузка: ${(_downloadProgress * 100).toInt()}%',
                style: const TextStyle(color: Colors.white70),
              ),
            ]
          ],
        ),
      );
    } else if (_videoPlayerController.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _videoPlayerController.value.aspectRatio,
              child: VideoPlayer(_videoPlayerController),
            ),
          ),
          GestureDetector(
            onTap: _togglePlay,
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _videoPlayerController.value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            bottom: _showControls ? MediaQuery.paddingOf(context).bottom + 90 : -100,
            left: 24,
            right: 24,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _buildProgressBar(),
            ),
          ),
        ],
      );
    } else {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.white54, size: 64),
            SizedBox(height: 16),
            Text('Ошибка воспроизведения', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
  }
}

class VoiceMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final int duration;
  final String? jwtToken;
  final bool isMe;
  final String? mimeType;
  final String senderName;

  const VoiceMessagePlayer({
    super.key,
    required this.audioUrl,
    required this.duration,
    required this.jwtToken,
    required this.isMe,
    this.mimeType,
    required this.senderName,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  String _formatDuration(Duration d) {
    final s = d.inSeconds % 60;
    final m = d.inMinutes;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.isMe;
    final playBtnColor = isMe ? const Color(0xFF4ADE80) : Colors.white;
    final iconColor = Colors.black;
    final activeTrackColor = isMe ? const Color(0xFF4ADE80) : Colors.white;
    final inactiveTrackColor = Colors.white.withValues(alpha: 0.2);

    return Selector<PlaybackProvider, _VoicePlaybackState>(
        selector: (_, provider) => _VoicePlaybackState(
          currentAudioUrl: provider.currentAudioUrl,
          isPlaying: provider.isPlaying,
          isInitialized: provider.isInitialized,
          isLoading: provider.isLoading,
          position: provider.position,
          duration: provider.duration,
        ),
        shouldRebuild: (prev, next) {
          // Ребилдим только если это наш audioUrl и состояние изменилось
          final isCurrent = next.currentAudioUrl == widget.audioUrl;
          final wasCurrent = prev.currentAudioUrl == widget.audioUrl;
          
          if (!isCurrent && !wasCurrent) {
            // Не наш audio - не ребилдим
            return false;
          }
          
          // Наш audio - проверяем значимые изменения
          return prev != next;
        },
        builder: (context, state, child) {
          final audioUrl = widget.audioUrl;
          final isCurrent = state.currentAudioUrl == audioUrl;
          final isPlaying = isCurrent && state.isPlaying;
          final isInitialized = isCurrent && state.isInitialized;
          final isLoading = isCurrent && state.isLoading;

          final position = isCurrent ? state.position : Duration.zero;
          final durationVal = isCurrent && state.isInitialized && state.duration > Duration.zero
              ? state.duration 
              : Duration(seconds: widget.duration);

          final displayDuration = isPlaying || (isCurrent && position > Duration.zero) ? position : durationVal;

          return Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Play/Pause circular button
                GestureDetector(
                  onTap: () {
                    if (isLoading) return;
                    final playbackProvider = context.read<PlaybackProvider>();
                    playbackProvider.play(
                      audioUrl,
                      'Голосовое сообщение',
                      isMe ? 'Вы' : widget.senderName,
                      mimeType: widget.mimeType,
                      duration: Duration(seconds: widget.duration),
                    );
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: playBtnColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: playBtnColor.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: isLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(iconColor.withValues(alpha: 0.5)),
                              ),
                            )
                          : Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: iconColor,
                              size: 26,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Progress & Duration column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Waveform Slider
                      VoiceWaveformSlider(
                        position: position,
                        duration: durationVal,
                        isActive: isCurrent && isInitialized,
                        // Финальный seek — один раз, когда палец отпущен.
                        // Тяжёлая операция: пересоздаёт AudioSource.
                        onSeek: isCurrent && isInitialized
                            ? (newPosition) {
                                context.read<PlaybackProvider>().seek(newPosition);
                              }
                            : null,
                        // Превью во время драга — на каждое движение пальца.
                        // Лёгкая операция: просто двигает позицию в UI,
                        // не трогает плеер. Без этого guard _isSeeking в
                        // провайдере отбрасывал бы почти все промежуточные
                        // вызовы seek(), и слайдер выглядел нерабочим.
                        onSeekPreview: isCurrent && isInitialized
                            ? (newPosition) {
                                context.read<PlaybackProvider>().seekPreview(newPosition);
                              }
                            : null,
                        activeColor: activeTrackColor,
                        inactiveColor: inactiveTrackColor,
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          _formatDuration(displayDuration),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 10.5,
                            fontFamily: AppStyles.fontFamily,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
    );
  }
}

class _BlinkingRedDot extends StatefulWidget {
  const _BlinkingRedDot();

  @override
  State<_BlinkingRedDot> createState() => _BlinkingRedDotState();
}

class _BlinkingRedDotState extends State<_BlinkingRedDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
