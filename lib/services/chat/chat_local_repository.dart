import 'dart:convert';
import 'package:drift/drift.dart';
import '../../models/chat/chat_model.dart';
import '../database/app_database.dart';

class LocalChatRepository {
  final AppDatabase _db;

  LocalChatRepository(this._db);

  /// Получение всех чатов в виде потока (Stream) для реактивного UI, уже преобразованных в ChatModel.
  Stream<List<ChatModel>> watchAllChats() {
    return (_db.select(_db.chats)
          ..orderBy([(c) => OrderingTerm.desc(c.lastMessageTime)]))
        .watch()
        .map((rows) => rows.map(_mapChatToModel).toList());
  }

  /// Получение сообщений конкретного чата в виде потока
  Stream<List<Message>> watchMessagesForChat(int chatId) {
    return (_db.select(_db.messages)
          ..where((m) => m.chatId.equals(chatId))
          ..orderBy([(m) => OrderingTerm.desc(m.timestamp)]))
        .watch();
  }

  Future<ChatModel?> getChatByServerId(String serverChatId) async {
    final row = await (_db.select(_db.chats)
          ..where((c) => c.serverChatId.equals(serverChatId)))
        .getSingleOrNull();

    if (row == null) return null;
    return _mapChatToModel(row);
  }

  Future<int> deleteChatByServerId(String serverChatId) {
    return (_db.delete(_db.chats)
          ..where((c) => c.serverChatId.equals(serverChatId)))
        .go();
  }

  /// Пакетное сохранение чатов из API в локальную БД
  Future<void> saveChatsBatch(List<ChatModel> chatModels) async {
    await _db.transaction(() async {
      for (final chatModel in chatModels) {
        await _upsertChat(chatModel);
      }
    });
  }

  /// Сохранение или обновление одного чата
  Future<int> saveChat(ChatModel chatModel) {
    return _upsertChat(chatModel);
  }

  /// Сохранение сообщения
  Future<int> saveMessage(MessagesCompanion message) {
    return _db.into(_db.messages).insertOnConflictUpdate(message);
  }

  /// Пакетное сохранение сообщений (полезно при загрузке истории)
  Future<void> saveMessagesBatch(List<MessagesCompanion> messages) async {
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.messages, messages);
    });
  }

  ChatModel _mapChatToModel(Chat row) {
    Map<String, dynamic>? otherUser;
    if (row.otherUserJson != null && row.otherUserJson!.isNotEmpty) {
      try {
        otherUser = jsonDecode(row.otherUserJson!) as Map<String, dynamic>;
      } catch (_) {}
    }

    return ChatModel(
      id: row.serverChatId,
      name: row.name,
      avatar: row.avatar,
      avatarGradient: row.avatarGradient,
      lastMessage: row.lastMessage,
      lastMessageTime: row.lastMessageTime,
      unreadCount: row.unreadCount,
      isGroup: row.isGroup,
      isChannel: row.isChannel,
      isPersonal: row.isPersonal,
      isFavorites: row.isFavorites,
      otherUser: otherUser,
      isEncrypted: row.isEncrypted,
    );
  }

  ChatsCompanion _mapModelToCompanion(ChatModel model) {
    String? otherUserJson;
    if (model.otherUser != null) {
      otherUserJson = jsonEncode(model.otherUser);
    }

    return ChatsCompanion(
      serverChatId: Value(model.id),
      name: Value(model.name),
      avatar: Value(model.avatar),
      avatarGradient: Value(model.avatarGradient),
      lastMessage: Value(model.lastMessage),
      lastMessageTime: Value(model.lastMessageTime),
      unreadCount: Value(model.unreadCount),
      isGroup: Value(model.isGroup),
      isChannel: Value(model.isChannel),
      isPersonal: Value(model.isPersonal),
      isFavorites: Value(model.isFavorites),
      otherUserJson: Value(otherUserJson),
      isEncrypted: Value(model.isEncrypted),
    );
  }

  Future<int> _upsertChat(ChatModel incoming) async {
    final existing = await (_db.select(_db.chats)
          ..where((c) => c.serverChatId.equals(incoming.id)))
        .getSingleOrNull();

    final merged = existing == null ? incoming : _mergeChat(_mapChatToModel(existing), incoming);

    if (existing == null) {
      return _db.into(_db.chats).insert(_mapModelToCompanion(merged));
    }

    return (_db.update(_db.chats)..where((c) => c.id.equals(existing.id)))
        .write(_mapModelToCompanion(merged));
  }

  ChatModel _mergeChat(ChatModel existing, ChatModel incoming) {
    final hasIncomingTime = incoming.lastMessageTime != null;
    final hasExistingTime = existing.lastMessageTime != null;

    bool incomingIsLatest;
    if (hasIncomingTime && hasExistingTime) {
      incomingIsLatest = !incoming.lastMessageTime!.isBefore(existing.lastMessageTime!);
    } else if (hasIncomingTime && !hasExistingTime) {
      incomingIsLatest = true;
    } else if (!hasIncomingTime && hasExistingTime) {
      incomingIsLatest = false;
    } else {
      // Если времени нет ни у кого, используем входящее значение как более актуальное.
      incomingIsLatest = true;
    }

    return ChatModel(
      id: incoming.id,
      name: incoming.name,
      avatar: incoming.avatar ?? existing.avatar,
      avatarGradient: incoming.avatarGradient ?? existing.avatarGradient,
      lastMessage: incomingIsLatest ? incoming.lastMessage : existing.lastMessage,
      lastMessageTime: incomingIsLatest ? incoming.lastMessageTime : existing.lastMessageTime,
      unreadCount: incoming.unreadCount,
      isGroup: incoming.isGroup,
      isChannel: incoming.isChannel,
      isPersonal: incoming.isPersonal,
      isFavorites: incoming.isFavorites,
      otherUser: incoming.otherUser ?? existing.otherUser,
      isEncrypted: incomingIsLatest ? incoming.isEncrypted : existing.isEncrypted,
    );
  }
}
