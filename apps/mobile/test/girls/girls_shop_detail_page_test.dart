import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_shop_api.dart';
import 'package:minapp_mobile/girls/girls_shop_page.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const String appId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String groupId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String ownerUserId = 'cccccccccccccccccccccccccccccccc';

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
      jsonEncode(value),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

void main() {
  testWidgets('guest and signed-in shop use the same play button text', (
    WidgetTester tester,
  ) async {
    final MockClient client = MockClient((http.Request request) async {
      throw StateError('Unexpected request: ${request.method} ${request.url.path}');
    });
    addTearDown(client.close);
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: Uri.parse('https://example.com'),
      client: client,
    );
    final GirlsShopApi shopApi = GirlsShopApi(
      baseUri: Uri.parse('https://example.com'),
      client: client,
    );
    addTearDown(shopApi.close);
    final GirlsShopApp app = GirlsShopApp(
      appId: appId,
      version: '3',
      title: 'ねこゲーム',
      ownerUserId: ownerUserId,
      ownerDisplayName: 'ねこさん',
      publishedAt: DateTime.utc(2026, 9, 30),
      sha256: List<String>.filled(64, 'd').join(),
    );

    await tester.pumpWidget(MaterialApp(
      home: GirlsShopDetailPage(
        api: api,
        shopApi: shopApi,
        session: null,
        app: app,
        currentGroup: null,
        onHideCreator: (_) async {},
      ),
    ));
    await tester.pumpAndSettle();
    final Finder play = find.widgetWithText(FilledButton, 'あそんでみる');
    expect(play, findsOneWidget);
    expect(tester.widget<FilledButton>(play).onPressed, isNotNull);
    expect(find.text('おためしプレイの記録は保存されません'), findsOneWidget);
    expect(find.text('遊ぶには登録・ログイン'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: GirlsShopDetailPage(
        key: const ValueKey<String>('signed-in-shop'),
        api: api,
        shopApi: shopApi,
        session: const AuthenticatedSession(
          accessToken: 'signed-in-test-token',
          expiresIn: 3600,
        ),
        app: app,
        currentGroup: null,
        onHideCreator: (_) async {},
      ),
    ));
    await tester.pumpAndSettle();
    final Finder signedPlay = find.widgetWithText(FilledButton, 'あそんでみる');
    expect(signedPlay, findsOneWidget);
    expect(tester.widget<FilledButton>(signedPlay).onPressed, isNotNull);
    expect(find.text('おためしプレイの記録は保存されません'), findsNothing);
  });

  testWidgets(
    'install-state failure keeps shop mutation disabled',
    (WidgetTester tester) async {
      int addRequests = 0;
      final MockClient client = MockClient((http.Request request) async {
        if (request.method == 'GET' &&
            request.url.path == '/hosted/groups/$groupId/apps') {
          return jsonResponse(
            <String, Object?>{
              'error': 'temporary_failure',
              'message': 'install state unavailable',
            },
            503,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/shop/apps/$appId/add') {
          addRequests += 1;
          return jsonResponse(<String, Object?>{}, 500);
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url.path}',
        );
      });
      addTearDown(client.close);

      final HostedGirlsApi api = HostedGirlsApi(
        baseUri: Uri.parse('https://example.com'),
        client: client,
      );
      final GirlsShopApi shopApi = GirlsShopApi(
        baseUri: Uri.parse('https://example.com'),
        client: client,
      );
      addTearDown(shopApi.close);

      await tester.pumpWidget(
        MaterialApp(
          home: GirlsShopDetailPage(
            api: api,
            shopApi: shopApi,
            session: const AuthenticatedSession(
              accessToken: 'test-token',
              expiresIn: 3600,
            ),
            app: GirlsShopApp(
              appId: appId,
              version: '1',
              title: 'ねこゲーム',
              ownerUserId: ownerUserId,
              ownerDisplayName: 'ねこさん',
              publishedAt: DateTime.utc(2026, 9, 30),
              sha256: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
            ),
            currentGroup: const HostedGroup(
              groupId: groupId,
              name: 'テストグループ',
              role: 'owner',
              status: 'active',
            ),
            onHideCreator: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder mutationButton = find.widgetWithText(
        OutlinedButton,
        '追加状況を確認できません',
      );
      expect(mutationButton, findsOneWidget);
      expect(tester.widget<OutlinedButton>(mutationButton).onPressed, isNull);

      await tester.tap(mutationButton);
      await tester.pump();
      expect(addRequests, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
