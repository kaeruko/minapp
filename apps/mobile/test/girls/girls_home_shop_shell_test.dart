import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/builtin_webview.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_current_group_store.dart';
import 'package:minapp_mobile/girls/girls_home_shop_shell.dart';
import 'package:minapp_mobile/girls/girls_profile_page.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

class _MemoryCurrentGroupStore implements GirlsCurrentGroupStore {
  String? value;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String groupId) async {
    value = groupId;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

HostedGirlsApi _fakeApi() {
  return HostedGirlsApi(
    baseUri: Uri.parse('https://example.com'),
    client: MockClient((http.Request request) async {
      if (request.url.path == '/shop/apps') {
        return http.Response(
          jsonEncode(<String, Object?>{'apps': <Object?>[]}),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      if (request.url.path == '/hosted/groups') {
        return http.Response(
          jsonEncode(<String, Object?>{'groups': <Object?>[]}),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      return http.Response(
        jsonEncode(<String, Object?>{}),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    }),
  );
}

Future<void> _finishRouteTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void _expectHeaderOrder(WidgetTester tester, String pageName) {
  final Finder headerFinder = find.byKey(const Key('girls-common-header'));
  final Finder titleFinder = find.byKey(const Key('girls-page-title'));
  expect(headerFinder, findsOneWidget);
  expect(find.byKey(const Key('girls-header-logo')), findsOneWidget);
  expect(titleFinder, findsOneWidget);
  expect(tester.widget<Text>(titleFinder).data, pageName);

  final Rect header = tester.getRect(headerFinder);
  final Rect lace = tester.getRect(find.byKey(const Key('girls-header-lace')));
  final Rect logo = tester.getRect(find.byKey(const Key('girls-header-logo')));
  final Rect title = tester.getRect(titleFinder);
  expect(lace.top, 0);
  expect(logo.top, greaterThanOrEqualTo(lace.bottom));
  expect(logo.top - lace.bottom, lessThanOrEqualTo(4));
  expect(logo.center.dx, closeTo(header.center.dx, .001));
  expect(title.center.dx, closeTo(logo.center.dx, .001));
  expect(title.top, greaterThanOrEqualTo(header.bottom));
  expect(title.top - header.bottom, lessThanOrEqualTo(12));
}

void main() {
  testWidgets('authenticated Girls routes keep one common header and footer', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GirlsHomeShopShell(
          api: _fakeApi(),
          session: const AuthenticatedSession(
            accessToken: 'test-token',
            expiresIn: 3600,
          ),
          onLogout: () {},
          currentGroupStore: _MemoryCurrentGroupStore(),
        ),
      ),
    );
    await _finishRouteTransition(tester);

    expect(find.byKey(const Key('girls-common-header')), findsOneWidget);
    expect(find.byKey(const Key('girls-header-logo')), findsOneWidget);
    expect(find.byKey(const Key('girls-shell-settings')), findsOneWidget);
    expect(find.byKey(const Key('girls-shell-profile')), findsOneWidget);
    expect(find.byKey(const Key('girls-footer-home')), findsOneWidget);
    expect(find.byKey(const Key('girls-footer-shop')), findsOneWidget);
    expect(find.text('公式アプリ'), findsOneWidget);
    _expectHeaderOrder(tester, 'ホーム');

    await tester.tap(find.byKey(const Key('girls-shell-settings')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('girls-settings-delete-account')),
      findsOneWidget,
    );
    expect(find.text('アカウントを削除'), findsOneWidget);
    Navigator.of(
      tester.element(find.byKey(const Key('girls-settings-delete-account'))),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('girls-footer-shop')));
    await _finishRouteTransition(tester);

    expect(find.byKey(const Key('girls-common-header')), findsOneWidget);
    expect(find.byKey(const Key('girls-header-logo')), findsOneWidget);
    expect(find.byKey(const Key('girls-footer-shop')), findsOneWidget);
    expect(find.text('みんアプGirls ショップ'), findsOneWidget);
    _expectHeaderOrder(tester, 'みんアプGirls ショップ');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('girls-footer-home')));
    await _finishRouteTransition(tester);

    expect(find.byKey(const Key('girls-common-header')), findsOneWidget);
    expect(find.byKey(const Key('girls-footer-home')), findsOneWidget);
    expect(find.text('公式アプリ'), findsOneWidget);
    _expectHeaderOrder(tester, 'ホーム');
    expect(tester.takeException(), isNull);
  });

  testWidgets('built-in lace follows each app and resets on other pages', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final HostedGirlsApi api = _fakeApi();
    const AuthenticatedSession session = AuthenticatedSession(
      accessToken: 'test-token',
      expiresIn: 3600,
    );
    final Finder underlay = find.byKey(const Key('girls-header-lace-underlay'));
    const Color defaultLaceColor = Colors.transparent;

    await tester.pumpWidget(
      MaterialApp(
        home: GirlsHomeShopShell(
          api: api,
          session: session,
          onLogout: () {},
          currentGroupStore: _MemoryCurrentGroupStore(),
        ),
      ),
    );
    await _finishRouteTransition(tester);
    expect(tester.widget<ColoredBox>(underlay).color, defaultLaceColor);

    for (final (String card, String appId, Color color)
        in <(String, String, Color)>[
      ('minappchi', 'minappchi', const Color(0xFFFFE8F2)),
      ('memo', 'memo', const Color(0xFFFFFAF7)),
      ('novel', 'novel-starter', const Color(0xFF7770AE)),
    ]) {
      await tester.tap(find.byKey(Key('girls-home-$card-app')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BuiltInWebViewPage>(find.byType(BuiltInWebViewPage))
            .appId,
        appId,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(tester.widget<ColoredBox>(underlay).color, color);
      final Rect header =
          tester.getRect(find.byKey(const Key('girls-common-header')));
      final Rect lace = tester.getRect(underlay);
      final Rect visibleLace =
          tester.getRect(find.byKey(const Key('girls-header-lace')));
      final Rect logo =
          tester.getRect(find.byKey(const Key('girls-header-logo')));
      expect(lace.bottom, closeTo(header.bottom, .001));
      expect(lace.left, header.left);
      expect(lace.width, header.width);
      expect(lace.top, lessThan(visibleLace.bottom));
      expect(lace.contains(logo.center), isTrue);

      // Exercise the nested navigator directly: the shell profile button also
      // returns to the selected footer tab after closing its profile page.
      final NavigatorState navigator =
          Navigator.of(tester.element(find.byType(BuiltInWebViewPage)));
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              GirlsProfilePage(api: api, session: session),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GirlsProfilePage), findsOneWidget);
      expect(tester.widget<ColoredBox>(underlay).color, defaultLaceColor);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(tester.widget<ColoredBox>(underlay).color, color);
      expect(find.byType(AppBar), findsNothing);

      await tester.tap(find.byKey(const Key('girls-footer-home')));
      await tester.pumpAndSettle();
      expect(tester.widget<ColoredBox>(underlay).color, defaultLaceColor);
      expect(find.text('公式アプリ'), findsOneWidget);

      await tester.tap(find.byKey(const Key('girls-builtin-arrange-later')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.byKey(const Key('girls-home-minappchi-app')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ColoredBox>(underlay).color,
      const Color(0xFFFFE8F2),
    );
    expect(tester.takeException(), isNull);
  });
}
