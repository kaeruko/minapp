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

    expect(find.byKey(const Key('girls-guest-banner')), findsOneWidget);
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

    expect(find.text('まずは登録なしで遊べるよ'), findsOneWidget);
    expect(find.byKey(const Key('girls-guest-memo')), findsOneWidget);
    expect(find.byKey(const Key('girls-guest-minappchi')), findsOneWidget);
    expect(find.byKey(const Key('girls-guest-novel')), findsOneWidget);
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

    expect(find.byKey(const Key('girls-guest-banner')), findsOneWidget);
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
    expect(find.textContaining('遊んだ記録は、この端末にそのまま残ります'), findsOneWidget);

    await tester.tap(find.text('今はしない'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('girls-guest-banner')), findsOneWidget);
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
    expect(find.byKey(const Key('girls-guest-banner')), findsOneWidget);
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
