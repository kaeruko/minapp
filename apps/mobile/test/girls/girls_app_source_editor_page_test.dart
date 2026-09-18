import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/girls_app_management_api.dart';
import 'package:minapp_mobile/girls/girls_app_source_editor_page.dart';
import 'package:minapp_mobile/girls/girls_source_zip.dart';

const String _groupId = '0123456789abcdef0123456789abcdef';
const String _appId = 'abcdef0123456789abcdef0123456789';

void main() {
  testWidgets(
    'keyboard-visible source editor keeps a usable code viewport',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(411, 823));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final GirlsSourceArchive archive = GirlsSourceArchive.fromEntries(
        <String, Uint8List>{
          'index.html': Uint8List.fromList(
            utf8.encode(
              '<!doctype html><style>body { min-height: 100%; }</style>',
            ),
          ),
        },
      );
      final GirlsAppManagementApi api = GirlsAppManagementApi(
        baseUri: Uri.parse('https://example.com'),
        client: MockClient((http.Request request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/hosted/groups/$_groupId/apps/$_appId/source',
          );
          return http.Response.bytes(
            archive.encode(),
            200,
            headers: <String, String>{
              'content-type': 'application/zip',
              'x-minapp-source-revision': '1',
              'x-minapp-source-sha256': '0' * 64,
            },
          );
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        MaterialApp(
          builder: (BuildContext context, Widget? child) {
            final MediaQueryData media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                viewInsets: const EdgeInsets.only(bottom: 300),
              ),
              child: child!,
            );
          },
          home: GirlsAppSourceEditorPage(
            api: api,
            accessToken: 'test-token',
            groupId: _groupId,
            appId: _appId,
            title: 'みんあぷっち',
            expectedRevision: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder codeField = find.byKey(
        const Key('girls-source-editor-code'),
      );
      expect(codeField, findsOneWidget);
      expect(
        find.byKey(const Key('girls-source-editor-file-menu')),
        findsOneWidget,
      );
      expect(tester.getSize(codeField).height, greaterThan(80));
      expect(tester.takeException(), isNull);
    },
  );
}
