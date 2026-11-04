import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/hosted_profile_api.dart';

void main() {
  const String userId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('fetch requires and parses the exact profile contract', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/hosted/me/display-name');
      expect(request.headers['authorization'], 'Bearer access-token');
      return http.Response(
        jsonEncode(<String, Object?>{
          'user_id': userId,
          'login_id': 'oyaji',
          'role': 'user',
          'display_name': '工房の親方',
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final HostedProfileApi api = HostedProfileApi(
      baseUri: Uri.parse('https://api.example.com'),
      client: client,
    );

    final HostedProfile profile = await api.fetch('access-token');

    expect(profile.userId, userId);
    expect(profile.loginId, 'oyaji');
    expect(profile.displayName, '工房の親方');
  });

  test('update sends only the validated display name', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/hosted/me/display-name');
      expect(jsonDecode(request.body), <String, Object?>{
        'display_name': '晩酌部長',
      });
      return http.Response(
        jsonEncode(<String, Object?>{
          'user_id': userId,
          'login_id': 'oyaji',
          'role': 'user',
          'display_name': '晩酌部長',
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final HostedProfileApi api = HostedProfileApi(
      baseUri: Uri.parse('https://api.example.com'),
      client: client,
    );

    final HostedProfile profile = await api.updateDisplayName(
      accessToken: 'access-token',
      displayName: '晩酌部長',
    );

    expect(profile.displayName, '晩酌部長');
  });

  test('unexpected response fields fail fast', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'user_id': userId,
          'login_id': 'oyaji',
          'role': 'user',
          'display_name': null,
          'unexpected': true,
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final HostedProfileApi api = HostedProfileApi(
      baseUri: Uri.parse('https://api.example.com'),
      client: client,
    );

    await expectLater(
      api.fetch('access-token'),
      throwsA(isA<FormatException>()),
    );
  });
}
