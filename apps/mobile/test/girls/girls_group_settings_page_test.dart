import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_group_settings_page.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const String _groupId = '0123456789abcdef0123456789abcdef';
const String _groupCode = '8TUS-UDGS-XYPW';

void main() {
  testWidgets('shows the permanent group ID and copy action', (
    WidgetTester tester,
  ) async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/hosted/groups/$_groupId/invite');
      return http.Response(
        jsonEncode(<String, Object?>{
          'group_id': _groupId,
          'code': _groupCode,
          'expires_at': '2099-01-01T00:00:00Z',
          'valid_for_seconds': 1,
        }),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    addTearDown(client.close);

    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: Uri.parse('https://example.com'),
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GirlsGroupSettingsPage(
          api: api,
          session: const AuthenticatedSession(
            accessToken: 'test-token',
            expiresIn: 3600,
          ),
          group: const HostedGroup(
            groupId: _groupId,
            name: 'みんなのアトリエ',
            role: 'owner',
            status: 'active',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('girls-group-settings-group-id')),
      findsOneWidget,
    );
    expect(find.text(_groupCode), findsOneWidget);
    expect(
      find.byKey(const Key('girls-group-settings-group-id-copy')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('owner can delete the group after confirmation', (
    WidgetTester tester,
  ) async {
    final List<String> requests = <String>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'POST' &&
          request.url.path == '/hosted/groups/$_groupId/invite') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'group_id': _groupId,
            'code': _groupCode,
            'expires_at': '2099-01-01T00:00:00Z',
            'valid_for_seconds': 1,
          }),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      if (request.method == 'DELETE' &&
          request.url.path == '/hosted/groups/$_groupId') {
        return http.Response('', 204);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    addTearDown(client.close);

    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: Uri.parse('https://example.com'),
      client: client,
    );
    GirlsGroupSettingsResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => FilledButton(
            key: const Key('open-settings'),
            onPressed: () async {
              result = await Navigator.of(context).push<GirlsGroupSettingsResult>(
                MaterialPageRoute<GirlsGroupSettingsResult>(
                  builder: (_) => GirlsGroupSettingsPage(
                    api: api,
                    session: const AuthenticatedSession(
                      accessToken: 'test-token',
                      expiresIn: 3600,
                    ),
                    group: const HostedGroup(
                      groupId: _groupId,
                      name: 'みんなのアトリエ',
                      role: 'owner',
                      status: 'active',
                    ),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('girls-group-settings-delete')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('girls-group-settings-leave')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('girls-group-settings-delete')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('girls-group-settings-remove-confirm')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('girls-group-settings-remove-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(requests, contains('DELETE /hosted/groups/$_groupId'));
    expect(result?.removed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('member can leave without loading owner-only settings', (
    WidgetTester tester,
  ) async {
    final List<String> requests = <String>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'DELETE' &&
          request.url.path == '/hosted/groups/$_groupId/membership') {
        return http.Response('', 204);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    addTearDown(client.close);

    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: Uri.parse('https://example.com'),
      client: client,
    );
    GirlsGroupSettingsResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => FilledButton(
            key: const Key('open-settings'),
            onPressed: () async {
              result = await Navigator.of(context).push<GirlsGroupSettingsResult>(
                MaterialPageRoute<GirlsGroupSettingsResult>(
                  builder: (_) => GirlsGroupSettingsPage(
                    api: api,
                    session: const AuthenticatedSession(
                      accessToken: 'test-token',
                      expiresIn: 3600,
                    ),
                    group: const HostedGroup(
                      groupId: _groupId,
                      name: 'みんなのアトリエ',
                      role: 'member',
                      status: 'active',
                    ),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('girls-group-settings-name')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('girls-group-settings-group-id')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('girls-group-settings-leave')),
      findsOneWidget,
    );
    expect(
      requests.where((String value) => value.startsWith('POST ')),
      isEmpty,
    );

    await tester.tap(find.byKey(const Key('girls-group-settings-leave')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('girls-group-settings-remove-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(
      requests,
      contains('DELETE /hosted/groups/$_groupId/membership'),
    );
    expect(result?.removed, isTrue);
    expect(tester.takeException(), isNull);
  });

}
