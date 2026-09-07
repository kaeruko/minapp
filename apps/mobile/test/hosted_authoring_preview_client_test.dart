import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/hosted_authoring_preview_client.dart';

const String _contentId = '33333333333333333333333333333333';
const String _playerAppId = '55555555555555555555555555555555';
const String _runtimeToken = 'RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR';
const String _contentToken = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';

http.Response _json(int status, Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

Map<String, Object?> _payload() => <String, Object?>{
      'content_id': _contentId,
      'content_format': 'minapp/novel@1',
      'draft_revision': 7,
      'player_app_id': _playerAppId,
      'content_path': '/hosted/authoring-preview/$_contentToken/index.html',
      'expires_in': 600,
      'runtime_token': _runtimeToken,
      'runtime_expires_in': 600,
    };

void main() {
  test('preview is JWT-authenticated and pins player plus draft revision', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
      return _json(201, _payload());
    });
    final HostedAuthoringPreviewApiClient api = HostedAuthoringPreviewApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final HostedAuthoringPreviewGrant grant = await api.createPreview(
      accessToken: 'owner-token',
      contentId: _contentId,
      playerAppId: _playerAppId,
      expectedRevision: 7,
    );

    expect(captured.method, 'POST');
    expect(
      captured.url.path,
      '/hosted/authoring/projects/$_contentId/preview',
    );
    expect(captured.headers['authorization'], 'Bearer owner-token');
    expect(
      jsonDecode(captured.body),
      <String, Object?>{
        'player_app_id': _playerAppId,
        'expected_revision': 7,
      },
    );
    expect(grant.contentId, _contentId);
    expect(grant.playerAppId, _playerAppId);
    expect(grant.draftRevision, 7);
    expect(grant.contentFormat, 'minapp/novel@1');
    expect(
      grant.contentUri,
      Uri.parse(
        'https://hosted.example.test/hosted/authoring-preview/$_contentToken/index.html',
      ),
    );
    expect(grant.runtimeToken, _runtimeToken);
  });

  test('preview response cannot silently change player or draft revision', () async {
    final MockClient client = MockClient((http.Request request) async {
      final Map<String, Object?> payload = _payload();
      payload['draft_revision'] = 8;
      return _json(201, payload);
    });
    final HostedAuthoringPreviewApiClient api = HostedAuthoringPreviewApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.createPreview(
        accessToken: 'owner-token',
        contentId: _contentId,
        playerAppId: _playerAppId,
        expectedRevision: 7,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('preview response rejects non-preview content path', () async {
    final MockClient client = MockClient((http.Request request) async {
      final Map<String, Object?> payload = _payload();
      payload['content_path'] = '/hosted/authoring-editor/$_contentToken/index.html';
      return _json(201, payload);
    });
    final HostedAuthoringPreviewApiClient api = HostedAuthoringPreviewApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.createPreview(
        accessToken: 'owner-token',
        contentId: _contentId,
        playerAppId: _playerAppId,
        expectedRevision: 7,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('preview response rejects unexpected identity fields', () async {
    final MockClient client = MockClient((http.Request request) async {
      final Map<String, Object?> payload = _payload();
      payload['user_id'] = 'never-child-controlled';
      return _json(201, payload);
    });
    final HostedAuthoringPreviewApiClient api = HostedAuthoringPreviewApiClient(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.createPreview(
        accessToken: 'owner-token',
        contentId: _contentId,
        playerAppId: _playerAppId,
        expectedRevision: 7,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
