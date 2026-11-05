import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/hosted_edition.dart';
import 'package:minapp_mobile/kobo/hosted_kobo_api.dart';
import 'package:minapp_mobile/kobo/kobo_groups_page.dart';
import 'package:minapp_mobile/kobo/kobo_theme.dart';

void main() {
  testWidgets('Kobo keeps its community implicit and private groups optional',
      (WidgetTester tester) async {
    final HostedKoboApi api = HostedKoboApi(
      baseUri: Uri.parse('https://kobo-api.example.com'),
      client: MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/hosted/groups');
        return http.Response(
          jsonEncode(<String, Object?>{
            'groups': <Object?>[
              <String, Object?>{
                'group_id': HostedEditions.koboCommunityGroupId,
                'name': HostedEditions.koboCommunityGroupName,
                'role': 'member',
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

    await tester.pumpWidget(
      MaterialApp(
        theme: KoboTheme.light(),
        home: KoboGroupsPage(
          api: api,
          session: const AuthenticatedSession(
            accessToken: 'access-token',
            expiresIn: 3600,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('非公開グループ'), findsOneWidget);
    expect(find.textContaining('みんなの工房'), findsOneWidget);
    expect(find.text('参加中の非公開グループ'), findsOneWidget);
    expect(find.textContaining('まだ参加していません'), findsOneWidget);
    expect(find.text(HostedEditions.koboCommunityGroupName), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
