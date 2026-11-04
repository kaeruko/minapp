import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/girls_persistent_app.dart';
import 'package:minapp_mobile/girls/girls_session_store.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

void main() {
  testWidgets('fresh launch enters guest home instead of auth', (
    WidgetTester tester,
  ) async {
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      return http.Response('unexpected', 500);
    });
    addTearDown(client.close);

    await tester.pumpWidget(
      GirlsPersistentApp(
        api: HostedGirlsApi(
          baseUri: Uri.parse('https://girls-api.example.com'),
          client: client,
          sessionStore: _EmptySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('girls-guest-memo')), findsOneWidget);
    expect(find.byKey(const Key('girls-login-id')), findsNothing);
    expect(requestCount, 0);
  });

  testWidgets('guest home exposes local play without backend requests', (
    WidgetTester tester,
  ) async {
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      return http.Response('unexpected', 500);
    });
    addTearDown(client.close);

    await tester.pumpWidget(
      GirlsPersistentApp(
        api: HostedGirlsApi(
          baseUri: Uri.parse('https://girls-api.example.com'),
          client: client,
          sessionStore: _EmptySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('まずは登録なしで遊べるよ'), findsNothing);
    expect(find.text('遊んだ記録はこの端末に保存されます'), findsNothing);
    expect(find.text('登録なしで遊べる公式アプリ'), findsNothing);
    expect(find.byKey(const Key('girls-guest-memo')), findsOneWidget);
    expect(find.byKey(const Key('girls-guest-minappchi')), findsOneWidget);
    expect(find.byKey(const Key('girls-guest-novel')), findsOneWidget);
    final GridView grid = tester.widget<GridView>(find.byType(GridView));
    final SliverGridDelegateWithFixedCrossAxisCount gridDelegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    // Card height includes a square illustration and a separate caption.
    expect(gridDelegate.childAspectRatio, 0.8);

    for (final String assetName in <String>[
      'assets/girls/home/cards/memo_card.png',
      'assets/girls/home/cards/minappchi_card.png',
      'assets/girls/home/cards/novel_card.png',
    ]) {
      final Finder imageFinder = find.byWidgetPredicate(
        (Widget widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == assetName,
      );
      expect(imageFinder, findsOneWidget);
      expect(tester.widget<Image>(imageFinder).fit, BoxFit.contain);
    }
    expect(find.byKey(const Key('girls-guest-auth')), findsOneWidget);
    expect(requestCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest home does not overflow on a small device', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final MockClient client = MockClient((http.Request request) async {
      return http.Response('unexpected', 500);
    });
    addTearDown(client.close);

    await tester.pumpWidget(
      GirlsPersistentApp(
        api: HostedGirlsApi(
          baseUri: Uri.parse('https://girls-api.example.com'),
          client: client,
          sessionStore: _EmptySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('girls-guest-memo')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account-only action explains registration before navigation', (
    WidgetTester tester,
  ) async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response('unexpected', 500);
    });
    addTearDown(client.close);

    await tester.pumpWidget(
      GirlsPersistentApp(
        api: HostedGirlsApi(
          baseUri: Uri.parse('https://girls-api.example.com'),
          client: client,
          sessionStore: _EmptySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('girls-guest-account-feature')),
    );
    await tester.tap(find.byKey(const Key('girls-guest-account-feature')));
    await tester.pumpAndSettle();

    expect(find.text('アプリ作成や公開には登録が必要です'), findsOneWidget);
    expect(find.textContaining('ゲストのまま公開アプリで遊ぶことはできます'), findsOneWidget);

    await tester.tap(find.text('今はしない'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('girls-guest-memo')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest can open auth and return without losing guest home', (
    WidgetTester tester,
  ) async {
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      expect(request.url.path, '/hosted/legal');
      return http.Response(
        jsonEncode(<String, Object?>{
          'effective_date': '2026-09-01',
          'support_email': 'support@example.com',
          'terms': <String, Object?>{
            'version': 'terms-v1',
            'title': '利用規約',
            'body': '規約本文',
          },
          'privacy': <String, Object?>{
            'version': 'privacy-v1',
            'title': 'プライバシーポリシー',
            'body': 'プライバシー本文',
          },
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    await tester.pumpWidget(
      GirlsPersistentApp(
        api: HostedGirlsApi(
          baseUri: Uri.parse('https://girls-api.example.com'),
          client: client,
          sessionStore: _EmptySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('girls-guest-auth')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('girls-login-id')), findsOneWidget);
    expect(find.byKey(const Key('girls-auth-back')), findsOneWidget);
    expect(requestCount, 1);

    await tester.tap(find.byKey(const Key('girls-auth-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('girls-guest-memo')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _EmptySessionStore implements GirlsSessionStore {
  @override
  Future<void> clearRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}
