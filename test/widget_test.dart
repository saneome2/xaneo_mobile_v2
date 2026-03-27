import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xaneo_mobile/main.dart';
import 'package:xaneo_mobile/providers/auth_provider.dart';

void main() {
  testWidgets('App loads and shows splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const XaneoApp());
    
    // Проверяем, что появился логотип Xaneo
    expect(find.text('Xaneo'), findsOneWidget);
  });
}
