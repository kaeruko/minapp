import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/hosted_authoring_launch_client.dart';

const String _contentId = '33333333333333333333333333333333';
const String _editorAppId = '44444444444444444444444444444444';
const String _runtimeToken = 'RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR';
const String _authoringToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _contentToken = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';

http.Response _json(int status, Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

Map<String, Object?> _launchPayload() => <String, Object?>{
      'content_path': '/hosted/authoring-editor/$_contentToken/index.html',
      'content_expires_in': 600,
      'runtime_token': _runtimeToken,
      'runtime_expires_in': 600,
      'authoring_token': _authoringToken,
      'authoring_expires_in': 600,
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
    };

void main() {
  test('launch is JWT-authenticated and returns all three bound capabilities', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
      return _json(201, _launchPayload());
    });
    final HostedAuthoringLaunchApiClient api = HostedAuthoringLaunchApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final HostedAuthoringLaunchGrant grant = await api.createLaunch(
      accessToken: 'owner-token',
      contentId: _contentId,
      editorAppId: _editorAppId,
    );

    expect(captured.method, 'POST');
    expect(
      captured.url.path,
      '/hosted/authoring/projects/$_contentId/launch',
    );
    expect(captured.headers['authorization'], 'Bearer owner-token');
    expect(
      jsonDecode(captured.body),
      <String, Object?>{'editor_app_id': _editorAppId},
    );
    expect(
      grant.contentUri,
      Uri.parse(
        'https://hosted.example.test/hosted/authoring-editor/$_contentToken/index.html',
      ),
    );
    expect(grant.runtimeToken, _runtimeToken);
    expect(grant.authoringToken, _authoringToken);
    expect(grant.contentId, _contentId);
    expect(grant.editorAppId, _editorAppId);
    expect(grant.contentFormat, 'minapp/novel@1');
    expect(grant.allowedOperations, contains('publish_request'));
  });

  test('launch response cannot silently change requested content scope', () async {
    final MockClient client = MockClient((http.Request request) async {
      final Map<String, Object?> payload = _launchPayload();
      payload['content_id'] = '5' * 32;
      return _json(201, payload);
    });
    final HostedAuthoringLaunchApiClient api = HostedAuthoringLaunchApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.createLaunch(
        accessToken: 'owner-token',
        contentId: _contentId,
        editorAppId: _editorAppId,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('launch response rejects a content path outside Authoring Editor scope', () async {
    final MockClient client = MockClient((http.Request request) async {
      final Map<String, Object?> payload = _launchPayload();
      payload['content_path'] = '/hosted/preview/$_contentToken/index.html';
      return _json(201, payload);
    });
    final HostedAuthoringLaunchApiClient api = HostedAuthoringLaunchApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.createLaunch(
        accessToken: 'owner-token',
        contentId: _contentId,
        editorAppId: _editorAppId,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('launch response rejects unexpected fields instead of ignoring them', () async {
    final MockClient client = MockClient((http.Request request) async {
      final Map<String, Object?> payload = _launchPayload();
      payload['user_id'] = 'should-never-be-child-controlled';
      return _json(201, payload);
    });
    final HostedAuthoringLaunchApiClient api = HostedAuthoringLaunchApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.createLaunch(
        accessToken: 'owner-token',
        contentId: _contentId,
        editorAppId: _editorAppId,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
