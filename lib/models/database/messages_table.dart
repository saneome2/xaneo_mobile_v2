import 'package:drift/drift.dart';
import 'chats_table.dart';

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverMessageId => text().unique()();
  IntColumn get chatId => integer().references(Chats, #id)();
  TextColumn get senderId => text()();
  TextColumn get textContent => text()();
  TextColumn get fileUrl => text().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get timestamp => dateTime()();

  // Support for ToDo lists and Polls
  TextColumn get messageType => text().nullable()(); // 'todo_list', 'poll', 'voice', 'text', etc.
  TextColumn get messageId => text().nullable()(); // UUID of TodoListMessage or PollMessage
  TextColumn get completionStatus => text().nullable()(); // JSON string: completion status map
  TextColumn get votesByOption => text().nullable()(); // JSON string: votes by option map
  TextColumn get userVotes => text().nullable()(); // JSON string: list of option IDs voted by the current user
}
