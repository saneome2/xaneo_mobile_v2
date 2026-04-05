import 'dart:convert';

/// Модель чата
class ChatModel {
  final String id;
  final String name;
  final String? avatar;
  final String? avatarGradient;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isGroup;
  final bool isChannel;
  final bool isPersonal;
  final bool isFavorites;
  final Map<String, dynamic>? otherUser;
  final bool isEncrypted;

  ChatModel({
    required this.id,
    required this.name,
    this.avatar,
    this.avatarGradient,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isGroup = false,
    this.isChannel = false,
    this.isPersonal = false,
    this.isFavorites = false,
    this.otherUser,
    this.isEncrypted = false,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    // Обрабатываем разные форматы ответа API
    final chatId = json['chat_id']?.toString() ?? json['id']?.toString() ?? '';
    final chatType = json['chat_type']?.toString() ?? '';
    final displayName = json['chat_display_name'] ?? json['name'] ?? json['title'] ?? 'Unknown';

    // Для личных чатов используем other_user
    String chatName = displayName;
    String? avatarUrl;
    String? avatarGrad;
    if (json['other_user'] != null && json['other_user'] is Map) {
      final otherUser = json['other_user'] as Map<String, dynamic>;
      chatName = otherUser['first_name']?.toString() ?? otherUser['username']?.toString() ?? displayName;
      // Безопасная проверка типа для avatar_url
      if (otherUser['avatar_url'] is String) {
        avatarUrl = otherUser['avatar_url'] as String;
      }
      // Градиент аватара
      if (otherUser['avatar_gradient'] is String) {
        avatarGrad = otherUser['avatar_gradient'] as String;
      }
    }

  // Безопасная проверка для avatar
  String? avatar;
  if (avatarUrl != null) {
    avatar = avatarUrl;
  } else if (json['avatar_url'] is String) {
    avatar = json['avatar_url'] as String;
  } else if (json['avatar'] is String) {
    avatar = json['avatar'] as String;
  } else if (json['image'] is String) {
    avatar = json['image'] as String;
  }

    // Градиент аватара для групп/каналов (из корня JSON)
    if (avatarGrad == null && json['avatar_gradient'] is String) {
      avatarGrad = json['avatar_gradient'] as String;
    }

    final isPersonal = chatType == 'personal';
    final isGroup = chatType == 'group';
    final isChannel = chatType == 'channel';

    // Определяем, является ли чат Избранным
    final isFavorites = chatId == 'favorites' ||
        displayName == 'Избранное' ||
        json['is_bookmark'] == true ||
        json['is_favorites'] == true;

    // Для Избранного устанавливаем фиолетовый градиент если не передан
    if (isFavorites && avatarGrad == null) {
      avatarGrad = '8B5CF6,6366F1';
    }

    // Получаем зашифрованный текст сообщения
    final encryptedText = json['last_message']?['encrypted_text'] as String? ??
        json['lastMessage']?['encrypted_text'] as String?;

    String? lastMsg;
    bool isEncrypted = false;

    if (encryptedText != null && encryptedText.isNotEmpty) {
      // Это зашифрованное сообщение XSEC-2
      lastMsg = encryptedText;
      isEncrypted = true;
    } else {
      // Пробуем получить plaintext
      final rawLastMsg = json['last_message'] ??
          json['lastMessage'] ??
          json['latest_message'] ??
          json['last_message_content'] ??
          json['message_preview'] ??
          json['preview'] ??
          json['message'];

      if (rawLastMsg is String) {
        lastMsg = rawLastMsg;
      } else if (rawLastMsg is Map) {
        final textCandidate = rawLastMsg['text'] ??
            rawLastMsg['message'] ??
            rawLastMsg['content'] ??
            rawLastMsg['body'] ??
            rawLastMsg['encrypted_text'];
        if (textCandidate is String && textCandidate.isNotEmpty) {
          lastMsg = textCandidate;
          isEncrypted = _isEncryptedMessage(textCandidate);
        } else {
          lastMsg = jsonEncode(rawLastMsg);
        }
      } else if (rawLastMsg != null) {
        lastMsg = rawLastMsg.toString();
      }
    }

    // Дополнительная проверка на шифрование
    if (!isEncrypted && lastMsg != null) {
      isEncrypted = _isEncryptedMessage(lastMsg);
    }

    // Извлекаем время последнего сообщения из разных возможных полей.
    // Важно: не останавливаемся на первом поле, если оно не распарсилось.
    DateTime? lastMsgTime;

    final candidates = <dynamic>[
      json['last_message_time'],
      if (json['last_message'] is Map)
        (json['last_message'] as Map<String, dynamic>)['timestamp'] ??
            (json['last_message'] as Map<String, dynamic>)['created_at'] ??
            (json['last_message'] as Map<String, dynamic>)['time'] ??
            (json['last_message'] as Map<String, dynamic>)['sent_at'],
      json['last_message_timestamp'],
      json['last_activity'],
    ];

    for (final candidate in candidates) {
      final parsed = _parseApiDateTime(candidate);
      if (parsed != null) {
        lastMsgTime = parsed;
        break;
      }
    }

    return ChatModel(
      id: chatId,
      name: chatName,
      avatar: avatar,
      avatarGradient: avatarGrad,
      lastMessage: lastMsg,
      lastMessageTime: lastMsgTime,
      unreadCount: json['unread_count'] ?? json['unreadCount'] ?? 0,
      isGroup: isGroup,
      isChannel: isChannel,
      isPersonal: isPersonal,
      isFavorites: isFavorites,
      isEncrypted: isEncrypted,
      otherUser: json['other_user'] is Map ? json['other_user'] as Map<String, dynamic> : null,
    );
  }

  /// Получить инициалы для аватара
  String get initials {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (name.isNotEmpty) return name[0].toUpperCase();
    return '?';
  }

  /// Форматировать время последнего сообщения
  String get formattedTime {
    if (lastMessageTime == null) return '';

    try {
      final now = DateTime.now();
      final diff = now.difference(lastMessageTime!);

      if (diff.inMinutes < 1) {
        return 'сейчас';
      } else if (diff.inHours < 1) {
        return '${diff.inMinutes}м';
      } else if (diff.inDays < 1) {
        return '${diff.inHours}ч';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}д';
      } else {
        return '${lastMessageTime!.day}.${lastMessageTime!.month}';
      }
    } catch (e) {
      final h = lastMessageTime!.hour.toString().padLeft(2, '0');
      final m = lastMessageTime!.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
  }

  /// Проверить, является ли сообщение зашифрованным
  bool get isEncryptedMessage {
    if (lastMessage == null || lastMessage!.isEmpty) return false;
    return _isEncryptedMessage(lastMessage!);
  }

  /// Проверить, является ли строка зашифрованным сообщением XSEC-2
  /// Формат: base64(12 bytes IV/nonce + ciphertext)
  static bool _isEncryptedMessage(String text) {
    if (text.isEmpty) return false;

    try {
      final trimmed = text.trim();

      // JSON не является зашифрованным сообщением
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        return false;
      }

      // Пробуем декодировать как base64
      var normalized = trimmed
          .replaceAll(' ', '')
          .replaceAll('\n', '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');

      final pad = normalized.length % 4;
      if (pad == 2) {
        normalized += '==';
      } else if (pad == 3) {
        normalized += '=';
      }

      final decoded = base64Decode(normalized);

      // Минимальная длина: 12 байт nonce + 16 байт tag (AES-GCM)
      if (decoded.length < 28) return false;

      // Проверяем что это не читаемый текст
      try {
        utf8.decode(decoded);
        return false; // Если получилось декодировать как UTF-8 - это plaintext
      } catch (_) {
        return true;
      }
    } catch (e) {
      return false;
    }
  }

