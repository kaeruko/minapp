import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/girls_app_edit_entry_page.dart';
import 'package:minapp_mobile/girls/girls_app_management_api.dart';
import 'package:minapp_mobile/girls/girls_source_zip.dart';

const String _groupId = '11111111111111111111111111111111';
const String _appId = '22222222222222222222222222222222';

void main() {
  testWidgets('AI-first edit entry shows help, copy, examples, and editor path', (
    WidgetTester tester,
  ) async {
    final GirlsSourceArchive archive = GirlsSourceArchive.fromEntries(
      <String, Uint8List>{
        'index.html': Uint8List.fromList(
          utf8.encode('<html><body>Hello</body></html>'),
        ),
        'style.css': Uint8List.fromList(
          utf8.encode('body { background: white; }'),
        ),
      },
    );
    int sourceReads = 0;
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(
        request.url.path,
        '/hosted/groups/$_groupId/apps/$_appId/source',
      );
      sourceReads += 1;
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
    addTearDown(client.close);

    final GirlsAppManagementApi api = GirlsAppManagementApi(
      baseUri: Uri.parse('https://example.com'),
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GirlsAppEditEntryPage(
          api: api,
          accessToken: 'test-token',
          groupId: _groupId,
          appId: _appId,
          title: 'おえかき',
          expectedRevision: 1,
        ),
      ),
    );

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

    await tester.tap(find.byKey(const Key('girls-edit-entry-copy')));
    await tester.pumpAndSettle();
    expect(sourceReads, 1);
    expect(find.text('AIに貼り付けるコードをコピーしたよ'), findsOneWidget);

    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    expect(find.text('コードを編集！'), findsOneWidget);
    expect(
      find.byKey(const Key('girls-edit-entry-open-editor')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('girls-edit-entry-open-editor')));
    await tester.pumpAndSettle();
    expect(sourceReads, 2);
    expect(find.byKey(const Key('girls-source-editor-code')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
