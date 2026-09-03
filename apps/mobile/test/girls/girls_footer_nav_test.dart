import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/girls/girls_footer_nav.dart';

void main() {
  test('Girls footer mapper colors only the selected hill', () {
    const GirlsFooterColorMapper mapper =
        GirlsFooterColorMapper(GirlsFooterTab.groups);

    expect(
      mapper.substitute(
        'tab-home',
        'rect',
        'fill',
        const Color(0xFF010101),
      ),
      const Color(0xFFFCF5E9),
    );
    expect(
      mapper.substitute(
        'tab-groups',
        'rect',
        'fill',
        const Color(0xFF020202),
      ),
      const Color(0xFFF9DDE8),
    );
    expect(
      mapper.substitute(
        'footer-outline',
        'path',
        'stroke',
        const Color(0xFFF3DAA8),
      ),
      const Color(0xFFF3DAA8),
    );
  });

  testWidgets('Girls footer SVG and five labels render', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GirlsFooterNav(
            selectedTab: GirlsFooterTab.groups,
            enabledTabs: <GirlsFooterTab>{GirlsFooterTab.groups},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ホーム'), findsOneWidget);
    expect(find.text('グループ'), findsOneWidget);
    expect(find.text('日記'), findsOneWidget);
    expect(find.text('ゲーム'), findsOneWidget);
    expect(find.text('その他'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
