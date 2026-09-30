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
              sha256: 'd' * 64,
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
