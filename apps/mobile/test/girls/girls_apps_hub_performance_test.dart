import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_apps_cache.dart';
import 'package:minapp_mobile/girls/girls_apps_hub_page.dart';
import 'package:minapp_mobile/girls/girls_source_zip.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const _groupId = '11111111111111111111111111111111';
const _editorId = '22222222222222222222222222222222';
const _playerId = '33333333333333333333333333333333';
const _userId = '44444444444444444444444444444444';
const _publishedAppId = '55555555555555555555555555555555';
const _blankAppId = '66666666666666666666666666666666';
const _group = HostedGroup(
    groupId: _groupId, name: 'My group', role: 'owner', status: 'active');

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, Object?> _builtin(bool editor) => {
      'app_id': editor ? _editorId : _playerId,
      'group_id': _groupId,
      'owner_user_id': _userId,
      'title': editor ? 'Novel maker' : 'Novel player',
      'source_kind': 'builtin',
      'builtin_id': editor ? 'novel-editor' : 'novel-starter',
      'created_at': '2026-09-17T00:00:00Z',
      'editable': false,
    };

Map<String, Object?> _publishedApp() => {
      'app_id': _publishedAppId,
      'group_id': _groupId,
      'owner_user_id': _userId,
      'title': 'みんあぷっち',
      'source_kind': 'zip',
      'created_at': '2026-09-10T00:00:00Z',
      'source_updated_at': '2026-09-21T00:00:00Z',
      'published_at': '2026-09-21T00:00:00Z',
      'published_version': 2,
      'editable': true,
      'source_revision': 2,
      'visibility': 'visible',
      'stats': {
        'total_plays': 3,
        'unique_users': 1,
        'monthly_plays': 3,
      },
      'group_name': 'My group',
    };

http.Response _response(http.Request request) {
  switch (request.url.path) {
    case '/hosted/groups':
      return _json({
        'groups': [
          {
            'group_id': _groupId,
            'name': 'My group',
            'role': 'owner',
            'status': 'active',
          }
        ]
      });
    case '/hosted/groups/$_groupId/apps':
      return _json({
        'apps': [_builtin(true), _builtin(false)]
      });
    case '/hosted/authoring/groups/$_groupId/apps':
      return _json({
        'apps': [
          {
            'app_id': _editorId,
            'group_id': _groupId,
            'title': 'Novel maker',
            'edits': ['minapp/novel@1'],
            'accepts': <String>[],
          }
        ]
      });
    case '/hosted/my/apps':
      return _json({'apps': [_publishedApp()]});
  }
  throw StateError('Unexpected request: ${request.method} ${request.url.path}');
}

Widget _page(
  HostedGirlsApi api,
  GirlsAppsCache cache, {
  String token = 'token-a',
  String key = 'page',
  HostedGroup group = _group,
}) =>
    MaterialApp(
        home: GirlsAppsPage(
      key: ValueKey(key),
      api: api,
      session: AuthenticatedSession(accessToken: token, expiresIn: 3600),
      currentGroup: group,
      cache: cache,
    ));

