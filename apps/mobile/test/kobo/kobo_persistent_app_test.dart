import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/hosted_session_store.dart';
import 'package:minapp_mobile/kobo/hosted_kobo_api.dart';
import 'package:minapp_mobile/kobo/kobo_persistent_app.dart';
import 'package:minapp_mobile/kobo/kobo_shell.dart';
import 'package:minapp_mobile/kobo/kobo_theme.dart';

void main() {
  testWidgets('fresh Kobo launch enters the common implicit guest flow', (
    WidgetTester tester,
  ) async {
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      return http.Response('unexpected', 500);
    });
    addTearDown(client.close);

    await tester.pumpWidget(
      KoboPersistentApp(
        api: HostedKoboApi(
          baseUri: Uri.parse('https://kobo-api.example.com'),
          client: client,
          sessionStore: _EmptySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日、なに作る？'), findsOneWidget);
    expect(find.byKey(const Key('kobo-login-id')), findsNothing);
    expect(requestCount, 0);
  });

  testWidgets('guest create action explains registration without fallback', (
    WidgetTester tester,
  ) async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response('unexpected', 500);
    });
    addTearDown(client.close);

    await tester.pumpWidget(
      KoboPersistentApp(
        api: HostedKoboApi(
          baseUri: Uri.parse('https://kobo-api.example.com'),
          client: client,
          sessionStore: _EmptySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('kobo-create-cta')));
    await tester.pumpAndSettle();

    expect(find.text('アプリを作る機能には登録が必要です'), findsOneWidget);
    expect(find.text('今はしない'), findsOneWidget);
    expect(find.byKey(const Key('kobo-login-id')), findsNothing);

    await tester.tap(find.text('今はしない'));
    await tester.pumpAndSettle();
    expect(find.text('今日、なに作る？'), findsOneWidget);
  });

  testWidgets('guest shop uses the public catalog without authorization', (
    WidgetTester tester,
  ) async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/shop/apps');
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response(
        jsonEncode(<String, Object?>{
          'apps': <Object?>[
            <String, Object?>{
              'app_id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'version': '1',
              'title': '晩酌おつまみ帳',
              'owner_user_id': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              'owner_display_name': '工房の親方',
              'published_at': '2026-11-04T00:00:00Z',
              'sha256':
                  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
              'thumbnail_path': null,
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    await tester.pumpWidget(
      KoboPersistentApp(
        api: HostedKoboApi(
          baseUri: Uri.parse('https://kobo-api.example.com'),
          client: client,
          sessionStore: _EmptySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('kobo-nav-community')));
    await tester.pumpAndSettle();

    expect(find.text('晩酌おつまみ帳'), findsOneWidget);
    expect(find.text('遊んでみる'), findsOneWidget);
    expect(find.text('登録・ログイン'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('featured example opens matching public shop app', (
    WidgetTester tester,
  ) async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/shop/apps');
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response(
        jsonEncode(<String, Object?>{
          'apps': <Object?>[
            for (final entry in <(String, String)>[
                  ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '晩酌予算'),
                  ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', '町中華メモ'),
                  ('cccccccccccccccccccccccccccccccc', '昼めしルーレット'),
                ])
              <String, Object?>{
                'app_id': entry.$1,
                'version': '1',
                'title': entry.$2,
                'owner_user_id': 'dddddddddddddddddddddddddddddddd',
                'owner_display_name': '工房の親方',
                'published_at': '2026-11-05T02:00:00Z',
                'sha256': List<String>.filled(64, 'e').join(),
                'thumbnail_path': null,
              },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      KoboPersistentApp(
        api: HostedKoboApi(
          baseUri: Uri.parse('https://kobo-api.example.com'),
          client: client,
          sessionStore: _EmptySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The featured card is a touch target, not a decorative example.
    await tester.tap(find.byKey(const Key('kobo-category-晩酌予算')));
    await tester.pumpAndSettle();

    expect(find.text('みんなのアプリ'), findsWidgets);
    expect(find.byKey(const Key('kobo-shop-search')), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('kobo-shop-search')))
          .controller!.text,
      '晩酌予算',
    );
    expect(find.text('町中華メモ'), findsNothing);
    expect(find.byKey(const Key('kobo-shop-play-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')), findsOneWidget);
    expect(find.byKey(const Key('kobo-shop-play-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')), findsNothing);

    // Removing the search recovers the full public catalog.
    await tester.tap(find.byKey(const Key('kobo-shop-clear-search')));
    await tester.pumpAndSettle();
    expect(find.text('町中華メモ'), findsOneWidget);
    expect(find.text('昼めしルーレット'), findsOneWidget);

    // The regular bottom-nav entry must not inherit the featured search.
    await tester.tap(find.byKey(const Key('kobo-nav-home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kobo-nav-community')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kobo-shop-play-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')), findsOneWidget);
    expect(find.byKey(const Key('kobo-shop-play-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')), findsOneWidget);
    expect(find.byKey(const Key('kobo-shop-play-cccccccccccccccccccccccccccccccc')), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('kobo-shop-search')))
          .controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unpublished featured example gives truthful empty result', (
    WidgetTester tester,
  ) async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/shop/apps');
      return http.Response(
        jsonEncode(<String, Object?>{'apps': <Object?>[]}),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      KoboPersistentApp(
        api: HostedKoboApi(
          baseUri: Uri.parse('https://kobo-api.example.com'),
          client: client,
          sessionStore: _EmptySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('kobo-category-小遣い管理')));
    await tester.tap(find.byKey(const Key('kobo-category-小遣い管理')));
    await tester.pumpAndSettle();

    expect(find.text('「小遣い管理」に一致する公開アプリはありません。'), findsOneWidget);
    expect(find.byKey(const Key('kobo-shop-clear-search')), findsOneWidget);
    await tester.tap(find.byKey(const Key('kobo-shop-clear-search')));
    await tester.pumpAndSettle();
    expect(find.text('公開中の道具はまだありません。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-in create action opens the existing app workflow', (
    WidgetTester tester,
  ) async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.headers['authorization'], 'Bearer access-token');
      if (request.url.path == '/hosted/groups') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'groups': <Object?>[
              <String, Object?>{
                'group_id': '00000000000000000000000000000002',
                'name': 'みんなの工房',
                'role': 'member',
                'status': 'active',
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/hosted/my/apps') {
        return http.Response(
          jsonEncode(<String, Object?>{'apps': <Object?>[]}),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    addTearDown(client.close);
    final HostedKoboApi api = HostedKoboApi(
      baseUri: Uri.parse('https://kobo-api.example.com'),
      client: client,
      sessionStore: _EmptySessionStore(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: KoboTheme.light(),
        home: KoboShell(
          api: api,
          session: const AuthenticatedSession(
            accessToken: 'access-token',
            expiresIn: 3600,
          ),
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('kobo-create-cta')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kobo-create-blank-app')), findsOneWidget);
    expect(find.byKey(const Key('kobo-upload-zip')), findsOneWidget);
    expect(find.text('俺のアプリ'), findsOneWidget);
    expect(find.textContaining('AI'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-in profile opens shared account capabilities', (
    WidgetTester tester,
  ) async {
    final List<String> requestedPaths = <String>[];
    final MockClient client = MockClient((http.Request request) async {
      expect(request.headers['authorization'], 'Bearer access-token');
      requestedPaths.add(request.url.path);
      if (request.url.path == '/hosted/me/display-name') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'user_id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'login_id': 'oyaji',
            'role': 'user',
            'display_name': '工房の親方',
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/hosted/account/email') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'email': null,
            'verified': false,
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    addTearDown(client.close);
    final HostedKoboApi api = HostedKoboApi(
      baseUri: Uri.parse('https://kobo-api.example.com'),
      client: client,
      sessionStore: _EmptySessionStore(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: KoboTheme.light(),
        home: KoboShell(
          api: api,
          session: const AuthenticatedSession(
            accessToken: 'access-token',
            expiresIn: 3600,
          ),
          onLogout: () async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('kobo-nav-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kobo-account-settings')), findsOneWidget);

    await tester.tap(find.byKey(const Key('kobo-account-settings')));
    await tester.pumpAndSettle();

    expect(find.text('アカウント設定'), findsOneWidget);
    expect(find.text('工房の親方'), findsOneWidget);
    expect(find.byKey(const Key('kobo-private-groups')), findsOneWidget);
    expect(
      requestedPaths,
      containsAll(<String>[
        '/hosted/me/display-name',
        '/hosted/account/email',
      ]),
    );
    expect(tester.takeException(), isNull);
  });
}

class _EmptySessionStore implements HostedSessionStore {
  @override
  Future<void> clearRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}
