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
}
