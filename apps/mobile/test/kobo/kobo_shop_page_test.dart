import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/hosted_app_webview.dart';
import 'package:minapp_mobile/hosted_consumer_api.dart';
import 'package:minapp_mobile/hosted_edition.dart';
import 'package:minapp_mobile/kobo/kobo_shop_page.dart';

const String _appId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _ownerId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, Object?> _catalog(int version) => <String, Object?>{
      'apps': <Object?>[
        <String, Object?>{
          'app_id': _appId,
          'version': '$version',
          'title': '町中華メモ',
          'owner_user_id': _ownerId,
          'owner_display_name': '作者',
          'published_at': '2026-11-05T02:00:00Z',
          'sha256': List<String>.filled(64, version == 2 ? 'c' : 'd').join(),
          'thumbnail_path': null,
        },
      ],
    };

void main() {
  testWidgets('stale guest play refreshes catalog and refuses the old URL',
      (WidgetTester tester) async {
    int catalogReads = 0;
    final MockClient client = MockClient((http.Request request) async {
      if (request.method != 'GET' || request.url.path != '/shop/apps' ||
          request.headers.containsKey('authorization')) {
        throw StateError('Unexpected shop request: $request');
      }
      catalogReads += 1;
      return http.Response(
        jsonEncode(_catalog(catalogReads == 1 ? 2 : 3)),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final HostedConsumerApi api = HostedConsumerApi(
      baseUri: Uri.parse('https://kobo.example.com'),
      edition: HostedEditions.kobo,
      client: client,
    );
    await tester.pumpWidget(MaterialApp(
      home: KoboShopPage(
        api: api,
        session: null,
        onNavigationSelected: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(catalogReads, 1);

    await tester.tap(find.byKey(const Key('kobo-shop-play-$_appId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(catalogReads, 2, reason: 'play must revalidate the catalog');
    expect(find.textContaining('作品が更新されました'), findsOneWidget);
    expect(find.byType(HostedAppWebViewPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
