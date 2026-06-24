import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database_key_service.dart';
import '../../models/database/chats_table.dart';
import '../../models/database/messages_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Chats, Messages])
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.e);

  /// Конструктор для тестов в памяти
  AppDatabase.forTesting(super.e);

  static AppDatabase? _instance;

  static Future<AppDatabase> getInstance() async {
    if (_instance != null) return _instance!;
    
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app_db.sqlite'));
    
    final keyService = DatabaseKeyService();
    final encryptionKey = await keyService.getEncryptionKey();

    _instance = AppDatabase._(NativeDatabase.createInBackground(
      file,
      setup: (db) {
        // Устанавливаем ключ для SQLCipher при открытии БД
        db.execute("PRAGMA key = '$encryptionKey';");
        // Включаем WAL-режим для параллельного чтения и записи
        db.execute("PRAGMA journal_mode = WAL;");
      },
    ));
    
    return _instance!;
  }

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(chats, chats.isArchived);
            await m.addColumn(chats, chats.archivedAt);
          }
          if (from < 3) {
            await m.addColumn(messages, messages.messageType);
            await m.addColumn(messages, messages.messageId);
            await m.addColumn(messages, messages.completionStatus);
            await m.addColumn(messages, messages.votesByOption);
            await m.addColumn(messages, messages.userVotes);
          }
          if (from < 4) {
            await m.addColumn(chats, chats.lastMessageType);
          }
        },
        beforeOpen: (details) async {
          // Создаем композитный индекс для оптимизации сортировки и выборки сообщений в чате
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_messages_chat_timestamp ON messages (chat_id, timestamp DESC);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_chats_last_message_time ON chats (last_message_time DESC);',
          );
        },
      );
}