void main() {

  testWidgets('blank app creation uploads starter ZIP and opens code editor',
      (tester) async {
    Uint8List? uploadedZip;
    final paths = <String>[];
    final api = HostedGirlsApi(
      baseUri: Uri.parse('https://example.test'),
      client: MockClient((request) async {
        paths.add('${request.method} ${request.url.path}');
        if (request.method == 'POST' &&
            request.url.path == '/hosted/groups/$_groupId/apps/upload') {
          expect(request.url.queryParameters['title'], '推し活タイマー');
          expect(request.headers['Content-Type'], 'application/zip');
          uploadedZip = Uint8List.fromList(request.bodyBytes);
          final GirlsSourceArchive archive =
              GirlsSourceArchive.decode(uploadedZip!);
          expect(archive.paths, contains('index.html'));
          expect(
            archive.readText('index.html'),
            contains('ここから自由にアレンジしてみよう'),
          );
          return _json(<String, Object?>{
            'app_id': _blankAppId,
            'group_id': _groupId,
            'owner_user_id': _userId,
            'title': '推し活タイマー',
            'source_kind': 'zip',
            'created_at': '2026-09-25T12:00:00Z',
            'source_updated_at': '2026-09-25T12:00:00Z',
            'published_version': null,
            'editable': true,
            'source_revision': 1,
          }, 201);
        }
        if (request.method == 'GET' &&
            request.url.path ==
                '/hosted/groups/$_groupId/apps/$_blankAppId/source') {
          final Uint8List bytes = uploadedZip ??
              (throw StateError('Source requested before starter upload.'));
          return http.Response.bytes(
            bytes,
            200,
            headers: <String, String>{
              'content-type': 'application/zip',
              'x-minapp-source-revision': '1',
              'x-minapp-source-sha256': '0' * 64,
            },
          );
        }
        return _response(request);
      }),
    );

    await tester.pumpWidget(_page(api, GirlsAppsCache()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('girls-create-blank-app')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('girls-create-blank-app')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('girls-create-blank-app-dialog')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('girls-create-blank-app-title')),
      '推し活タイマー',
    );
    await tester.tap(
      find.byKey(const Key('girls-create-blank-app-confirm')),
    );
    await tester.pumpAndSettle();

    expect(
      paths,
      contains('POST /hosted/groups/$_groupId/apps/upload'),
    );
    expect(find.text('推し活タイマー のコード'), findsOneWidget);
    expect(
      find.byKey(const Key('girls-source-editor-code')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('four requests, parallel reads, no sample on list display',
      (tester) async {
    final paths = <String>[];
    final apps = Completer<http.Response>();
    final api = HostedGirlsApi(
        baseUri: Uri.parse('https://example.test'),
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/hosted/groups/$_groupId/apps')
            return apps.future;
          return _response(request);
        }));
    await tester.pumpWidget(_page(api, GirlsAppsCache()));
    await tester.pump();
    // The managed-app request must start without waiting for maker discovery.
    expect(paths, contains('/hosted/my/apps'));
    expect(paths, isNot(contains('/hosted/authoring/groups/$_groupId/apps')));
    apps.complete(_json({
      'apps': [_builtin(true), _builtin(false)]
    }));
    await tester.pumpAndSettle();
    expect(paths, hasLength(4));
    expect(find.text('Novel maker'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('みんあぷっち'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('みんあぷっち'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'girls-app-play-published-$_publishedAppId',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cached list shows immediately, is refreshed, and cannot cross sessions',
      (tester) async {
    final cache = GirlsAppsCache();
    Completer<http.Response>? refresh;
    final api = HostedGirlsApi(
        baseUri: Uri.parse('https://example.test'),
        client: MockClient((request) async {
          if (request.url.path == '/hosted/groups' && refresh != null)
            return refresh.future;
          return _response(request);
        }));
    await tester.pumpWidget(_page(api, cache));
    await tester.pumpAndSettle();
    refresh = Completer<http.Response>();
    await tester.pumpWidget(_page(api, cache, key: 'reopened'));
    expect(find.text('Novel maker'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(cache.read('token-a', _playerId), isNull);
    await tester
        .pumpWidget(_page(api, cache, token: 'token-b', key: 'other-user'));
    expect(find.text('Novel maker'), findsNothing);
    refresh.complete(_response(
        http.Request('GET', Uri.parse('https://example.test/hosted/groups'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('parallel request error clears cached data and stops spinners',
      (tester) async {
    final cache = GirlsAppsCache();
    var fail = false;
    final api = HostedGirlsApi(
        baseUri: Uri.parse('https://example.test'),
        client: MockClient((request) async {
          if (fail && request.url.path == '/hosted/my/apps') {
            return _json(
                {'error': 'forbidden', 'message': 'Access revoked'}, 403);
          }
          return _response(request);
        }));
    await tester.pumpWidget(_page(api, cache));
    await tester.pumpAndSettle();
    fail = true;
    await tester.pumpWidget(_page(api, cache, key: 'refresh-failure'));
    await tester.pumpAndSettle();
    expect(find.text('Access revoked'), findsOneWidget);
    expect(find.text('Novel maker'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('もう一度読み込む'), findsOneWidget);
    expect(cache.read('token-a', _groupId), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale request cannot overwrite a changed group',
      (tester) async {
    final cache = GirlsAppsCache();
    final stale = Completer<http.Response>();
    var reads = 0;
    final api = HostedGirlsApi(
        baseUri: Uri.parse('https://example.test'),
        client: MockClient((request) async {
          if (request.url.path == '/hosted/groups') {
            if (++reads == 1) return stale.future;
            return _json({'groups': <Object>[]});
          }
          return _response(request);
        }));
    await tester.pumpWidget(_page(api, cache));
    await tester.pump();
    await tester.pumpWidget(_page(api, cache,
        group: const HostedGroup(
            groupId: _playerId,
            name: 'Other group',
            role: 'member',
            status: 'active')));
    await tester.pumpAndSettle();
    stale.complete(_response(
        http.Request('GET', Uri.parse('https://example.test/hosted/groups'))));
    await tester.pumpAndSettle();
    expect(find.text('Novel maker'), findsNothing);
    expect(cache.read('token-a', _groupId), isNull);
    expect(tester.takeException(), isNull);
  });
}
