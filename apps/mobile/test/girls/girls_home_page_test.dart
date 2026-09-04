import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_home_page.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

HostedGirlsApi _fakeApi() {
  return HostedGirlsApi(
    baseUri: Uri.parse('https://example.com'),
    client: MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'groups': <Object?>[
            <String, Object?>{
              'group_id': '0123456789abcdef0123456789abcdef',
              'name': '放課後イラスト部',
              'role': 'owner',
              'status': 'active',
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
  testWidgets('Girls home opens group creation dialog from the create card', (
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('こんにちは、ハニー！\n今日も楽しもうね♪'), findsOneWidget);
    expect(find.text('ビルトインアプリ'), findsOneWidget);
    expect(find.text('友達の最新情報'), findsOneWidget);
    expect(find.byKey(const Key('girls-home-mascot-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-novel-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-paint-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-groups')), findsOneWidget);
    expect(find.text('放課後イラスト部'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('girls-home-settings')));
    await tester.pumpAndSettle();
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('メールアドレス'), findsOneWidget);
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('girls-home-groups')));
    await tester.pumpAndSettle();

    expect(find.text('💗 新しいグループ'), findsOneWidget);
    expect(find.byKey(const Key('girls-group-name')), findsOneWidget);
    expect(find.text('グループ名'), findsOneWidget);
    expect(find.text('やめる'), findsOneWidget);
    expect(find.text('つくる'), findsOneWidget);
    expect(find.text('ビルトインアプリ'), findsOneWidget);

    await tester.tap(find.text('やめる'));
    await tester.pumpAndSettle();
    expect(find.text('💗 新しいグループ'), findsNothing);

    await tester.tap(find.byKey(const Key('girls-footer-groups')));
    await tester.pumpAndSettle();
    expect(find.text('どのグループで遊ぶ？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('girls-footer-home')));
    await tester.pumpAndSettle();
    expect(find.text('ビルトインアプリ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
