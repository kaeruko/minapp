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

  Widget page(GirlsAppManagementApi api) => MaterialApp(
        home: GirlsAppEditEntryPage(
          api: api,
          accessToken: 'test-token',
          groupId: _groupId,
          appId: _appId,
          title: 'おえかき',
          expectedRevision: 1,
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
    expect(find.text('背景をピンクにしたい'), findsOneWidget);
    expect(find.text('ボタンをもっとかわいくしたい'), findsOneWidget);
    expect(find.text('犬の画像を追加したい'), findsOneWidget);
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

    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    expect(find.text('コードを編集！'), findsOneWidget);

    await tester.tap(find.byKey(const Key('girls-edit-entry-open-editor')));
    await tester.pumpAndSettle();
    expect(sourceReads, 1);
    expect(find.byKey(const Key('girls-source-editor-code')), findsOneWidget);
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
        if (call.method != 'Clipboard.setData') {
          throw StateError('Unexpected platform call: ${call.method}');
        }
        final Object? arguments = call.arguments;
        if (arguments is! Map<Object?, Object?>) {
          throw StateError('Clipboard.setData arguments are not a map.');
        }
        final Object? text = arguments['text'];
        if (text is! String) {
          throw StateError('Clipboard.setData text is not a string.');
        }
        copiedText = text;
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
    expect(copiedText, contains('これは「みんアプGirls」で動くミニアプリです。'));
    expect(copiedText, contains('アプリ名: おえかき'));
    expect(copiedText, contains('===== index.html ====='));
    expect(copiedText, contains('<html><body>Hello</body></html>'));
    expect(copiedText, contains('===== style.css ====='));
    expect(copiedText, contains('body { background: white; }'));

    ScaffoldMessenger.of(
      tester.element(find.byType(GirlsAppEditEntryPage)),
    ).removeCurrentSnackBar();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
