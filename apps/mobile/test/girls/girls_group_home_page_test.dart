import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_community.dart';
import 'package:minapp_mobile/girls/girls_group_home_page.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const String _groupId = '0123456789abcdef0123456789abcdef';
const String _inviteCode = '8TUS-UDGS-XYPW';

void main() {
  testWidgets('group home shows the invite code instead of the Girls title', (
    WidgetTester tester,
  ) async {
    final MockClient client = MockClient((http.Request request) async {
      if (request.method == 'POST' &&
          request.url.path == '/hosted/groups/$_groupId/invite') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'group_id': _groupId,
            'code': _inviteCode,
            'expires_at': '2099-01-01T00:00:00Z',
            'valid_for_seconds': 1,
          }),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      if (request.method == 'GET' &&
          request.url.path == '/hosted/groups/$_groupId/apps') {
        return http.Response(
          jsonEncode(<String, Object?>{'apps': <Object?>[]}),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    addTearDown(client.close);

    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: Uri.parse('https://example.com'),
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GirlsGroupHomePage(
          api: api,
          session: const AuthenticatedSession(
            accessToken: 'test-token',
            expiresIn: 3600,
          ),
          group: const HostedGroup(
            groupId: _groupId,
            name: '放課後おやすみクラブ',
            role: 'owner',
            status: 'active',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('招待コード $_inviteCode'), findsOneWidget);
    expect(find.byKey(const Key('girls-private-group-make')), findsOneWidget);
    expect(find.text('みんアプ Girls'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('community home lists apps without requesting an invite', (
    WidgetTester tester,
  ) async {
    final List<String> requests = <String>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add('${request.method} ${request.url.path}');
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/hosted/groups/$girlsCommunityGroupId/apps',
      );
      return http.Response(
        jsonEncode(<String, Object?>{'apps': <Object?>[]}),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    addTearDown(client.close);

    await tester.pumpWidget(
      MaterialApp(
        home: GirlsGroupHomePage(
          api: HostedGirlsApi(
            baseUri: Uri.parse('https://example.com'),
            client: client,
          ),
          session: const AuthenticatedSession(
            accessToken: 'test-token',
            expiresIn: 3600,
          ),
          group: const HostedGroup(
            groupId: girlsCommunityGroupId,
            name: girlsCommunityGroupName,
            role: 'member',
            status: 'active',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requests, <String>[
      'GET /hosted/groups/$girlsCommunityGroupId/apps',
    ]);
    expect(find.text(girlsCommunityGroupName), findsWidgets);
    expect(find.text('全員で楽しむ共通スペース'), findsOneWidget);
    expect(find.byKey(const Key('girls-group-invite')), findsNothing);
    expect(find.byKey(const Key('girls-private-group-make')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
