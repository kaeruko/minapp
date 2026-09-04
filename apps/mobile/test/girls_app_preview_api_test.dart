import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/girls_app_preview_api.dart';

const String _groupId = '22222222222222222222222222222222';
const String _appId = '33333333333333333333333333333333';
const String _contentToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _previewToken = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
const String _runtimeToken = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

http.Response _json(int status, Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

void main() {
  test('published self-test uses published-session and does not call launch-session', () async {
    final List<String> paths = <String>[];
    final MockClient client = MockClient((http.Request request) async {
      paths.add(request.url.path);
      expect(request.method, 'POST');
      expect(request.headers['authorization'], 'Bearer owner-token');
      expect(request.body, '{}');
      if (request.url.path.endsWith('/published-session')) {
        return _json(201, <String, Object?>{
          'content_path': '/hosted/content/$_contentToken/index.html',
          'published_version': 4,
          'expires_in': 600,
        });
      }
      if (request.url.path.endsWith('/runtime-session')) {
        return _json(201, <String, Object?>{
          'token': _runtimeToken,
          'expires_in': 600,
        });
      }
      fail('Unexpected request: ${request.url}');
    });
    final GirlsAppPreviewApi api = GirlsAppPreviewApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final GirlsAppTestSession session = await api.createPublishedTest(
      accessToken: 'owner-token',
      groupId: _groupId,
      appId: _appId,
    );

    expect(
      session.contentUri.toString(),
      'https://hosted.example.test/hosted/content/$_contentToken/index.html',
    );
    expect(session.publishedVersion, 4);
    expect(session.sourceRevision, isNull);
    expect(session.runtimeToken, _runtimeToken);
    expect(
      paths,
      <String>[
        '/hosted/groups/$_groupId/apps/$_appId/published-session',
        '/hosted/groups/$_groupId/apps/$_appId/runtime-session',
      ],
    );
    expect(
      paths.where((String path) => path.contains('/launch-session')),
      isEmpty,
    );
  });

  test('draft preview uses owner preview capability plus runtime session', () async {
    final List<String> paths = <String>[];
    final MockClient client = MockClient((http.Request request) async {
      paths.add(request.url.path);
      expect(request.method, 'POST');
      expect(request.headers['authorization'], 'Bearer owner-token');
      expect(request.body, '{}');
      if (request.url.path == '/hosted/my/apps/$_appId/preview-session') {
        return _json(201, <String, Object?>{
          'app_id': _appId,
          'group_id': _groupId,
          'source_revision': 7,
          'content_path': '/hosted/preview/$_previewToken/index.html',
          'expires_in': 600,
        });
      }
      if (request.url.path.endsWith('/runtime-session')) {
        return _json(201, <String, Object?>{
          'token': _runtimeToken,
          'expires_in': 600,
        });
      }
      fail('Unexpected request: ${request.url}');
    });
    final GirlsAppPreviewApi api = GirlsAppPreviewApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final GirlsAppTestSession session = await api.createDraftPreview(
      accessToken: 'owner-token',
      groupId: _groupId,
      appId: _appId,
    );

    expect(
      session.contentUri.toString(),
      'https://hosted.example.test/hosted/preview/$_previewToken/index.html',
    );
    expect(session.sourceRevision, 7);
    expect(session.publishedVersion, isNull);
    expect(session.runtimeToken, _runtimeToken);
    expect(
      paths,
      <String>[
        '/hosted/my/apps/$_appId/preview-session',
        '/hosted/groups/$_groupId/apps/$_appId/runtime-session',
      ],
    );
  });
}
