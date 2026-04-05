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

    _instance = AppDatabase._(NativeDatabase(
      file,
      setup: (db) {
        // Устанавливаем ключ для SQLCipher при открытии БД
        db.execute("PRAGMA key = '$encryptionKey';");
      },
    ));
    
    return _instance!;
  }

  @override
  int get schemaVersion => 1;
}
