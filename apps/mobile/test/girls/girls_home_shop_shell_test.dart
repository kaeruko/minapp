import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_home_shop_shell.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

HostedGirlsApi _fakeApi() {
  return HostedGirlsApi(
    baseUri: Uri.parse('https://example.com'),
    client: MockClient((http.Request request) async {
      if (request.url.path == '/shop/apps') {
        return http.Response(
          jsonEncode(<String, Object?>{'apps': <Object?>[]}),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      if (request.url.path == '/hosted/groups') {
        return http.Response(
          jsonEncode(<String, Object?>{'groups': <Object?>[]}),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      return http.Response(
        jsonEncode(<String, Object?>{}),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    }),
  );
}

void main() {
  testWidgets('authenticated Girls routes keep one common header and footer', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GirlsHomeShopShell(
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

    expect(find.byKey(const Key('girls-common-header')), findsOneWidget);
    expect(find.byKey(const Key('girls-header-logo')), findsOneWidget);
    expect(find.byKey(const Key('girls-shell-settings')), findsOneWidget);
    expect(find.byKey(const Key('girls-shell-profile')), findsOneWidget);
    expect(find.byKey(const Key('girls-footer-home')), findsOneWidget);
    expect(find.byKey(const Key('girls-footer-shop')), findsOneWidget);
    expect(find.text('ビルトインアプリ'), findsOneWidget);

    await tester.tap(find.byKey(const Key('girls-footer-shop')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('girls-common-header')), findsOneWidget);
    expect(find.byKey(const Key('girls-header-logo')), findsOneWidget);
    expect(find.byKey(const Key('girls-footer-shop')), findsOneWidget);
    expect(find.text('みんアプGirls ショップ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('girls-footer-home')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('girls-common-header')), findsOneWidget);
    expect(find.byKey(const Key('girls-footer-home')), findsOneWidget);
    expect(find.text('ビルトインアプリ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
