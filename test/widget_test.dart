import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:xaneo_mobile/main.dart';
import 'package:xaneo_mobile/services/database/app_database.dart';
import 'package:xaneo_mobile/services/chat/chat_local_repository.dart';

void main() {
  testWidgets('App loads and shows splash screen', (WidgetTester tester) async {
    // В тесте используем in-memory базу (чтобы тесты не обращались к диску и работали быстро)
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final localChatRepo = LocalChatRepository(db);

    await tester.pumpWidget(XaneoApp(localChatRepo: localChatRepo));
    
    // Просто проверяем, что виджет смонтировался, дожидаемся микротасок (1 кадр)
    await tester.pump();
  });
}
