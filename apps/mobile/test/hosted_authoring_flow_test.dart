import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/hosted_authoring_bridge.dart';
import 'package:minapp_mobile/hosted_authoring_launch_client.dart';
import 'package:minapp_mobile/hosted_authoring_projects_api.dart';

const String _groupId = '22222222222222222222222222222222';
const String _contentId = '33333333333333333333333333333333';
const String _editorAppId = '44444444444444444444444444444444';
const String _publishedAppId = '55555555555555555555555555555555';
const String _playerAppId = '66666666666666666666666666666666';
const String _contentFormat = 'example/quiz@1';
const String _runtimeToken = 'RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR';
const String _authoringToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _contentToken = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';

http.Response _json(int status, Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

Map<String, Object?> _summary({required int revision}) => <String, Object?>{
      'content_id': _contentId,
      'group_id': _groupId,
      'content_format': _contentFormat,
      'status': 'draft',
      'draft_revision': revision,
      'assets': <Object?>[],
      'created_at': '2026-09-06T09:00:00Z',
      'updated_at': '2026-09-06T10:00:00Z',
    };

Map<String, Object?> _document({required int revision}) => <String, Object?>{
      'content_format': _contentFormat,
      'schema_version': 1,
      'content_revision': revision,
      'questions': <Object?>[
        <String, Object?>{
          'id': 'q1',
          'prompt': '2 + 2 = ?',
          'answer': '4',
        },
      ],
    };

Map<String, Object?> _project({required int revision}) => <String, Object?>{
      ..._summary(revision: revision),
      'document': _document(revision: revision),
    };

Map<String, Object?> _launch() => <String, Object?>{
      'content_path': '/hosted/authoring-editor/$_contentToken/index.html',
      'content_expires_in': 600,
      'runtime_token': _runtimeToken,
      'runtime_expires_in': 600,
      'authoring_token': _authoringToken,
      'authoring_expires_in': 600,
      'content_id': _contentId,
      'content_format': _contentFormat,
      'editor_app_id': _editorAppId,
      'allowed_operations': <Object?>[
        'load',
        'save_document',
        'get_asset',
        'save_asset',
        'delete_asset',
        'publish_request',
      ],
    };

Map<String, Object?> _published({required int revision}) => <String, Object?>{
      'content_id': _contentId,
      'group_id': _groupId,
      'content_format': _contentFormat,
      'published_version': 1,
      'source_revision': revision,
      'published_app_id': _publishedAppId,
      'player_app_id': _playerAppId,
      'player_source_version': 2,
      'assets': <Object?>[],
      'published_at': '2026-09-06T10:20:00Z',
    };

void main() {
  test('Hosted Authoring keeps JWT outside capability load/save/publish', () async {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);

      if (request.method == 'GET' &&
          request.url.path == '/hosted/authoring/groups/$_groupId/projects') {
        expect(request.url.queryParameters, <String, String>{
          'content_format': _contentFormat,
        });
        expect(request.headers['authorization'], 'Bearer owner-token');
        return _json(200, <String, Object?>{
          'projects': <Object?>[_summary(revision: 3)],
        });
      }

      if (request.method == 'GET' &&
          request.url.path == '/hosted/authoring/projects/$_contentId') {
        expect(request.headers['authorization'], 'Bearer owner-token');
        return _json(200, _project(revision: 3));
      }

      if (request.method == 'POST' &&
          request.url.path == '/hosted/authoring/projects/$_contentId/launch') {
        expect(request.headers['authorization'], 'Bearer owner-token');
        expect(
          jsonDecode(request.body),
          <String, Object?>{'editor_app_id': _editorAppId},
        );
        return _json(201, _launch());
      }

      if (request.method == 'GET' &&
          request.url.path == '/hosted/authoring/session/$_authoringToken') {
        expect(request.headers['authorization'], isNull);
        return _json(200, _project(revision: 3));
      }

      if (request.method == 'POST' &&
          request.url.path ==
              '/hosted/authoring/session/$_authoringToken/document') {
        expect(request.headers['authorization'], isNull);
        final Object? decoded = jsonDecode(request.body);
        expect(decoded, isA<Map<String, Object?>>());
        final Map<String, Object?> body = decoded! as Map<String, Object?>;
        expect(body.keys.toSet(), <String>{'expected_revision', 'document'});
        expect(body['expected_revision'], 3);
        final Map<String, Object?> savedDocument =
            body['document']! as Map<String, Object?>;
        expect(savedDocument['content_revision'], 4);
        return _json(200, _summary(revision: 4));
      }

      if (request.method == 'POST' &&
          request.url.path ==
              '/hosted/authoring/session/$_authoringToken/publish') {
        expect(request.headers['authorization'], isNull);
        expect(
          jsonDecode(request.body),
          <String, Object?>{'expected_revision': 4},
        );
        return _json(201, _published(revision: 4));
      }

      fail('Unexpected request: ${request.method} ${request.url}');
    });

    final HostedAuthoringProjectsApi projectsApi = HostedAuthoringProjectsApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );
    final HostedAuthoringLaunchApiClient launchApi =
        HostedAuthoringLaunchApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );
    final HostedAuthoringApiClient authoringApi = HostedAuthoringApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final List<HostedAuthoringProjectSummary> listed =
        await projectsApi.listProjects(
      accessToken: 'owner-token',
      groupId: _groupId,
      contentFormat: _contentFormat,
    );
    expect(listed.single.contentId, _contentId);
    expect(listed.single.draftRevision, 3);

    final HostedAuthoringProject loaded = await projectsApi.loadProject(
      accessToken: 'owner-token',
      contentId: _contentId,
    );
    expect(loaded.summary.contentFormat, _contentFormat);
    expect(loaded.document['content_format'], _contentFormat);

    final HostedAuthoringLaunchGrant launch = await launchApi.createLaunch(
      accessToken: 'owner-token',
      contentId: _contentId,
      editorAppId: _editorAppId,
    );
    expect(launch.contentFormat, _contentFormat);
    expect(launch.editorAppId, _editorAppId);
    expect(launch.allowedOperations, contains('publish_request'));

    final HostedAuthoringBridgeSession bridge = HostedAuthoringBridgeSession(
      transport: authoringApi,
      authoringToken: launch.authoringToken,
    );

    final Map<String, Object?> bridgeLoad = await bridge.handleMessage(
      jsonEncode(<String, Object?>{
        'version': 1,
        'id': 'load-1',
        'method': 'authoring.load',
      }),
    );
    expect(bridgeLoad['ok'], isTrue);

    final Map<String, Object?> bridgeSave = await bridge.handleMessage(
      jsonEncode(<String, Object?>{
        'version': 1,
        'id': 'save-1',
        'method': 'authoring.save',
        'expectedRevision': 3,
        'data': _document(revision: 4),
      }),
    );
    expect(bridgeSave['ok'], isTrue);

    final Map<String, Object?> bridgePublish = await bridge.handleMessage(
      jsonEncode(<String, Object?>{
        'version': 1,
        'id': 'publish-1',
        'method': 'authoring.publish',
        'expectedRevision': 4,
      }),
    );
    expect(bridgePublish['ok'], isTrue);
    final Map<String, Object?> result =
        bridgePublish['result']! as Map<String, Object?>;
    expect(result['published_app_id'], _publishedAppId);
    expect(result['player_app_id'], _playerAppId);

    expect(
      requests.map((http.Request request) => request.url.path).toList(),
      <String>[
        '/hosted/authoring/groups/$_groupId/projects',
        '/hosted/authoring/projects/$_contentId',
        '/hosted/authoring/projects/$_contentId/launch',
        '/hosted/authoring/session/$_authoringToken',
        '/hosted/authoring/session/$_authoringToken/document',
        '/hosted/authoring/session/$_authoringToken/publish',
      ],
    );
  });
}
