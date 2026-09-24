import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_home_page.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const HostedGroup _currentGroup = HostedGroup(
  groupId: '0123456789abcdef0123456789abcdef',
  name: '放課後イラスト部',
  role: 'owner',
  status: 'active',
);

HostedGirlsApi _fakeApi() {
  return HostedGirlsApi(
    baseUri: Uri.parse('https://example.com'),
    client: MockClient((http.Request request) async {
      final String path = request.url.path;
      late final Map<String, Object?> payload;
      if (path == '/hosted/groups') {
        payload = <String, Object?>{
          'groups': <Object?>[
            <String, Object?>{
              'group_id': _currentGroup.groupId,
              'name': _currentGroup.name,
              'role': _currentGroup.role,
              'status': _currentGroup.status,
            },
          ],
        };
      } else if (path ==
          '/hosted/groups/${_currentGroup.groupId}/members') {
        payload = <String, Object?>{
          'members': <Object?>[
            <String, Object?>{
              'user_id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'login_id': 'owner',
              'role': 'owner',
              'status': 'active',
            },
          ],
        };
      } else if (path == '/hosted/groups/${_currentGroup.groupId}/apps') {
        payload = <String, Object?>{'apps': <Object?>[]};
      } else {
        fail('Unexpected request: ${request.method} ${request.url}');
      }
      return http.Response(
        jsonEncode(payload),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    }),
  );
}

void main() {
  testWidgets('Girls home shows the intended four cards and opens group creation', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GirlsHomePage(
          api: _fakeApi(),
          session: const AuthenticatedSession(
            accessToken: 'test-token',
            expiresIn: 3600,
          ),
          onLogout: () {},
          currentGroup: _currentGroup,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('girls-header-leading-tray')), findsOneWidget);
    expect(find.byKey(const Key('girls-header-actions-tray')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-mascot-prompt')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-mascot-image')), findsOneWidget);
    expect(find.text('友達を招待する？'), findsOneWidget);
    expect(find.text('公式アプリ'), findsOneWidget);
    expect(find.text('友達の最新情報'), findsOneWidget);
    expect(find.byKey(const Key('girls-home-memo-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-minappchi-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-novel-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-groups')), findsOneWidget);
    expect(find.text('放課後イラスト部'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('girls-home-memo-app')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('マイメモ帳'), findsOneWidget);
    expect(find.text('マイメモ帳は準備中だよ'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('✨ このアプリをアレンジする？'), findsOneWidget);
    expect(find.text('このアプリをアレンジする！'), findsOneWidget);
    await tester.tap(find.byKey(const Key('girls-builtin-arrange-later')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('girls-home-settings')));
    await tester.pumpAndSettle();
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('メールアドレス'), findsOneWidget);
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('girls-home-groups')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('girls-home-groups')));
    await tester.pumpAndSettle();

    expect(find.text('💗 新しいグループ'), findsOneWidget);
    expect(find.byKey(const Key('girls-group-name')), findsOneWidget);
    expect(find.text('グループ名'), findsOneWidget);
    expect(find.text('やめる'), findsOneWidget);
    expect(find.text('つくる'), findsOneWidget);

    await tester.tap(find.text('やめる'));
    await tester.pumpAndSettle();
    expect(find.text('💗 新しいグループ'), findsNothing);

    await tester.tap(find.byKey(const Key('girls-footer-groups')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('girls-groups-first-view-group')),
      findsOneWidget,
    );
    expect(find.text('いまのグループ'), findsOneWidget);
    expect(find.text('あなたがオーナーです'), findsOneWidget);
    expect(find.text('グループを開く'), findsOneWidget);

    await tester.tap(find.byKey(const Key('girls-footer-home')));
    await tester.pumpAndSettle();
    expect(find.text('公式アプリ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
