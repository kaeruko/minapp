import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_community.dart';
import 'package:minapp_mobile/girls/girls_groups_dashboard_page.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const HostedGroup _privateGroup = HostedGroup(
  groupId: '0123456789abcdef0123456789abcdef',
  name: '放課後イラスト部',
  role: 'owner',
  status: 'active',
);

HostedGirlsApi _fakeApi({required bool includePrivateGroup}) {
  return HostedGirlsApi(
    baseUri: Uri.parse('https://example.com'),
    client: MockClient((http.Request request) async {
      if (request.method != 'GET' || request.url.path != '/hosted/groups') {
        fail('Unexpected request: ${request.method} ${request.url}');
      }
      return http.Response(
        jsonEncode(<String, Object?>{
          'groups': <Object?>[
            <String, Object?>{
              'group_id': girlsCommunityGroupId,
              'name': girlsCommunityGroupName,
              'role': 'member',
              'status': 'active',
            },
            if (includePrivateGroup)
              <String, Object?>{
                'group_id': _privateGroup.groupId,
                'name': _privateGroup.name,
                'role': _privateGroup.role,
                'status': _privateGroup.status,
              },
          ],
        }),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    }),
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required bool includePrivateGroup,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: GirlsGroupsDashboardPage(
        api: _fakeApi(includePrivateGroup: includePrivateGroup),
        session: const AuthenticatedSession(
          accessToken: 'test-token',
          expiresIn: 3600,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('community is implicit and private groups are optional', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, includePrivateGroup: false);

    expect(find.text('友達グループ'), findsOneWidget);
    expect(find.textContaining(girlsCommunityGroupName), findsOneWidget);
    expect(find.text('参加中のグループ'), findsOneWidget);
    expect(find.textContaining('普通に遊ぶだけなら'), findsOneWidget);
    expect(find.byKey(const Key('girls-group-find')), findsOneWidget);
    expect(find.byKey(const Key('girls-group-create')), findsOneWidget);
    expect(find.text('切り替える'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('private group is listed without becoming a current group', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, includePrivateGroup: true);

    expect(find.text(_privateGroup.name), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'girls-private-group-0123456789abcdef0123456789abcdef',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('切り替える'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
