import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/main.dart';

void main() {
  testWidgets('Phase 0 home renders product shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MinApp());

    expect(find.text('みんアプ'), findsOneWidget);
    expect(find.text('時間割'), findsOneWidget);
    expect(find.text('文化祭マップ'), findsOneWidget);
    expect(find.text('Phase 0'), findsOneWidget);
  });
}
