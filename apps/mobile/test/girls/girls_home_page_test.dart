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
      return http.Response(
        jsonEncode(<String, Object?>{
          'groups': <Object?>[
            <String, Object?>{
              'group_id': _currentGroup.groupId,
              'name': _currentGroup.name,
              'role': _currentGroup.role,
              'status': _currentGroup.status,
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
    expect(find.text('ビルトインアプリ'), findsOneWidget);
    expect(find.text('友達の最新情報'), findsOneWidget);
    expect(find.byKey(const Key('girls-home-memo-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-minappchi-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-novel-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-groups')), findsOneWidget);
    expect(find.text('放課後イラスト部'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('girls-home-memo-app')));
    await tester.pump();
    expect(find.text('マイメモ帳は準備中だよ'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));

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
    expect(find.text('ビルトインアプリ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
