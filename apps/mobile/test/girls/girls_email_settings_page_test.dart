import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_email_settings_page.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

void main() {
  testWidgets('email settings completes confirmation-code linking', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int requestCount = 0;
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((http.Request request) async {
        requestCount += 1;
        expect(request.headers['Authorization'], 'Bearer test-token');
        switch (requestCount) {
          case 1:
            expect(request.method, 'GET');
            return _response(<String, Object?>{
              'email': null,
              'verified': false,
            });
          case 2:
            expect(request.method, 'POST');
            expect(
              jsonDecode(request.body),
              <String, Object?>{'email': 'honey@example.com'},
            );
            return _response(<String, Object?>{
              'email': 'honey@example.com',
              'verified': false,
              'code_sent': true,
              'destination': 'h***@example.com',
            });
          case 3:
            expect(request.method, 'POST');
            expect(
              jsonDecode(request.body),
              <String, Object?>{'code': '123456'},
            );
            return _response(<String, Object?>{
              'email': 'honey@example.com',
              'verified': true,
            });
          default:
            fail('Unexpected request #$requestCount');
        }
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GirlsEmailSettingsPage(
          api: api,
          session: const AuthenticatedSession(
            accessToken: 'test-token',
            expiresIn: 3600,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('まだ紐づけていません'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('girls-email-input')),
      'Honey@Example.com',
    );
    await tester.tap(find.byKey(const Key('girls-email-send-code')));
    await tester.pumpAndSettle();

    expect(find.text('h***@example.com に送信しました。'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('girls-email-code-input')),
      '123456',
    );
    await tester.ensureVisible(find.byKey(const Key('girls-email-verify')));
    await tester.tap(find.byKey(const Key('girls-email-verify')));
    await tester.pumpAndSettle();

    expect(find.text('紐づけ済み'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('girls-email-status')),
        matching: find.text('honey@example.com'),
      ),
      findsOneWidget,
    );
    expect(find.text('メールアドレスを紐づけました♡'), findsOneWidget);
    expect(requestCount, 3);
    expect(tester.takeException(), isNull);
  });
}

http.Response _response(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}
