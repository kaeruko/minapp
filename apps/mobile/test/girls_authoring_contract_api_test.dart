import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/girls_authoring_contract_api.dart';

void main() {
  final Uri baseUri = Uri.parse('https://girls-api.example.com');
  const String token = 'access-token';
  const String groupId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('lists generic editor and player contracts with bearer auth', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(
        request.url,
        Uri.parse(
          'https://girls-api.example.com/hosted/authoring/groups/$groupId/apps',
        ),
      );
      expect(request.headers['Authorization'], 'Bearer $token');
      return http.Response(
        jsonEncode(<String, Object?>{
          'apps': <Object?>[
            <String, Object?>{
              'app_id': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              'group_id': groupId,
              'title': 'Quiz Editor',
              'edits': <String>['example/quiz@1'],
              'accepts': <String>[],
            },
            <String, Object?>{
              'app_id': 'cccccccccccccccccccccccccccccccc',
              'group_id': groupId,
              'title': 'Quiz Player',
              'edits': <String>[],
              'accepts': <String>['example/quiz@1'],
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final GirlsAuthoringContractApi api =
        GirlsAuthoringContractApi(baseUri: baseUri, client: client);
    final List<GirlsAuthoringAppContract> apps = await api.listApps(
      accessToken: token,
      groupId: groupId,
    );

    expect(apps, hasLength(2));
    expect(apps.first.edits, <String>['example/quiz@1']);
    expect(apps.first.accepts, isEmpty);
    expect(apps.last.edits, isEmpty);
    expect(apps.last.accepts, <String>['example/quiz@1']);
  });

  test('rejects duplicate app ids instead of choosing one', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'apps': <Object?>[
            _app('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', groupId),
            _app('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', groupId),
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final GirlsAuthoringContractApi api =
        GirlsAuthoringContractApi(baseUri: baseUri, client: client);

    expect(
      () => api.listApps(accessToken: token, groupId: groupId),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects invalid content formats from server', () async {
    final MockClient client = MockClient((http.Request request) async {
      final Map<String, Object?> app = _app(
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        groupId,
      );
      app['edits'] = <String>['quiz-v1'];
      return http.Response(
        jsonEncode(<String, Object?>{'apps': <Object?>[app]}),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final GirlsAuthoringContractApi api =
        GirlsAuthoringContractApi(baseUri: baseUri, client: client);

    expect(
      () => api.listApps(accessToken: token, groupId: groupId),
      throwsA(isA<FormatException>()),
    );
  });
}

Map<String, Object?> _app(String appId, String groupId) => <String, Object?>{
      'app_id': appId,
      'group_id': groupId,
      'title': 'Quiz Editor',
      'edits': <String>['example/quiz@1'],
      'accepts': <String>[],
    };
