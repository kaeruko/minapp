import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_apps_page.dart';
import 'package:minapp_mobile/girls/girls_source_zip.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const appId = 'a123456789abcdef0123456789abcdef';
const groupId = 'b123456789abcdef0123456789abcdef';

Map<String, Object?> fixture(
        {bool hidden = false, int? version = 1, int revision = 1}) =>
    {
      'app_id': appId,
      'group_id': groupId,
      'title': '私の小さな星物語',
      'source_kind': 'zip',
      'created_at': '2026-09-01T00:00:00Z',
      'owner_user_id': 'c123456789abcdef0123456789abcdef',
      'editable': true,
      'source_revision': revision,
      'published_version': version,
      'source_updated_at': '2026-09-18T00:00:00Z',
      'published_at': version == null ? null : '2026-09-02T00:00:00Z',
      'visibility': hidden ? 'hidden' : 'visible',
      'stats': {'total_plays': 3456, 'unique_users': 100, 'monthly_plays': 42},
      'source_history': [],
      'published_history': version == null
          ? []
          : [
              {
                'version': version,
                'source_revision': 1,
                'published_at': '2026-09-02T00:00:00Z',
                'sha256': '0' * 64,
              }
            ],
    };

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json'},
    );

Future<void> showPage(WidgetTester tester, MockClient client,
    {double width = 390, double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(client.close);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: GirlsAppDetailPage(
      api: HostedGirlsApi(
          baseUri: Uri.parse('https://example.com'), client: client),
      session: const AuthenticatedSession(
          accessToken: 'test-token', expiresIn: 3600),
      appId: appId,
    ),
  ));
  await tester.pumpAndSettle();
  expect(find.text('私の小さな星物語'), findsWidgets,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join('\n'));
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('detail hierarchy and separate date rows at width $width',
        (tester) async {
      await showPage(
          tester,
          MockClient((request) async => jsonResponse(
              request.url.path == '/hosted/my/apps/$appId'
                  ? fixture()
                  : {'apps': <Object?>[]})),
          width: width);
      expect(find.text('アプリ詳細'), findsOneWidget);
      expect(find.text('アプリ名'), findsNothing);
      expect(find.text('アプリ情報'), findsNothing);
      expect(find.text('プレビュー'), findsOneWidget);
      final AppBar appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.primary, isFalse);
      expect(find.text('3456回'), findsOneWidget);
      final published = find.byKey(const Key('girls-app-published-date'));
      final updated = find.byKey(const Key('girls-app-updated-date'));
      expect(tester.getTopLeft(updated).dy,
          greaterThan(tester.getBottomLeft(published).dy));
      expect(find.text('新しいZIPで更新'), findsNothing);
      expect(find.text('公開中のアプリを試す'), findsNothing);
      expect(find.text('📦'), findsOneWidget);
      expect(tester.getSize(find.text('📦')).width, lessThan(35));
      await tester.ensureVisible(find.byKey(const Key('girls-app-edit-code')));
      expect(find.text('アプリを編集'), findsOneWidget);
      expect(find.text('編集版をプレビュー'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'preview always requests the current draft, not the published app',
      (tester) async {
    final paths = <String>[];
    await showPage(tester, MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/preview-session')) {
        return jsonResponse(
            {'error': 'test_preview', 'message': 'Test preview response'}, 400);
      }
      return jsonResponse(request.url.path == '/hosted/my/apps/$appId'
          ? fixture()
          : {'apps': <Object?>[]});
    }));
    final preview = find.byKey(const Key('girls-app-preview-latest'));
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(paths, contains('/hosted/my/apps/$appId/preview-session'));
    expect(paths.any((path) => path.endsWith('/published-session')), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'published visibility switch hides and restores without republishing',
      (tester) async {
    bool hidden = false;
    final requests = <bool>[];
    await showPage(tester, MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.url.path, '/hosted/my/apps/$appId/visibility');
        hidden = (jsonDecode(request.body) as Map)['hidden'] as bool;
        requests.add(hidden);
        return jsonResponse(fixture(hidden: hidden));
      }
      return jsonResponse(request.url.path == '/hosted/my/apps/$appId'
          ? fixture(hidden: hidden)
          : {'apps': <Object?>[]});
    }));
    final toggle = find.byKey(const Key('girls-app-visibility'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(requests, [true, false]);
    expect(tester.widget<Switch>(toggle).value, isTrue);
  });

  testWidgets('first publication also restores a hidden draft', (tester) async {
    bool hidden = true;
    int? version;
    final writes = <String>[];
    await showPage(tester, MockClient((request) async {
      if (request.method == 'POST') {
        writes.add(request.url.path);
        if (request.url.path.endsWith('/publish')) {
          expect(jsonDecode(request.body), {'revision': 1});
          version = 1;
          return jsonResponse({'published_version': 1, 'source_revision': 1});
        }
        expect(request.url.path.endsWith('/visibility'), isTrue);
        hidden = false;
        return jsonResponse(fixture(version: version));
      }
      return jsonResponse(request.url.path == '/hosted/my/apps/$appId'
          ? fixture(hidden: hidden, version: version)
          : {'apps': <Object?>[]});
    }));
    await tester.tap(find.byKey(const Key('girls-app-visibility')));
    await tester.pumpAndSettle();
    expect(writes, [
      '/hosted/groups/$groupId/apps/$appId/publish',
      '/hosted/my/apps/$appId/visibility'
    ]);
    expect(
        tester
            .widget<Switch>(find.byKey(const Key('girls-app-visibility')))
            .value,
        isTrue);
  });

  testWidgets('edit opens source editor and delete still requires confirmation',
      (tester) async {
    final archive = GirlsSourceArchive.fromEntries(
        {'index.html': Uint8List.fromList(utf8.encode('<html>hello</html>'))});
    await showPage(tester, MockClient((request) async {
      expect(request.method, 'GET');
      if (request.url.path.endsWith('/source')) {
        return http.Response.bytes(archive.encode(), 200, headers: {
          'content-type': 'application/zip',
          'x-minapp-source-revision': '1',
          'x-minapp-source-sha256': '0' * 64,
        });
      }
      return jsonResponse(request.url.path == '/hosted/my/apps/$appId'
          ? fixture()
          : {'apps': <Object?>[]});
    }));
    final edit = find.byKey(const Key('girls-app-edit-code'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('girls-source-editor-code')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final delete = find.byKey(const Key('girls-app-delete'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('このアプリを削除する？'), findsOneWidget);
    await tester.tap(find.text('やめる'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
