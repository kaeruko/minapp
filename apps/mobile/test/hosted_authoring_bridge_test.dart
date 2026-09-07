import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/hosted_authoring_bridge.dart';

const String _contentId = '33333333333333333333333333333333';
const String _editorAppId = '44444444444444444444444444444444';
const String _publishedAppId = '55555555555555555555555555555555';
const String _playerAppId = '66666666666666666666666666666666';
const String _groupId = '22222222222222222222222222222222';
const String _token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

http.Response _json(int status, Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

Map<String, Object?> _project({required int revision, bool document = false}) =>
    <String, Object?>{
      'content_id': _contentId,
      'group_id': _groupId,
      'content_format': 'minapp/novel@1',
      'status': 'draft',
      'draft_revision': revision,
      'assets': <Object?>[],
      'created_at': '2026-09-06T09:00:00Z',
      'updated_at': '2026-09-06T09:10:00Z',
      if (document) 'document': <String, Object?>{'version': 1},
    };

Map<String, Object?> _published({required int revision}) => <String, Object?>{
      'content_id': _contentId,
      'group_id': _groupId,
      'content_format': 'minapp/novel@1',
      'published_version': 1,
      'source_revision': revision,
      'published_app_id': _publishedAppId,
      'player_app_id': _playerAppId,
      'player_source_version': 4,
      'assets': <Object?>[],
      'published_at': '2026-09-06T10:20:00Z',
    };

class FakeAuthoringTransport implements HostedAuthoringTransport {
  final List<String> calls = <String>[];

  @override
  Future<Map<String, Object?>> loadProject(String authoringToken) async {
    calls.add('load:$authoringToken');
    return _project(revision: 7, document: true);
  }

  @override
  Future<Map<String, Object?>> saveDocument(
    String authoringToken, {
    required int expectedRevision,
    required Map<String, Object?> document,
  }) async {
    calls.add('save:$authoringToken:$expectedRevision:${document['version']}');
    return _project(revision: expectedRevision + 1);
  }

  @override
  Future<Map<String, Object?>> publishProject(
    String authoringToken, {
    required int expectedRevision,
  }) async {
    calls.add('publish:$authoringToken:$expectedRevision');
    return _published(revision: expectedRevision);
  }
}

void main() {
  test('session mint is JWT-authenticated and capability calls carry no content id', () async {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      if (request.url.path == '/hosted/authoring/projects/$_contentId/session') {
        expect(request.headers['authorization'], 'Bearer owner-token');
        expect(jsonDecode(request.body), <String, Object?>{'editor_app_id': _editorAppId});
        return _json(201, <String, Object?>{
          'token': _token,
          'expires_in': 600,
          'content_id': _contentId,
          'content_format': 'minapp/novel@1',
          'editor_app_id': _editorAppId,
          'allowed_operations': <Object?>[
            'load',
            'save_document',
            'get_asset',
            'save_asset',
            'delete_asset',
            'publish_request',
          ],
        });
      }
      if (request.url.path == '/hosted/authoring/session/$_token') {
        expect(request.headers['authorization'], isNull);
        return _json(200, _project(revision: 7, document: true));
      }
      if (request.url.path == '/hosted/authoring/session/$_token/document') {
        expect(request.headers['authorization'], isNull);
        expect(
          jsonDecode(request.body),
          <String, Object?>{
            'expected_revision': 7,
            'document': <String, Object?>{'version': 1, 'start': 'end'},
          },
        );
        return _json(200, _project(revision: 8));
      }
      if (request.url.path == '/hosted/authoring/session/$_token/publish') {
        expect(request.headers['authorization'], isNull);
        expect(jsonDecode(request.body), <String, Object?>{'expected_revision': 8});
        return _json(201, _published(revision: 8));
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    final HostedAuthoringApiClient api = HostedAuthoringApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final HostedAuthoringGrant grant = await api.createSession(
      accessToken: 'owner-token',
      contentId: _contentId,
      editorAppId: _editorAppId,
    );
    final Map<String, Object?> loaded = await api.loadProject(grant.token);
    final Map<String, Object?> saved = await api.saveDocument(
      grant.token,
      expectedRevision: 7,
      document: <String, Object?>{'version': 1, 'start': 'end'},
    );
    final Map<String, Object?> published = await api.publishProject(
      grant.token,
      expectedRevision: 8,
    );

    expect(grant.contentId, _contentId);
    expect(grant.editorAppId, _editorAppId);
    expect(grant.allowedOperations, contains('publish_request'));
    expect(loaded['draft_revision'], 7);
    expect(saved['draft_revision'], 8);
    expect(published['source_revision'], 8);
    expect(published['published_app_id'], _publishedAppId);
    expect(published['player_app_id'], _playerAppId);
    expect(published['player_source_version'], 4);
    expect(
      requests.map((http.Request request) => request.url.path).toList(),
      <String>[
        '/hosted/authoring/projects/$_contentId/session',
        '/hosted/authoring/session/$_token',
        '/hosted/authoring/session/$_token/document',
        '/hosted/authoring/session/$_token/publish',
      ],
    );
  });

  test('publish response rejects invalid normal app identity', () async {
    final MockClient client = MockClient((http.Request request) async {
      final Map<String, Object?> response = _published(revision: 8);
      response['published_app_id'] = 'not-an-id';
      return _json(201, response);
    });
    final HostedAuthoringApiClient api = HostedAuthoringApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.publishProject(_token, expectedRevision: 8),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('session response cannot silently change content or editor scope', () async {
    final MockClient client = MockClient((http.Request request) async => _json(
          201,
          <String, Object?>{
            'token': _token,
            'expires_in': 600,
            'content_id': '5' * 32,
            'content_format': 'minapp/novel@1',
            'editor_app_id': _editorAppId,
            'allowed_operations': <Object?>['load'],
          },
        ));
    final HostedAuthoringApiClient api = HostedAuthoringApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.createSession(
        accessToken: 'owner-token',
        contentId: _contentId,
        editorAppId: _editorAppId,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('bridge load save and publish always use the bound authoring token', () async {
    final FakeAuthoringTransport transport = FakeAuthoringTransport();
    final HostedAuthoringBridgeSession bridge = HostedAuthoringBridgeSession(
      transport: transport,
      authoringToken: _token,
    );

    final Map<String, Object?> load = await bridge.handleMessage(
      jsonEncode(<String, Object?>{
        'version': 1,
        'id': '1',
        'method': 'authoring.load',
      }),
    );
    final Map<String, Object?> save = await bridge.handleMessage(
      jsonEncode(<String, Object?>{
        'version': 1,
        'id': '2',
        'method': 'authoring.save',
        'expectedRevision': 7,
        'data': <String, Object?>{'version': 1},
      }),
    );
    final Map<String, Object?> publish = await bridge.handleMessage(
      jsonEncode(<String, Object?>{
        'version': 1,
        'id': '3',
        'method': 'authoring.publish',
        'expectedRevision': 8,
      }),
    );

    expect(load['ok'], isTrue);
    expect(save['ok'], isTrue);
    expect(publish['ok'], isTrue);
    expect(
      transport.calls,
      <String>[
        'load:$_token',
        'save:$_token:7:1',
        'publish:$_token:8',
      ],
    );
  });

  test('publish rejects identity scope and data fields instead of ignoring them', () async {
    final FakeAuthoringTransport transport = FakeAuthoringTransport();
    final HostedAuthoringBridgeSession bridge = HostedAuthoringBridgeSession(
      transport: transport,
      authoringToken: _token,
    );

    final Map<String, Object?> response = await bridge.handleMessage(
      jsonEncode(<String, Object?>{
        'version': 1,
        'id': 'publish-scope',
        'method': 'authoring.publish',
        'expectedRevision': 8,
        'contentId': _contentId,
      }),
    );

    expect(response['ok'], isFalse);
    final Map<String, Object?> error = response['error']! as Map<String, Object?>;
    expect(error['code'], 'invalid_authoring_bridge_request');
    expect(transport.calls, isEmpty);
  });

  test('bridge rejects identity and scope fields instead of ignoring them', () async {
    final FakeAuthoringTransport transport = FakeAuthoringTransport();
    final HostedAuthoringBridgeSession bridge = HostedAuthoringBridgeSession(
      transport: transport,
      authoringToken: _token,
    );

    final Map<String, Object?> response = await bridge.handleMessage(
      jsonEncode(<String, Object?>{
        'version': 1,
        'id': 'scope',
        'method': 'authoring.load',
        'contentId': _contentId,
      }),
    );

    expect(response['ok'], isFalse);
    final Map<String, Object?> error = response['error']! as Map<String, Object?>;
    expect(error['code'], 'invalid_authoring_bridge_request');
    expect(transport.calls, isEmpty);
  });

  test('bootstrap exposes minapp.authoring without embedding credentials or token', () {
    final String script = HostedAuthoringBridgeProtocol.bootstrapJavaScript;
    expect(script, contains('authoring.load'));
    expect(script, contains('authoring.save'));
    expect(script, contains('authoring.publish'));
    expect(script, contains('Object.assign({}, current, { authoring })'));
    expect(script, isNot(contains(_token)));
    expect(script.toLowerCase(), isNot(contains('cognito')));
    expect(script.toLowerCase(), isNot(contains('authorization')));
  });
}
