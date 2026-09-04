import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/girls/girls_footer_nav.dart';

void main() {
  test('Girls footer destinations are home groups shop apps more', () {
    expect(
      GirlsFooterTab.values.map((GirlsFooterTab tab) => tab.name).toList(),
      <String>['home', 'groups', 'shop', 'apps', 'more'],
    );
    expect(
      GirlsFooterTab.values.map((GirlsFooterTab tab) => tab.label).toList(),
      <String>['ホーム', 'グループ', 'ショップ', 'アプリ', 'その他'],
    );
  });

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

  testWidgets('Girls footer SVG and five illustrated destinations render', (
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

    for (final GirlsFooterTab tab in GirlsFooterTab.values) {
      expect(
        find.byKey(ValueKey<String>('girls-footer-${tab.name}')),
        findsOneWidget,
      );
      expect(find.image(AssetImage(tab.assetName)), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
