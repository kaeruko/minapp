import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/hosted_edition.dart';
import 'package:minapp_mobile/hosted_private_groups.dart';
import 'package:minapp_mobile/kobo/hosted_kobo_api.dart';

const String _token = 'access-token';
const String _privateGroupId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test('load requires the edition community and exposes only private groups',
      () async {
    final HostedKoboApi api = HostedKoboApi(
      baseUri: Uri.parse('https://kobo-api.example.com'),
      client: MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/hosted/groups');
        expect(request.headers['Authorization'], 'Bearer $_token');
        return _json(<String, Object?>{
          'groups': <Object?>[
            <String, Object?>{
              'group_id': HostedEditions.koboCommunityGroupId,
              'name': HostedEditions.koboCommunityGroupName,
              'role': 'member',
              'status': 'active',
            },
            <String, Object?>{
              'group_id': _privateGroupId,
              'name': '釣り仲間の工房',
              'role': 'owner',
              'status': 'active',
            },
          ],
        });
      }),
    );
    const AuthenticatedSession session = AuthenticatedSession(
      accessToken: _token,
      expiresIn: 3600,
    );

    final HostedPrivateGroupsSnapshot snapshot =
        await HostedPrivateGroupsService(api: api, session: session).load();

    expect(snapshot.community.groupId, HostedEditions.koboCommunityGroupId);
    expect(snapshot.privateGroups, hasLength(1));
    expect(snapshot.privateGroups.single.groupId, _privateGroupId);
  });

  test('create always issues the private group invitation ID', () async {
    int requestCount = 0;
    final HostedKoboApi api = HostedKoboApi(
      baseUri: Uri.parse('https://kobo-api.example.com'),
      client: MockClient((http.Request request) async {
        requestCount += 1;
        expect(request.headers['Authorization'], 'Bearer $_token');
        if (requestCount == 1) {
          expect(request.method, 'POST');
          expect(request.url.path, '/hosted/groups');
          expect(jsonDecode(request.body), <String, Object?>{
            'name': '釣り仲間の工房',
          });
          return _json(<String, Object?>{
            'group_id': _privateGroupId,
            'name': '釣り仲間の工房',
            'role': 'owner',
            'status': 'active',
            'visibility': 'private',
          }, statusCode: 201);
        }
        if (requestCount == 2) {
          expect(request.method, 'POST');
          expect(
            request.url.path,
            '/hosted/groups/$_privateGroupId/invite',
          );
          return _json(<String, Object?>{
            'group_id': _privateGroupId,
            'code': '2345-6789-ABCD',
            'expires_at': '2099-01-01T00:00:00Z',
            'valid_for_seconds': 604800,
          }, statusCode: 201);
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      }),
    );
    const AuthenticatedSession session = AuthenticatedSession(
      accessToken: _token,
      expiresIn: 3600,
    );

    final HostedPrivateGroupCreation creation =
        await HostedPrivateGroupsService(api: api, session: session)
            .create(name: '釣り仲間の工房');

    expect(creation.group.groupId, _privateGroupId);
    expect(creation.invite.code, '2345-6789-ABCD');
    expect(requestCount, 2);
  });

  test('create and join reject ambiguous whitespace before API access',
      () async {
    final HostedKoboApi api = HostedKoboApi(
      baseUri: Uri.parse('https://kobo-api.example.com'),
      client: MockClient((http.Request request) async {
        fail('Validation failure must not access the API: ${request.url}');
      }),
    );
    const AuthenticatedSession session = AuthenticatedSession(
      accessToken: _token,
      expiresIn: 3600,
    );
    final HostedPrivateGroupsService service =
        HostedPrivateGroupsService(api: api, session: session);

    await expectLater(
      service.create(name: ' 釣り仲間'),
      throwsArgumentError,
    );
    expect(
      () => service.join(code: ' 2345-6789-ABCD'),
      throwsArgumentError,
    );
  });
}

http.Response _json(Map<String, Object?> body, {int statusCode = 200}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}
