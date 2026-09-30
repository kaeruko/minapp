import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/girls_app_edit_entry_page.dart';
import 'package:minapp_mobile/girls/girls_app_management_api.dart';
import 'package:minapp_mobile/girls/girls_source_zip.dart';

const String _groupId = '11111111111111111111111111111111';
const String _appId = '22222222222222222222222222222222';
const String _userId = '33333333333333333333333333333333';

Map<String, Object?> managedAppJson(String title) => <String, Object?>{
      'app_id': _appId,
      'group_id': _groupId,
      'title': title,
      'source_kind': 'upload',
      'created_at': '2026-09-07T00:00:00Z',
      'published_version': null,
      'owner_user_id': _userId,
      'source_revision': 1,
      'source_updated_at': '2026-09-07T01:00:00Z',
      'published_at': null,
      'editable': true,
      'visibility': 'visible',
      'group_name': 'テストグループ',
      'stats': <String, Object?>{
        'total_plays': 0,
        'unique_users': 0,
        'monthly_plays': 0,
      },
    };

void main() {
  GirlsSourceArchive archive() => GirlsSourceArchive.fromEntries(
        <String, Uint8List>{
          'index.html': Uint8List.fromList(
            utf8.encode('<html><body>Hello</body></html>'),
          ),
          'style.css': Uint8List.fromList(
            utf8.encode('body { background: white; }'),
          ),
        },
      );

  MockClient sourceClient({
    required GirlsSourceArchive archive,
    required void Function() onRead,
  }) =>
      MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(
          request.url.path,
          '/hosted/groups/$_groupId/apps/$_appId/source',
        );
        onRead();
        return http.Response.bytes(
          archive.encode(),
          200,
          headers: <String, String>{
            'content-type': 'application/zip',
            'x-minapp-source-revision': '1',
            'x-minapp-source-sha256': '0' * 64,
          },
        );
      });

  Widget page(
    GirlsAppManagementApi api, {
    Future<void> Function()? onRenamed,
    Future<void> Function()? onIconChanged,
  }) =>
      MaterialApp(
        home: GirlsAppEditEntryPage(
          api: api,
          accessToken: 'test-token',
          groupId: _groupId,
          appId: _appId,
          title: 'おえかき',
          expectedRevision: 1,
          onRenamed: onRenamed,
          onIconChanged: onIconChanged,
        ),
      );

  testWidgets('AI-first edit entry shows help and opens the source editor', (
    WidgetTester tester,
  ) async {
    int sourceReads = 0;
    final MockClient client = sourceClient(
      archive: archive(),
      onRead: () => sourceReads += 1,
    );
    addTearDown(client.close);
    final GirlsAppManagementApi api = GirlsAppManagementApi(
      baseUri: Uri.parse('https://example.com'),
      client: client,
    );

    await tester.pumpWidget(page(api));

    expect(find.text('どうやってアレンジする？'), findsOneWidget);
    expect(find.text('AIといっしょにアレンジ'), findsOneWidget);
    expect(find.byKey(const Key('girls-edit-entry-back')), findsOneWidget);
    expect(find.byKey(const Key('girls-edit-entry-help')), findsOneWidget);
    expect(find.byKey(const Key('girls-edit-entry-copy')), findsOneWidget);
    expect(find.byKey(const Key('girls-edit-entry-icon-card')), findsOneWidget);
    expect(
      find.byKey(const Key('girls-edit-entry-change-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('girls-edit-entry-reset-icon')),
      findsOneWidget,
    );
    expect(find.text('背景をピンクにしたい'), findsOneWidget);
    expect(find.text('ボタンをもっとかわいくしたい'), findsOneWidget);
    expect(sourceReads, 0);

    await tester.tap(find.byKey(const Key('girls-edit-entry-help')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('girls-source-editor-help-dialog')),
      findsOneWidget,
    );
    expect(find.text('使い方ガイドを見る'), findsOneWidget);
    await tester.tap(find.byKey(const Key('girls-source-editor-help-close')));
    await tester.pumpAndSettle();

    final Finder openEditor = find.byKey(
      const Key('girls-edit-entry-open-editor'),
    );
    await tester.dragUntilVisible(
      openEditor,
      find.byType(Scrollable).first,
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    expect(find.text('犬の画像を追加したい'), findsOneWidget);
    expect(find.text('コードを編集！'), findsOneWidget);

    await tester.tap(openEditor);
    await tester.pumpAndSettle();
    expect(sourceReads, 1);
    expect(find.byKey(const Key('girls-source-editor-code')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app name can be renamed from the arrange entry screen', (
    WidgetTester tester,
  ) async {
    bool renamedCallback = false;
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/hosted/my/apps/$_appId');
      expect(request.headers['authorization'], 'Bearer test-token');
      expect(
        jsonDecode(request.body),
        <String, Object?>{'title': 'しばちゃん時計'},
      );
      return http.Response(
        jsonEncode(managedAppJson('しばちゃん時計')),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final GirlsAppManagementApi api = GirlsAppManagementApi(
      baseUri: Uri.parse('https://example.com'),
      client: client,
    );

    await tester.pumpWidget(
      page(
        api,
        onRenamed: () async {
          renamedCallback = true;
        },
      ),
    );

    expect(
      find.byKey(const Key('girls-edit-entry-app-title')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('girls-edit-entry-app-title')),
      'しばちゃん時計',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('girls-edit-entry-save-title')));
    await tester.pumpAndSettle();

    expect(renamedCallback, isTrue);
    expect(find.text('アプリ名を変更したよ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app icon can be reset from the arrange entry screen', (
    WidgetTester tester,
  ) async {
    bool iconChanged = false;
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/hosted/my/apps/$_appId/thumbnail');
      expect(request.headers['authorization'], 'Bearer test-token');
      return http.Response('', 204);
    });
    addTearDown(client.close);
    final GirlsAppManagementApi api = GirlsAppManagementApi(
      baseUri: Uri.parse('https://example.com'),
      client: client,
    );

    await tester.pumpWidget(
      page(
        api,
        onIconChanged: () async {
          iconChanged = true;
        },
      ),
    );

    await tester.tap(
      find.byKey(const Key('girls-edit-entry-reset-icon')),
    );
    await tester.pumpAndSettle();

    expect(iconChanged, isTrue);
    expect(find.text('アプリアイコンをデフォルトに戻したよ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI copy writes the current source to the clipboard', (
    WidgetTester tester,
  ) async {
    String? copiedText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          final Object? arguments = call.arguments;
          if (arguments is! Map<Object?, Object?>) {
            throw StateError('Clipboard.setData arguments are not a map.');
          }
          final Object? text = arguments['text'];
          if (text is! String) {
            throw StateError('Clipboard.setData text is not a string.');
          }
          copiedText = text;
        }
        return null;
      },
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    int sourceReads = 0;
    final MockClient client = sourceClient(
      archive: archive(),
      onRead: () => sourceReads += 1,
    );
    addTearDown(client.close);
    final GirlsAppManagementApi api = GirlsAppManagementApi(
      baseUri: Uri.parse('https://example.com'),
      client: client,
    );

    await tester.pumpWidget(page(api));
    await tester.tap(find.byKey(const Key('girls-edit-entry-copy')));
    await tester.pump();

    for (int attempt = 0; attempt < 20 && copiedText == null; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(sourceReads, 1);
    expect(copiedText, isNotNull);
    ScaffoldMessenger.of(
      tester.element(find.byType(GirlsAppEditEntryPage)),
    ).removeCurrentSnackBar();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
