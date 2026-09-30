import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/girls_app.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

void main() {
  testWidgets('Girls PNG login art assets render', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Image(
                image: AssetImage(
                  'assets/girls/generated/minapp_girls_logo.png',
                ),
                width: 150,
                fit: BoxFit.contain,
              ),
              Image(
                image: AssetImage(
                  'assets/girls/generated/bg_pastel_pattern.png',
                ),
                width: 360,
                height: 220,
                fit: BoxFit.cover,
              ),
              Image(
                image: AssetImage(
                  'assets/girls/generated/border_lace_heart.png',
                ),
                width: 360,
                fit: BoxFit.fitWidth,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  for (final double width in <double>[320, 390]) {
    testWidgets('login places shared lace, logo and title in order at $width',
        (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final MockClient client = _legalClient();
      addTearDown(client.close);
      await tester.pumpWidget(GirlsApp(
        api: HostedGirlsApi(
          baseUri: Uri.parse('https://girls-api.example.com'),
          client: client,
        ),
      ));
      await tester.pumpAndSettle();

      final Rect header =
          tester.getRect(find.byKey(const Key('girls-common-header')));
      final Rect lace =
          tester.getRect(find.byKey(const Key('girls-header-lace')));
      final Rect logo =
          tester.getRect(find.byKey(const Key('girls-header-logo')));
      final Rect title =
          tester.getRect(find.byKey(const Key('girls-page-title')));
      final Rect character = tester.getRect(find.byWidgetPredicate(
        (Widget widget) =>
            widget is Image && widget.semanticLabel == 'みんアプ Girls のキャラクター',
      ));
      expect(header.top, 0);
      expect(lace.top, 0);
      expect(lace.bottom, lessThan(90));
      expect(logo.top, greaterThanOrEqualTo(lace.bottom));
      expect(title.top, greaterThanOrEqualTo(logo.bottom));
      expect(character.top, greaterThanOrEqualTo(title.bottom));
      expect(
        tester.widget<Text>(find.byKey(const Key('girls-page-title'))).data,
        'ログイン',
      );
      // The old login artwork is now used only for the lower lace edge.
      expect(find.byKey(const Key('girls-login-hero-lace')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('auth title switches between login and registration',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.reset);
    final MockClient client = _legalClient();
    addTearDown(client.close);
    await tester.pumpWidget(GirlsApp(
      api: HostedGirlsApi(
        baseUri: Uri.parse('https://girls-api.example.com'),
        client: client,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('新規登録はこちら'));
    await tester.tap(find.text('新規登録はこちら'));
    await tester.pumpAndSettle();
    expect(find.text('新規登録'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('girls-page-title'))).data,
      '新規登録',
    );
    expect(find.byKey(const Key('girls-password-confirm')), findsOneWidget);

    await tester.ensureVisible(find.text('ログインに戻る'));
    await tester.tap(find.text('ログインに戻る'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('girls-page-title'))).data,
      'ログイン',
    );
    expect(find.byKey(const Key('girls-password-confirm')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

MockClient _legalClient() {
  return MockClient((http.Request request) async {
    expect(request.url.path, '/hosted/legal');
    return http.Response(
      jsonEncode(<String, Object?>{
        'effective_date': '2026-09-01',
        'support_email': 'support@example.com',
        'terms': <String, Object?>{
          'version': 'terms-v1',
          'title': '利用規約',
          'body': '規約本文',
        },
        'privacy': <String, Object?>{
          'version': 'privacy-v1',
          'title': 'プライバシーポリシー',
          'body': 'プライバシー本文',
        },
      }),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });
}
