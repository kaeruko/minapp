import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:minapp_mobile/hosted_app_management_api.dart';
import 'package:minapp_mobile/hosted_source_archive.dart';
import 'package:minapp_mobile/kobo/kobo_home_page.dart';
import 'package:minapp_mobile/kobo/kobo_source_editor_page.dart';
import 'package:minapp_mobile/kobo/kobo_theme.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture Kobo production widgets with deterministic sample data',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KoboTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const KoboHomePage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kobo-hero-sign')), findsOneWidget);
    await binding.takeScreenshot('01-home');

    const String groupId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const String appId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final HostedSourceArchive source = HostedSourceArchive.fromEntries(
      <String, Uint8List>{
        'index.html': Uint8List.fromList(
          utf8.encode('''<!doctype html>
<html lang="ja">
<head><meta charset="utf-8"><title>町中華メモ</title></head>
<body>
  <h1>町中華メモ</h1>
  <p>また行きたいお店を記録しよう。</p>
</body>
</html>'''),
        ),
      },
    );
    final MockClient client = MockClient((http.Request request) async {
      final Uri expected = Uri.parse(
        'https://store-fixture.invalid/hosted/groups/$groupId/apps/$appId/source',
      );
      if (request.method != 'GET' ||
          request.url != expected ||
          request.headers['authorization'] != 'Bearer store-fixture') {
        throw StateError(
          'Unexpected store screenshot request: '
          '${request.method} ${request.url} ${request.headers}',
        );
      }
      return http.Response.bytes(
        source.encode(),
        200,
        headers: <String, String>{
          'content-type': 'application/zip',
          'x-minapp-source-revision': '1',
          'x-minapp-source-sha256': List<String>.filled(64, 'a').join(),
        },
      );
    });
    final HostedAppManagementApi api = HostedAppManagementApi(
      baseUri: Uri.parse('https://store-fixture.invalid'),
      client: client,
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: KoboTheme.light(),
        debugShowCheckedModeBanner: false,
        home: KoboSourceEditorPage(
          api: api,
          accessToken: 'store-fixture',
          groupId: groupId,
          appId: appId,
          title: '町中華メモ',
          expectedRevision: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kobo-source-editor')), findsOneWidget);
    await binding.takeScreenshot('02-code-editor');
  });
}
