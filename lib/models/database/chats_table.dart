import 'package:drift/drift.dart';

class Chats extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverChatId => text().unique()();
  TextColumn get name => text()();
  TextColumn get avatar => text().nullable()();
  TextColumn get avatarGradient => text().nullable()();
  TextColumn get lastMessage => text().nullable()();
  DateTimeColumn get lastMessageTime => dateTime().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  BoolColumn get isGroup => boolean().withDefault(const Constant(false))();
  BoolColumn get isChannel => boolean().withDefault(const Constant(false))();
  BoolColumn get isPersonal => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorites => boolean().withDefault(const Constant(false))();
  TextColumn get otherUserJson => text().nullable()();
  BoolColumn get isEncrypted => boolean().withDefault(const Constant(false))();
}