  static bool _looksLikeStructuredPayload(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) return true;
    final hasNonce = RegExp(r'nonce\s*[:=]').hasMatch(trimmed);
    final hasCipher = RegExp(r'ciphertext\s*[:=]|encrypted_data\s*[:=]').hasMatch(trimmed);
    return hasNonce && hasCipher;
  }

  /// Получить отображаемое сообщение
  /// Для зашифрованных сообщений показываем плейсхолдер
  /// Для пустых групп/каналов показываем "Группа создана"/"Канал создан"
  String get displayMessage {
    if (lastMessage == null || lastMessage!.isEmpty) {
      if (isGroup) return 'Группа создана';
      if (isChannel) return 'Канал создан';
      return '';
    }

    // Если сообщение зашифровано (base64 payload), показываем плейсхолдер
    if (isEncryptedMessage || _looksLikeStructuredPayload(lastMessage!)) {
      return 'Зашифрованное сообщение';
    }

    return lastMessage!;
  }

  static DateTime? _parseApiDateTime(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) {
      return value.isUtc ? value.toLocal() : value;
    }

    if (value is int) {
      // Поддержка unix timestamp в секундах и миллисекундах.
      final isMilliseconds = value > 100000000000;
      final dateTime = isMilliseconds
          ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
      return dateTime.toLocal();
    }

    if (value is double) {
      return _parseApiDateTime(value.toInt());
    }

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;

      final parsedStringDate = DateTime.tryParse(trimmed);
      if (parsedStringDate != null) {
        return parsedStringDate.isUtc ? parsedStringDate.toLocal() : parsedStringDate;
      }

      final numericValue = int.tryParse(trimmed);
      if (numericValue != null) {
        return _parseApiDateTime(numericValue);
      }
    }

    return null;
  }
}
