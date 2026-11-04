import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_community.dart';
import 'package:minapp_mobile/girls/girls_home_page.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const HostedGroup _currentGroup = HostedGroup(
  groupId: girlsCommunityGroupId,
  name: girlsCommunityGroupName,
  role: 'member',
  status: 'active',
);
const String _arrangedAppId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _ownerUserId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

HostedGirlsApi _fakeApi({List<String>? requests}) {
  return HostedGirlsApi(
    baseUri: Uri.parse('https://example.com'),
    client: MockClient((http.Request request) async {
      final String path = request.url.path;
      requests?.add('${request.method} $path');
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
      } else if (path == '/hosted/groups/${_currentGroup.groupId}/apps') {
        payload = <String, Object?>{'apps': <Object?>[]};
      } else if (request.method == 'POST' &&
          path == '/hosted/groups/${_currentGroup.groupId}/apps/upload') {
        expect(request.url.queryParameters['title'], 'マイメモ帳 アレンジ');
        expect(request.headers['content-type'], 'application/zip');
        expect(request.bodyBytes, isNotEmpty);
        payload = <String, Object?>{
          'app_id': _arrangedAppId,
          'group_id': _currentGroup.groupId,
          'title': 'マイメモ帳 アレンジ',
          'source_kind': 'zip',
          'created_at': '2026-09-25T00:00:00Z',
          'source_updated_at': '2026-09-25T00:00:00Z',
          'owner_user_id': _ownerUserId,
          'editable': true,
          'source_revision': 1,
        };
      } else if (request.method == 'GET' &&
          path == '/hosted/my/apps/$_arrangedAppId') {
        payload = <String, Object?>{
          'app_id': _arrangedAppId,
          'group_id': _currentGroup.groupId,
          'title': 'マイメモ帳 アレンジ',
          'source_kind': 'zip',
          'created_at': '2026-09-25T00:00:00Z',
          'source_updated_at': '2026-09-25T00:00:00Z',
          'owner_user_id': _ownerUserId,
          'editable': true,
          'source_revision': 1,
          'published_version': null,
          'visibility': 'visible',
          'stats': <String, Object?>{
            'total_plays': 0,
            'unique_users': 0,
            'monthly_plays': 0,
          },
          'source_history': <Object?>[],
          'published_history': <Object?>[],
        };
      } else {
        fail('Unexpected request: ${request.method} ${request.url}');
      }
      return http.Response(
        jsonEncode(payload),
        request.method == 'POST' ? 201 : 200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    }),
  );
}

void main() {
  testWidgets(
    'Girls home always resolves the system community',
    (WidgetTester tester) async {
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

      expect(find.text(_currentGroup.name), findsOneWidget);
      expect(find.text('アプリを作ってみよう！'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'arrange copies bundled source into the current group and opens app detail',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final List<String> requests = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: GirlsHomePage(
            api: _fakeApi(requests: requests),
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

      await tester.tap(find.byKey(const Key('girls-home-memo-app')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('girls-builtin-arrange-confirm')));
      await tester.pumpAndSettle();

      expect(
        requests,
        contains(
          'POST /hosted/groups/${_currentGroup.groupId}/apps/upload',
        ),
      );
      expect(find.text('アプリ詳細'), findsOneWidget);
      expect(find.text('マイメモ帳 アレンジ'), findsOneWidget);
      expect(find.text('指定されたビルトインアプリはありません。'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Player sample offers to copy the work instead of arranging the Player app',
    (WidgetTester tester) async {
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

      await tester.tap(find.byKey(const Key('girls-home-novel-app')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('✨ この作品を編集する？'), findsOneWidget);
      expect(
        find.text('「ひみつの放課後」をコピーして、自分だけの物語に編集できるよ。'),
        findsOneWidget,
      );
      expect(find.text('コピーして編集する！'), findsOneWidget);
      expect(find.text('このアプリをアレンジする！'), findsNothing);

      await tester.tap(find.byKey(const Key('girls-builtin-arrange-later')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
      'Girls home shows the intended four cards and opens group creation', (
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
    expect(find.text('アプリを作ってみよう！'), findsOneWidget);
    expect(find.text('公式アプリ'), findsOneWidget);
    expect(find.text('みんなの最新情報'), findsOneWidget);
    expect(find.byKey(const Key('girls-home-memo-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-minappchi-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-novel-app')), findsOneWidget);
    expect(find.byKey(const Key('girls-home-groups')), findsOneWidget);
    expect(find.text(girlsCommunityGroupName), findsOneWidget);
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
    expect(find.text('友達グループ'), findsOneWidget);
    expect(find.textContaining('普通に遊ぶだけなら'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('girls-footer-home')));
    await tester.pumpAndSettle();
    expect(find.text('公式アプリ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
