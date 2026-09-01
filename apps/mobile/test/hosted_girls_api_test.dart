import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/hosted_girls_api.dart';

void main() {
  final Uri baseUri = Uri.parse('https://girls-api.example.com');
  const String token = 'access-token';
  const String groupId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('listGroups uses Hosted groups endpoint with bearer auth', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url, Uri.parse('https://girls-api.example.com/hosted/groups'));
      expect(request.headers['Authorization'], 'Bearer $token');
      return _jsonResponse(<String, Object?>{
        'groups': <Object?>[
          <String, Object?>{
            'group_id': groupId,
            'name': '放課後イラスト部',
            'role': 'owner',
            'status': 'active',
          },
        ],
      });
    });

    final HostedGirlsApi api = HostedGirlsApi(baseUri: baseUri, client: client);
    final List<HostedGroup> groups = await api.listGroups(token);

    expect(groups, hasLength(1));
    expect(groups.single.groupId, groupId);
    expect(groups.single.name, '放課後イラスト部');
    expect(groups.single.isOwner, isTrue);
  });

  test('joinGroup sends the user-facing group ID as invite code', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url, Uri.parse('https://girls-api.example.com/hosted/groups/join'));
      expect(request.headers['Authorization'], 'Bearer $token');
      expect(
        jsonDecode(request.body),
        <String, Object?>{'code': '2345-6789-ABCD'},
      );
      return _jsonResponse(<String, Object?>{
        'group_id': groupId,
        'name': 'なかよし創作部',
        'role': 'member',
        'status': 'active',
      }, statusCode: 201);
    });

    final HostedGirlsApi api = HostedGirlsApi(baseUri: baseUri, client: client);
    final HostedGroup group = await api.joinGroup(
      accessToken: token,
      code: '2345-6789-abcd',
    );

    expect(group.groupId, groupId);
    expect(group.name, 'なかよし創作部');
    expect(group.isOwner, isFalse);
  });

  test('createGroup followed by createInvite preserves backend semantics', () async {
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      expect(request.headers['Authorization'], 'Bearer $token');
      if (requestCount == 1) {
        expect(request.method, 'POST');
        expect(request.url, Uri.parse('https://girls-api.example.com/hosted/groups'));
        expect(jsonDecode(request.body), <String, Object?>{'name': '夜ふかし創作部'});
        return _jsonResponse(<String, Object?>{
          'group_id': groupId,
          'name': '夜ふかし創作部',
          'role': 'owner',
          'status': 'active',
          'visibility': 'private',
        }, statusCode: 201);
      }
      if (requestCount == 2) {
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.parse('https://girls-api.example.com/hosted/groups/$groupId/invite'),
        );
        expect(jsonDecode(request.body), <String, Object?>{});
        return _jsonResponse(<String, Object?>{
          'group_id': groupId,
          'code': '2345-6789-ABCD',
          'expires_at': '2026-09-08T00:00:00Z',
          'valid_for_seconds': 604800,
        }, statusCode: 201);
      }
      fail('Unexpected request #$requestCount: ${request.method} ${request.url}');
    });

    final HostedGirlsApi api = HostedGirlsApi(baseUri: baseUri, client: client);
    final HostedGroup group = await api.createGroup(
      accessToken: token,
      name: '夜ふかし創作部',
    );
    final HostedInvite invite = await api.createInvite(
      accessToken: token,
      groupId: group.groupId,
    );

    expect(group.isOwner, isTrue);
    expect(invite.groupId, groupId);
    expect(invite.code, '2345-6789-ABCD');
    expect(invite.validForSeconds, 604800);
    expect(requestCount, 2);
  });

  test('registration uses legal versions returned by Hosted legal endpoint', () async {
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      if (requestCount == 1) {
        expect(request.method, 'GET');
        expect(request.url, Uri.parse('https://girls-api.example.com/hosted/legal'));
        return _jsonResponse(<String, Object?>{
          'effective_date': '2026-08-28',
          'support_email': 'mail@example.com',
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
        });
      }
      if (requestCount == 2) {
        expect(request.method, 'POST');
        expect(request.url, Uri.parse('https://girls-api.example.com/hosted/register'));
        expect(
          jsonDecode(request.body),
          <String, Object?>{
            'login_id': 'honey',
            'password': 'secret12',
            'terms_version': 'terms-v1',
            'privacy_version': 'privacy-v1',
            'terms_accepted': true,
            'privacy_accepted': true,
          },
        );
        return _jsonResponse(<String, Object?>{
          'user_id': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          'login_id': 'honey',
          'role': 'user',
          'status': 'active',
          'recovery_code': 'RECOVERY-CODE-EXAMPLE-123',
          'legal': <String, Object?>{
            'terms_version': 'terms-v1',
            'privacy_version': 'privacy-v1',
            'accepted_at': '2026-09-01T00:00:00Z',
          },
        }, statusCode: 201);
      }
      fail('Unexpected request #$requestCount: ${request.method} ${request.url}');
    });

    final HostedGirlsApi api = HostedGirlsApi(baseUri: baseUri, client: client);
    final HostedLegalBundle legal = await api.fetchLegal();
    final HostedRegistrationResult result = await api.register(
      loginId: 'honey',
      password: 'secret12',
      legal: legal,
    );

    expect(result.loginId, 'honey');
    expect(result.recoveryCode, 'RECOVERY-CODE-EXAMPLE-123');
    expect(requestCount, 2);
  });

  test('invalid group ID fails before making a network request', () async {
    final MockClient client = MockClient((http.Request request) async {
      fail('Network request must not be made for an invalid group ID.');
    });
    final HostedGirlsApi api = HostedGirlsApi(baseUri: baseUri, client: client);

    expect(
      () => api.joinGroup(accessToken: token, code: 'INVALID'),
      throwsArgumentError,
    );
  });
}

http.Response _jsonResponse(
  Map<String, Object?> body, {
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json; charset=utf-8'},
  );
}
